import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../models/plex_metadata.dart';
import '../utils/plex_image_helper.dart';
import '../utils/provider_extensions.dart';
import '../widgets/app_bar_back_button.dart';
import '../utils/desktop_window_padding.dart';
import '../widgets/placeholder_container.dart';
import '../providers/download_provider.dart';
import 'dart:io';

class PhotoViewerScreen extends StatelessWidget {
  final PlexMetadata metadata;
  final bool isOffline;

  const PhotoViewerScreen({super.key, required this.metadata, this.isOffline = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Center the image
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Builder(
                builder: (context) {
                  // Check for offline local file first
                  if (isOffline && metadata.serverId != null) {
                    final thumbPath = metadata.thumb;

                    if (thumbPath != null) {
                      final localThumbPath = context.read<DownloadProvider>().getArtworkLocalPath(
                            metadata.serverId!,
                            thumbPath,
                          );
                      if (localThumbPath != null && File(localThumbPath).existsSync()) {
                        return Image.file(
                          File(localThumbPath),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const PlaceholderContainer(),
                        );
                      }
                    }
                    // Fallback if offline file not found
                    return const PlaceholderContainer();
                  }

                  // Online - use network image
                  if (metadata.serverId == null) {
                    return const PlaceholderContainer();
                  }

                  final client = context.getClientForServer(metadata.serverId!);

                  // For photos, we try to get the original stream or a high res transcode.
                  final mediaQuery = MediaQuery.of(context);
                  final imageUrl = PlexImageHelper.getOptimizedImageUrl(
                    client: client,
                    thumbPath: metadata.thumb,
                    maxWidth: mediaQuery.size.width * 2, // Double resolution for zoom
                    maxHeight: mediaQuery.size.height * 2,
                    devicePixelRatio: mediaQuery.devicePixelRatio,
                    imageType: ImageType.art,
                  );

                  return CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                    errorWidget: (context, url, error) => const PlaceholderContainer(),
                  );
                },
              ),
            ),
          ),

          // Back button and title overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(8.0),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    DesktopAppBarHelper.buildAdjustedLeading(
                      AppBarBackButton(
                        style: BackButtonStyle.circular,
                        onPressed: () => Navigator.pop(context),
                      ),
                      context: context,
                    )!,
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        metadata.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
