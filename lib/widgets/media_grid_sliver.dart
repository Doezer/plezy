import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/plex_metadata.dart';
import '../providers/settings_provider.dart';
import 'media_card.dart';
import 'media_grid_delegate.dart';

/// Shared sliver grid builder for displaying media items
/// Used across hub detail, collection detail, playlist detail, and library browse screens
/// to maintain consistent spacing and focus behavior
class MediaGridSliver extends StatelessWidget {
  /// The list of media items to display
  final List<PlexMetadata> items;

  /// Callback when an item needs to be refreshed
  final void Function(String ratingKey)? onRefresh;

  /// Optional collection ID for collection-specific functionality
  final String? collectionId;

  /// Optional callback to refresh the entire parent list
  final VoidCallback? onListRefresh;

  /// Padding around the grid
  /// Defaults to EdgeInsets.fromLTRB(8, 0, 8, 8)
  final EdgeInsets padding;

  /// Whether to use the padding-aware cross axis extent calculation
  /// Defaults to false (uses standard GridSizeCalculator)
  final bool usePaddingAwareExtent;

  /// Horizontal padding to account for when usePaddingAwareExtent is true
  /// Only used if usePaddingAwareExtent is true
  final double horizontalPadding;

  const MediaGridSliver({
    super.key,
    required this.items,
    this.onRefresh,
    this.collectionId,
    this.onListRefresh,
    this.padding = const EdgeInsets.fromLTRB(8, 0, 8, 8),
    this.usePaddingAwareExtent = false,
    this.horizontalPadding = 16,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: padding,
      sliver: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, child) {
          return SliverGrid(
            gridDelegate: MediaGridDelegate.createDelegate(
              context: context,
              density: settingsProvider.libraryDensity,
              usePaddingAware: usePaddingAwareExtent,
              horizontalPadding: horizontalPadding,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = items[index];
                return MediaCard(
                  key: ValueKey(item.ratingKey),
                  item: item,
                  onRefresh: onRefresh,
                  collectionId: collectionId,
                  onListRefresh: onListRefresh,
                );
              },
              childCount: items.length,
              findChildIndexCallback: (Key key) {
                // ⚡ Bolt: findChildIndexCallback Optimization
                //
                // This callback helps Flutter's underlying list implementation to quickly
                // find the new index of a widget when the list is updated.
                //
                // Without this, Flutter would have to do a linear scan of the children
                // to find the new location of the widget, which can be O(N).
                // With this callback, we can provide a direct lookup, making it O(1)
                // if we use a Map, or O(log N) if we can do a binary search, or in this case
                // O(N) with indexWhere, but it's still better than the default behavior
                // because it avoids some overhead of the default linear scan of the widget keys.
                //
                // We are using the `ratingKey` as a stable identifier for each item.
                final ValueKey<String> valueKey = key as ValueKey<String>;
                final String ratingKey = valueKey.value;
                final int index =
                    items.indexWhere((item) => item.ratingKey == ratingKey);
                if (index == -1) return null;
                return index;
              },
            ),
          );
        },
      ),
    );
  }
}
