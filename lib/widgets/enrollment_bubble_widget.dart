import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../utils/constants.dart';
import '../widgets/ar_overlay_widget.dart';

enum EnrollmentStep { promptEnrollment, collectingName, collectingRelationship }

class EnrollmentBubbleWidget extends StatelessWidget {
  final Face face;
  final Size imageSize;
  final EnrollmentStep step;
  final String? voiceBuffer;
  final bool isListening;
  final VoidCallback? onYes;
  final VoidCallback? onNo;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  const EnrollmentBubbleWidget({
    super.key,
    required this.face,
    required this.imageSize,
    required this.step,
    this.voiceBuffer,
    this.isListening = false,
    this.onYes,
    this.onNo,
    this.onConfirm,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;

    // Convert face bounding box to screen coordinates
    final scaleX = screenSize.width / imageSize.width;
    final scaleY = screenSize.height / imageSize.height;

    final rect = face.boundingBox;

    // Calculate position relative to face - TINY bubble
    double left;
    double top;
    double width = 120; // Much smaller fixed width

    ArrowDirection arrowDirection;
    double arrowOffset;

    if (isLandscape) {
      // Landscape: Position to the RIGHT of the face
      left = (rect.right * scaleX) + 15;
      top = (rect.top * scaleY);
      arrowDirection = ArrowDirection.left;
      arrowOffset = (rect.height * scaleY) / 2;

      // Check if there's enough space on the right
      if (left + width > screenSize.width) {
        // Position to the LEFT if no space on right
        left = (rect.left * scaleX) - width - 15;
        arrowDirection = ArrowDirection.right;
      }
    } else {
      // Portrait: Position to the RIGHT of the face (not below)
      left = (rect.right * scaleX) + 15;
      top = (rect.top * scaleY);
      arrowDirection = ArrowDirection.left;
      arrowOffset = (rect.height * scaleY) / 2;

      // Check if there's enough space on the right
      if (left + width > screenSize.width) {
        // Position to the LEFT if no space on right
        left = (rect.left * scaleX) - width - 15;
        arrowDirection = ArrowDirection.right;
      }
    }

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      left: left.clamp(10.0, screenSize.width - width - 10),
      top: top.clamp(60.0, screenSize.height - 100),
      child: SizedBox(
        width: width,
        child: _buildBubbleWithArrow(context, arrowDirection, arrowOffset),
      ),
    );
  }

  Widget _buildBubbleWithArrow(
    BuildContext context,
    ArrowDirection direction,
    double offset,
  ) {
    const double arrowSize = 8.0;
    const double arrowBase = 12.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [_buildBubbleContent(context)],
    );
  }

  Widget _buildBubbleContent(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withOpacity(0.95),
            AppColors.secondary.withOpacity(0.85),
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: _buildStepContent(context),
    );
  }

  Widget _buildStepContent(BuildContext context) {
    switch (step) {
      case EnrollmentStep.promptEnrollment:
        return _buildPromptContent(context);
      case EnrollmentStep.collectingName:
        return _buildInputContent(context, 'Name?');
      case EnrollmentStep.collectingRelationship:
        return _buildInputContent(context, 'Relation?');
    }
  }

  Widget _buildPromptContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_add, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              'Recognize this',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Text(
          'person?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (isListening) ...[
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mic, color: Colors.red[300], size: 10),
              const SizedBox(width: 3),
              Text(
                'Yes/No',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
        if (voiceBuffer != null && voiceBuffer!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            '"$voiceBuffer"',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _buildInputContent(BuildContext context, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (isListening) ...[
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mic, color: Colors.red[300], size: 10),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  '',
                  style: TextStyle(color: Colors.red[300], fontSize: 8),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(
              0.2,
            ), // Darker background for "disabled" look
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Colors.white.withOpacity(0.2), // Dimmer border
              width: 1,
            ),
          ),
          child: Text(
            (voiceBuffer != null && voiceBuffer!.isNotEmpty)
                ? voiceBuffer!
                : 'Listening...',
            style: TextStyle(
              color: (voiceBuffer != null && voiceBuffer!.isNotEmpty)
                  ? Colors.white
                  : Colors.white.withOpacity(0.4), // Dimmer placeholder
              fontSize: 10,
              fontStyle: (voiceBuffer == null || voiceBuffer!.isEmpty)
                  ? FontStyle.italic
                  : FontStyle.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// Reuse ArrowPainter from ar_overlay_widget.dart
class ArrowPainter extends CustomPainter {
  final Color color;
  final ArrowDirection direction;

  ArrowPainter({required this.color, required this.direction});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    switch (direction) {
      case ArrowDirection.left:
        path.moveTo(size.width, 0);
        path.lineTo(0, size.height / 2);
        path.lineTo(size.width, size.height);
        break;
      case ArrowDirection.right:
        path.moveTo(0, 0);
        path.lineTo(size.width, size.height / 2);
        path.lineTo(0, size.height);
        break;
      case ArrowDirection.top:
        path.moveTo(0, size.height);
        path.lineTo(size.width / 2, 0);
        path.lineTo(size.width, size.height);
        break;
      case ArrowDirection.bottom:
        path.moveTo(0, 0);
        path.lineTo(size.width / 2, size.height);
        path.lineTo(size.width, 0);
        break;
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
