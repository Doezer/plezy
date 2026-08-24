import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../media/ids.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../focus/locked_hub_controller.dart';
import '../media/library_query.dart';
import '../media/media_backend.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../mixins/paginated_item_loader.dart';
import '../mixins/standard_paginated_view.dart';
import '../providers/catalog_sources_provider.dart';
import '../services/catalog/catalog_source.dart';
import '../services/catalog/plex_catalog_source.dart';
import '../utils/app_logger.dart';
import '../utils/media_server_http_client.dart';
import '../utils/provider_extensions.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/hub_section.dart';
import '../widgets/optimized_media_image.dart';
import '../utils/media_image_helper.dart';
import '../i18n/strings.g.dart';
import 'base_media_list_detail_screen.dart';
import 'focusable_detail_screen_mixin.dart';
import '../mixins/grid_focus_node_mixin.dart';
import '../focus/focusable_action_bar.dart';

/// Screen to browse all media featuring a specific actor.
class ActorMediaScreen extends StatefulWidget {
  final String actorName;
  final String personId;

  final String? personKey;
  final String? actorThumb;
  final String? characterName;
  final String serverId;
  final String? serverName;
  final MediaBackend backend;

  const ActorMediaScreen({
    super.key,
    required this.actorName,
    required this.personId,
    this.personKey,
    this.actorThumb,
    this.characterName,
    required this.serverId,
    this.serverName,
    required this.backend,
  });

  @override
  State<ActorMediaScreen> createState() => _ActorMediaScreenState();
}

class _ActorMediaScreenState extends BaseMediaListDetailScreen<ActorMediaScreen>
    with
        GridFocusNodeMixin<ActorMediaScreen>,
        FocusableDetailScreenMixin<ActorMediaScreen>,
        PaginatedItemLoader<MediaItem, ActorMediaScreen>,
        PaginatedItemUpdatable<ActorMediaScreen>,
        StandardPaginatedView<MediaItem, ActorMediaScreen> {
  static const int _pageSize = 200;
  static const int _knownForLimit = 24;

  final _hubFocusMemory = HubFocusMemory();
  CatalogPersonInfo? _personInfo;
  List<MediaHub> _personHubs = const [];
  bool _personDataLoaded = false;

  CatalogSourcesProvider? _catalogSources;

  /// The Plex source [_loadPersonData] last attempted against, so a
  /// [CatalogSourcesProvider] notification (session hydration completing,
  /// a profile switch) only re-triggers the load when the source actually
  /// changed, rather than on every unrelated provider notification.
  PlexCatalogSource? _lastAttemptedPlexSource;

  @override
  MediaItem get mediaItem => MediaItem(
    id: '',
    backend: widget.backend,
    kind: MediaKind.unknown,
    serverId: widget.serverId,
    serverName: widget.serverName,
  );

  @override
  String get title => widget.actorName;

  @override
  String get emptyMessage => t.discover.noContentAvailable;

  @override
  bool get hasItems => totalSize > 0;

  @override
  void initState() {
    super.initState();
    _catalogSources = context.read<CatalogSourcesProvider?>();
    _catalogSources?.addListener(_onCatalogSourcesChanged);
    unawaited(_loadPersonData());
  }

  @override
  void dispose() {
    _catalogSources?.removeListener(_onCatalogSourcesChanged);
    disposePagination();
    disposeFocusResources();
    super.dispose();
  }

  MediaServerClient get _mediaClient => context.getMediaClientForServer(ServerId(widget.serverId));

  /// Session hydration (or a profile switch) can create the Plex Discover
  /// source after this screen has already given up on it once — retry then,
  /// deduped by source identity so an unrelated provider notification (a
  /// different account connecting) doesn't refetch.
  void _onCatalogSourcesChanged() {
    if (_personDataLoaded) return;
    final source = _catalogSources?.plexSource;
    if (source == null || identical(source, _lastAttemptedPlexSource)) return;
    unawaited(_loadPersonData());
  }

  /// Plex's cloud metadata for the person: the "Known For" shelf and the
  /// full filmography grouped by department (Actor, Director, Producer, …).
  /// Best-effort — no session, no [ActorMediaScreen.personKey], or a request
  /// failure all just leave the on-server grid as the whole screen.
  Future<void> _loadPersonData() async {
    final personKey = widget.personKey;
    if (widget.backend != MediaBackend.plex || personKey == null || personKey.isEmpty) return;
    final source = _catalogSources?.plexSource;
    if (source == null) return;
    _lastAttemptedPlexSource = source;

    try {
      final results = await Future.wait([
        source.fetchPersonInfo(personKey),
        source.fetchPersonKnownFor(personKey, limit: _knownForLimit),
        source.fetchPersonCredits(personKey),
      ]);
      // A profile switch or reconnect can rebind `_catalogSources.plexSource`
      // to a different source while this fetch was in flight. If that
      // happened, this call is stale — bail out rather than clobbering
      // whatever the newer source's own load already produced.
      if (!mounted || !identical(source, _catalogSources?.plexSource)) return;
      final info = results[0] as CatalogPersonInfo?;
      final knownFor = results[1] as CatalogPage;
      final creditGroups = results[2] as List<CatalogCreditGroup>;

      final hubs = <MediaHub>[
        if (knownFor.items.isNotEmpty)
          MediaHub(
            id: 'actor:$personKey:knownFor',
            // Not localized via i18n: Plex Discover's own filmography group
            // titles (below) come back in English regardless of app locale,
            // so this shelf label matches that rather than standing out as
            // the only translated string among them.
            title: 'Known For',
            type: 'mixed',
            items: [for (final item in knownFor.items) item.toMediaItem()],
            size: knownFor.totalResults ?? knownFor.items.length,
          ),
        for (final group in creditGroups)
          MediaHub(
            id: 'actor:$personKey:credits:${group.type ?? group.title}',
            title: group.title,
            type: 'mixed',
            items: [for (final credit in group.credits) credit.item.toMediaItem()],
            size: group.credits.length,
          ),
      ];

      setState(() {
        _personInfo = info;
        _personHubs = hubs;
        _personDataLoaded = true;
      });
    } catch (error, stackTrace) {
      appLogger.w('Failed to load Plex Discover person data', error: error, stackTrace: stackTrace);
      if (mounted && identical(source, _catalogSources?.plexSource)) {
        setState(() => _personDataLoaded = true);
      }
    }
  }

  @override
  Future<LibraryPage<MediaItem>> fetchPage(int start, int size, AbortController? abort) {
    return _mediaClient.fetchPersonMediaPage(widget.personId, start: start, size: size, abort: abort);
  }

  @override
  Future<void> loadItems() {
    return loadStandardPaginatedItems(
      pageSize: _pageSize,
      errorMessageFor: (error, stackTrace) {
        appLogger.e('Failed to load actor media', error: error, stackTrace: stackTrace);
        return t.messages.errorLoading(error: error.toString());
      },
      onLoaded: (loadedCount, totalCount) {
        appLogger.d('Loaded $loadedCount of $totalCount items for actor: ${widget.actorName}');
        autoFocusFirstItemAfterLoad();
      },
    );
  }

  @override
  List<FocusableAction> getAppBarActions() {
    return [];
  }

  Widget _buildActorHeader() {
    final theme = Theme.of(context);
    final summary = _personInfo?.summary;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(40),
                  child: OptimizedMediaImage(
                    client: _mediaClient,
                    imagePath: widget.actorThumb ?? _personInfo?.thumbUrl,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    imageType: ImageType.avatar,
                    fallbackIcon: Symbols.person_rounded,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text(
                        widget.actorName,
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: .bold),
                        maxLines: 2,
                        overflow: .ellipsis,
                      ),
                      if (widget.characterName != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.characterName!,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: .ellipsis,
                        ),
                      ],
                      if (totalSize > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          t.discover.titleCount(n: totalSize),
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (summary != null && summary.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(summary, style: theme.textTheme.bodyMedium, maxLines: 6, overflow: .ellipsis),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPersonHubSlivers() {
    return [
      for (final hub in _personHubs)
        if (hub.items.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: HubSection(
                key: ValueKey(hub.id),
                hub: hub,
                focusMemory: _hubFocusMemory,
                icon: Symbols.movie_rounded,
                inset: true,
              ),
            ),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return buildDetailScaffold(
      slivers: [
        CustomAppBar(title: Text(widget.actorName), pinned: true, actions: buildFocusableAppBarActions()),
        _buildActorHeader(),
        ...buildStateSlivers(),
        if (hasItems)
          buildSparseFocusableGrid(
            totalItems: totalSize,
            itemAt: (index) => loadedItems[index],
            onRefresh: updateItem,
            onSkeletonVisible: (index) => ensureIndexLoaded(index, pageSize: _pageSize),
          ),
        if (_personDataLoaded) ..._buildPersonHubSlivers(),
      ],
    );
  }
}
