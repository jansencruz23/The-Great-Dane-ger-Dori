// import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

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
    final isLandscape = screenSize.width > screenSize.height;

    // Convert face bounding box to screen coordinates
    final scaleX = screenSize.width / imageSize.width;
    final scaleY = screenSize.height / imageSize.height;

    final rect = face.boundingBox;

    // Calculate position relative to face
    double left;
    double top;
    double width = rect.width * scaleX;

    if (isLandscape) {
      // Landscape: Position to the RIGHT of the face
      width = 280; // Fixed width for landscape overlay
      left = (rect.right * scaleX) + 20;
      top = (rect.top * scaleY);

      // Check if there's enough space on the right
      if (left + width > screenSize.width) {
        // Position to the LEFT if no space on right
        left = (rect.left * scaleX) - width - 20;
      }
    } else {
      // Portrait: Position BELOW the face
      left = rect.left * scaleX;
      width = rect.width * scaleX;
      top = (rect.bottom * scaleY) + 20;

      // Check if there's enough space at the bottom
      if (top + 200 > screenSize.height) {
        top = (rect.top * scaleY) - 220; // Position above
      }
    }

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      left: left.clamp(10.0, screenSize.width - width - 10),
      top: top.clamp(40.0, screenSize.height - 250),
      child: SizedBox(
        width: width.clamp(200.0, screenSize.width - 40),
        child: _buildARBubble(context),
      ),
    );
  }

  Widget _buildARBubble(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.85),
        borderRadius: BorderRadius.circular(AppConstants.arBubbleRadius),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withOpacity(0.9),
            AppColors.secondary.withOpacity(0.7),
          ],
        ),
      ),
      padding: const EdgeInsets.all(AppConstants.arBubblePadding),
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
              shadows: [
                Shadow(
                  offset: Offset(0, 1),
                  blurRadius: 2,
                  color: Colors.black45,
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 4),

          // Relationship
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Text(
              knownFace.displayRelationship,
              style: const TextStyle(
                color: Colors.white,
                fontSize: AppConstants.arSubtextSize - 2,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(
                    offset: Offset(0, 1),
                    blurRadius: 2,
                    color: Colors.black26,
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(height: 8),

          // Last seen info
          Row(
            children: [
              const Icon(
                Icons.access_time,
                color: Colors.white,
                size: 14,
                shadows: [
                  Shadow(
                    offset: Offset(0, 1),
                    blurRadius: 2,
                    color: Colors.black26,
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _getLastSeenText(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppConstants.arSubtextSize - 2,
                    fontWeight: FontWeight.w500,
                    shadows: [
                      Shadow(
                        offset: Offset(0, 1),
                        blurRadius: 2,
                        color: Colors.black26,
                      ),
                    ],
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
                color: Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lightbulb_outline,
                    color: Color(0xFFFFD54F),
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
                  color: Colors.white70,
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  '${knownFace.interactionCount} ${knownFace.interactionCount == 1 ? 'conversation' : 'conversations'}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: AppConstants.arSubtextSize - 4,
                    fontWeight: FontWeight.w500,
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
              'Previous Interaction:',
              style: TextStyle(
                color: Colors.white,
                fontSize: AppConstants.arSubtextSize - 1,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                    offset: Offset(0, 1),
                    blurRadius: 2,
                    color: Colors.black26,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            ...recentLogs.take(1).map((log) {
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
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
                          color: Colors.white70,
                          size: 10,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          Helpers.getRelativeTime(log.timestamp),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: AppConstants.arSubtextSize - 4,
                            fontWeight: FontWeight.w500,
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
                          height: 1.3,
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
