import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

import '../models/known_face_model.dart';
import '../models/activity_log_model.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';

class ArOverlayWidget extends StatelessWidget {
  final Face face;
  final KnownFaceModel knownFace;
  final Size imageSize;
  final List<ActivityLogModel> recentLogs;

  const ArOverlayWidget({
    super.key,
    required this.face,
    required this.knownFace,
    required this.imageSize,
    this.recentLogs = const [],
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    // Convert face bounding box to screen coordinates
    // The face coordinates come from the image stream.
    // If the image stream is 640x480 (landscape) but the screen is portrait,
    // ML Kit coordinates need to be mapped.

    // However, we are passing the PREVIEW size as imageSize.
    // CameraController.value.previewSize is the size of the preview texture.

    // If the preview is rotated (e.g. Android portrait), width/height might be swapped
    // relative to screen.

    // Simple heuristic: if screen is portrait but image is landscape (or vice versa),
    // we might need to swap dimensions for scaling calculation IF the preview isn't already rotated.
    // But CameraPreview usually handles rotation.

    // Let's rely on the fact that we want to map the relative position.

    final rect = face.boundingBox;

    // Calculate position
    // We'll use a safer scaling approach that covers the screen (BoxFit.cover equivalent)

    // Determine the scale factor used by the CameraPreview to cover the screen
    double scale;
    if (screenSize.aspectRatio > imageSize.aspectRatio) {
      // Screen is wider than image (relative to their own axes)
      // Fit width
      scale = screenSize.width / imageSize.width;
    } else {
      // Screen is taller
      // Fit height
      scale = screenSize.height / imageSize.height;
    }

    // If we are in landscape, we might need to adjust if the coordinates are rotated.
    // But ML Kit usually returns coordinates in the image frame.
    // If we passed rotation to ML Kit, it might rotate coordinates?
    // No, ML Kit returns coordinates in the unrotated image usually, unless we use the metadata correctly.

    // Actually, if we pass rotation to ML Kit, it processes the image "upright".
    // The coordinates returned are in the coordinate system of the "upright" image.

    // If we are in landscape, and the device is landscape, the image is likely already "upright" (0 deg rotation).
    // So coordinates should map directly.

    // Let's try using the calculated scale.

    // Center the image on screen
    final double offsetX = (screenSize.width - imageSize.width * scale) / 2;
    final double offsetY = (screenSize.height - imageSize.height * scale) / 2;

    final left = (rect.left * scale) + offsetX;
    final top = ((rect.top * scale) + offsetY) - 120; // Position above face
    final width = rect.width * scale;

    return Positioned(
      left: left,
      top: top.clamp(60.0, screenSize.height - 200),
      child: SizedBox(
        width: width.clamp(200.0, screenSize.width - 40),
        child: _buildARBubble(context),
      ),
    );
  }

  Widget _buildARBubble(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.arOverlay.withOpacity(AppConstants.arBubbleOpacity),
        borderRadius: BorderRadius.circular(AppConstants.arBubbleRadius),
        border: Border.all(color: AppColors.arOverlayBorder, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name
          Text(
            knownFace.displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: AppConstants.arTextSize,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 4),

          // Relationship
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.arOverlayBorder.withValues(alpha: .3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              knownFace.displayRelationship,
              style: const TextStyle(
                color: Colors.white,
                fontSize: AppConstants.arSubtextSize - 2,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(height: 8),

          // Last seen info
          Row(
            children: [
              const Icon(Icons.access_time, color: Colors.white70, size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _getLastSeenText(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: AppConstants.arSubtextSize - 2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          // Notes if available
          if (knownFace.notes != null && knownFace.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lightbulb_outline,
                    color: Colors.amber,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      knownFace.notes!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: AppConstants.arSubtextSize - 2,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Interaction count
          if (knownFace.interactionCount > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.chat_bubble_outline,
                  color: Colors.white60,
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  '${knownFace.interactionCount} ${knownFace.interactionCount == 1 ? 'conversation' : 'conversations'}',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: AppConstants.arSubtextSize - 4,
                  ),
                ),
              ],
            ),
          ],

          // Recent summaries
          if (recentLogs.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white30, height: 1),
            const SizedBox(height: 8),
            const Text(
              'Recent Interactions:',
              style: TextStyle(
                color: Colors.white,
                fontSize: AppConstants.arSubtextSize - 1,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            ...recentLogs.take(3).map((log) {
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .15),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule,
                          color: Colors.white54,
                          size: 10,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          Helpers.getRelativeTime(log.timestamp),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: AppConstants.arSubtextSize - 4,
                          ),
                        ),
                      ],
                    ),
                    if (log.hasSummary) ...[
                      const SizedBox(height: 4),
                      Text(
                        log.summary!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: AppConstants.arSubtextSize - 2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  String _getLastSeenText() {
    if (knownFace.lastSeenAt == null) {
      return 'First time seeing today';
    }

    return '${AppStrings.lastSeen} ${Helpers.getRelativeTime(knownFace.lastSeenAt!)}';
  }
}
