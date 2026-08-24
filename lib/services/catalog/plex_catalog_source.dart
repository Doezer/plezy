import '../../media/media_kind.dart';
import '../../models/catalog/catalog_cast_member.dart';
import '../../models/catalog/catalog_item.dart';
import '../../utils/external_ids.dart';
import '../../utils/app_logger.dart';
import '../../utils/json_utils.dart';
import '../plex_discover_client.dart';
import 'catalog_source.dart';
import 'catalog_watchlist_machinery.dart';
import 'plex_discover_metadata_mapper.dart';

/// [CatalogSource] backed by the active Plex profile's universal watchlist
/// and Discover's Home shelves (what Plex's own web client shows on its
/// Home ▸ Trending tab).
class PlexCatalogSource with CatalogWatchlistMachinery implements CatalogSource, CatalogHubSource, CatalogPersonSource {
  final PlexDiscoverClient _client;
  final bool includeImageVariants;
  final Map<String, String> _hubKeys = {};

  PlexCatalogSource(this._client, {this.includeImageVariants = false});

  @override
  CatalogSourceId get id => CatalogSourceId.plex;

  @override
  String get displayName => 'Plex';

  @override
  List<CatalogRowId> get supportedRows => const [CatalogRowId.watchlist];

  @override
  bool get supportsWatchlist => true;

  @override
  String get watchlistLogLabel => 'Plex: watchlist';

  // Discover validates X-Plex-Container-Size against a cap it drifts
  // without notice (#1715: 500 became invalid). 100 keeps the snapshot at
  // few requests while staying well under the observed cap, and the client
  // degrades to 25-item chunks if the cap ever drops below it; more pages
  // preserve the 5000-entry coverage.
  @override
  int get watchlistPageLimit => 100;

  @override
  int get watchlistMaxPages => 50;

  @override
  Future<CatalogPage> fetchRow(CatalogRowId row, {int page = 1, int limit = 25}) async {
    if (row != CatalogRowId.watchlist) throw ArgumentError('Plex does not serve ${row.name}');
    final response = await _client.getWatchlist(page: page, limit: limit);
    return CatalogPage(
      items: _fromMetadata(response.items),
      hasMore: response.hasMore,
      totalResults: response.totalResults,
    );
  }

  @override
  Future<List<CatalogHub>> fetchHubs({int limit = 25}) async {
    final fetched = await _client.getHomeHubs(limit: limit, includeImageVariants: includeImageVariants);
    final keys = <String, String>{};
    final result = <CatalogHub>[];
    for (final hub in fetched) {
      final items = _fromMetadata(hub.page.items);
      if (items.isEmpty) continue;
      final style = _hubStyleFor(hub.style);
      keys[hub.id] = hub.key;
      result.add(
        CatalogHub(
          id: hub.id,
          title: hub.title,
          style: style,
          page: CatalogPage(items: items, hasMore: hub.page.hasMore, totalResults: hub.page.totalResults),
        ),
      );
    }
    _hubKeys
      ..clear()
      ..addAll(keys);
    return result;
  }

  /// Discover serves a hub in one shot — it ignores container offsets — so
  /// View All has nothing to page into beyond the first request.
  @override
  Future<CatalogPage> fetchHub(String id, {int page = 1, int limit = 25}) async {
    final key = _hubKeys[id];
    if (key == null || page > 1) return const CatalogPage(items: []);
    final response = await _client.getHub(key, limit: limit, includeImageVariants: includeImageVariants);
    return CatalogPage(items: _fromMetadata(response.items), hasMore: false, totalResults: response.totalResults);
  }

  @override
  Future<List<CatalogItem>> search(String query, {int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    return _fromSearchResults(await _client.search(trimmed, limit: limit));
  }

  @override
  Future<CatalogItemIds?> resolveItemIds(MediaKind kind, ExternalIds external) async {
    // Plex Discover matches on imdb/tmdb/tvdb only; an AniDB-only item has
    // nothing to send it.
    if (!external.hasCatalogIds) return null;
    final metadata = await _client.match(external);
    final matchedKind = metadata == null ? null : plexDiscoverKindFor(metadata['type']);
    if (metadata == null || matchedKind != kind) return null;
    final ids = plexDiscoverIdsFor(metadata);
    if (ids.plex == null) return null;
    return CatalogItemIds(
      plex: ids.plex,
      imdb: ids.imdb ?? external.imdb,
      tmdb: ids.tmdb ?? external.tmdb,
      tvdb: ids.tvdb ?? external.tvdb,
    );
  }

  @override
  Future<CatalogItemIds> resolveWatchlistMutationIds(MediaKind kind, CatalogItemIds ids) async {
    if (ids.plex != null && ids.plex!.isNotEmpty) return ids;
    final resolved = await resolveItemIds(kind, ids.toExternalIds());
    if (resolved?.plex == null || resolved!.plex!.isEmpty) {
      throw StateError('Plex: no rating key for ${ids.canonicalKey ?? 'item'}');
    }
    return resolved;
  }

  @override
  Future<CatalogDetail> fetchDetail(CatalogItem item, {int castLimit = 20, int relatedLimit = 20}) async {
    final ratingKey = item.ids.plex;
    if (ratingKey == null || ratingKey.isEmpty) return CatalogDetail(item: item);

    final metadataFuture = _loadDetailMetadata(ratingKey);
    final relatedFuture = _loadRelatedMetadata(ratingKey);
    final metadata = await metadataFuture;
    final relatedMetadata = await relatedFuture;
    final detailItem = metadata == null ? null : _toCatalogItem(metadata);
    final safeCastLimit = castLimit < 0 ? 0 : castLimit;
    final safeRelatedLimit = relatedLimit < 0 ? 0 : relatedLimit;

    return CatalogDetail(
      item: detailItem == null ? item : item.enrichedWith(detailItem),
      cast: metadata == null
          ? const []
          : [
              for (final role in flexibleMapList(metadata['Role']).take(safeCastLimit))
                if (_nonEmptyString(role['tag'] ?? role['name']) case final String name)
                  CatalogCastMember(
                    name: name,
                    secondary: _nonEmptyString(role['role']),
                    imageUrl: _nonEmptyString(role['thumb']),
                  ),
            ],
      related: _fromMetadata(relatedMetadata).take(safeRelatedLimit).toList(),
    );
  }

  Future<Map<String, dynamic>?> _loadDetailMetadata(String ratingKey) async {
    try {
      return await _client.getMetadata(ratingKey);
    } catch (error, stackTrace) {
      appLogger.w('Plex: detail metadata failed', error: error, stackTrace: stackTrace);
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _loadRelatedMetadata(String ratingKey) async {
    try {
      return await _client.getRelated(ratingKey);
    } catch (error, stackTrace) {
      appLogger.w('Plex: related metadata failed', error: error, stackTrace: stackTrace);
      return const [];
    }
  }

  @override
  Future<WatchlistKeyPage> fetchWatchlistKeyPage(int page, int limit) async {
    final response = await _client.getWatchlist(page: page, limit: limit);
    return (
      groups: [for (final item in _fromMetadata(response.items)) membershipKeysFor(item.kind, item.ids)],
      hasMore: response.hasMore,
    );
  }

  @override
  Future<void> performWatchlistMutation(MediaKind kind, CatalogItemIds ids, {required bool add}) async {
    final ratingKey = ids.plex;
    if (ratingKey == null || ratingKey.isEmpty) {
      throw ArgumentError('Plex watchlist mutations require a Plex rating key');
    }
    await _client.setWatchlisted(ratingKey, add: add);
  }

  List<CatalogItem> _fromMetadata(List<Map<String, dynamic>> metadata) {
    final items = <CatalogItem>[];
    final seen = <String>{};
    for (final value in metadata) {
      final item = _toCatalogItem(value);
      if (item != null && seen.add(item.identityKey)) items.add(item);
    }
    return items;
  }

  List<CatalogItem> _fromSearchResults(List<PlexDiscoverSearchResult> results) {
    final items = <CatalogItem>[];
    final seen = <String>{};
    for (final result in results) {
      final item = _toCatalogItem(result.metadata);
      if (item != null && seen.add(item.identityKey)) items.add(item);
    }
    return items;
  }

  CatalogItem? _toCatalogItem(Map<String, dynamic> metadata) => plexDiscoverItemFromMetadata(metadata);

  static CatalogHubStyle? _hubStyleFor(Object? style) => switch (style) {
    'shelf' => CatalogHubStyle.shelf,
    'availabilityPlatforms' => CatalogHubStyle.availabilityPlatforms,
    _ => null,
  };

  static String? _nonEmptyString(Object? value) {
    final string = value?.toString().trim();
    return string == null || string.isEmpty ? null : string;
  }

  @override
  Future<CatalogPersonInfo?> fetchPersonInfo(String personId) async {
    final metadata = await _client.getPersonInfo(personId);
    if (metadata == null) return null;
    final name = _nonEmptyString(metadata['title']);
    if (name == null) return null;

    String? avatar;
    String? poster;
    for (final image in flexibleMapList(metadata['Image'])) {
      final type = _nonEmptyString(image['type']);
      final url = _nonEmptyString(image['url']);
      if (type == null || url == null) continue;
      if (type == 'avatar') avatar ??= url;
      if (type == 'coverPoster') poster ??= url;
    }

    return CatalogPersonInfo(
      name: name,
      summary: _nonEmptyString(metadata['summary']),
      thumbUrl: _nonEmptyString(metadata['thumb']) ?? avatar,
      posterUrl: poster,
      birthPlace: _nonEmptyString(metadata['birthPlace']),
      bornAt: _dateOnly(metadata['bornAt']),
      creditCounts: [
        for (final entry in flexibleMapList(metadata['CreditType']))
          if (_nonEmptyString(entry['type']) case final String type)
            if (_nonEmptyString(entry['title']) case final String title)
              (type: type, title: title, count: flexibleInt(entry['count']) ?? 0),
      ],
    );
  }

  @override
  Future<CatalogPage> fetchPersonKnownFor(String personId, {int limit = 24}) async {
    final page = await _client.getPersonKnownFor(personId, limit: limit);
    return CatalogPage(items: _fromMetadata(page.items), hasMore: page.hasMore, totalResults: page.totalResults);
  }

  @override
  Future<List<CatalogCreditGroup>> fetchPersonCredits(String personId) async {
    final groups = await _client.getPersonCredits(personId);
    final result = <CatalogCreditGroup>[];
    for (final group in groups) {
      final credits = <CatalogPersonCredit>[];
      final seen = <String>{};
      for (final credit in group.credits) {
        final item = _toCatalogItem(credit.metadata);
        if (item != null && seen.add(item.identityKey)) {
          credits.add(CatalogPersonCredit(role: credit.role, item: item));
        }
      }
      if (credits.isNotEmpty) result.add(CatalogCreditGroup(title: group.title, type: group.type, credits: credits));
    }
    return result;
  }

  static DateTime? _dateOnly(Object? value) => value is String ? DateTime.tryParse(value) : null;

  @override
  void dispose() {
    disposeWatchlistMachinery();
    _client.dispose();
  }
}
