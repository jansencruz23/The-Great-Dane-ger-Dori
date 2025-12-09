import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../utils/constants.dart';
import '../widgets/ar_overlay_widget.dart';

enum EnrollmentStep { promptEnrollment, collectingName, collectingRelationship }

class EnrollmentBubbleWidget extends StatefulWidget {
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
  State<EnrollmentBubbleWidget> createState() => _EnrollmentBubbleWidgetState();
}

class _EnrollmentBubbleWidgetState extends State<EnrollmentBubbleWidget> {
  // Smoothed position values
  double _smoothLeft = 0;
  double _smoothTop = 0;
  bool _isInitialized = false;

  // Smooth animation parameters
  static const double _smoothingFactor = 0.3; // Higher = faster response

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(EnrollmentBubbleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Trigger smooth update when face position changes
    if (oldWidget.face.boundingBox != widget.face.boundingBox) {
      _updateSmoothPosition();
    }
  }

  void _updateSmoothPosition() {
    final screenSize = MediaQuery.of(context).size;
    final scaleX = screenSize.width / widget.imageSize.width;
    final scaleY = screenSize.height / widget.imageSize.height;
    final rect = widget.face.boundingBox;
    const double width = 120;

    // Calculate target position
    double targetLeft = (rect.right * scaleX) + 15;
    double targetTop = (rect.top * scaleY);

    // Check if there's enough space on the right
    if (targetLeft + width > screenSize.width) {
      targetLeft = (rect.left * scaleX) - width - 15;
    }

    // Clamp values
    targetLeft = targetLeft.clamp(10.0, screenSize.width - width - 10);
    targetTop = targetTop.clamp(60.0, screenSize.height - 100);

    // Apply smoothing using lerp
    if (_isInitialized) {
      setState(() {
        _smoothLeft =
            _smoothLeft + (_smoothingFactor * (targetLeft - _smoothLeft));
        _smoothTop = _smoothTop + (_smoothingFactor * (targetTop - _smoothTop));
      });
    } else {
      // First frame - set directly
      setState(() {
        _smoothLeft = targetLeft;
        _smoothTop = targetTop;
        _isInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;

    // Convert face bounding box to screen coordinates
    final scaleX = screenSize.width / widget.imageSize.width;
    final scaleY = screenSize.height / widget.imageSize.height;

    final rect = widget.face.boundingBox;

    // Calculate position relative to face - TINY bubble
    double targetLeft;
    double targetTop;
    double width = 120; // Much smaller fixed width

    ArrowDirection arrowDirection;
    double arrowOffset;

    if (isLandscape) {
      // Landscape: Position to the RIGHT of the face
      targetLeft = (rect.right * scaleX) + 15;
      targetTop = (rect.top * scaleY);
      arrowDirection = ArrowDirection.left;
      arrowOffset = (rect.height * scaleY) / 2;

      // Check if there's enough space on the right
      if (targetLeft + width > screenSize.width) {
        // Position to the LEFT if no space on right
        targetLeft = (rect.left * scaleX) - width - 15;
        arrowDirection = ArrowDirection.right;
      }
    } else {
      // Portrait: Position to the RIGHT of the face (not below)
      targetLeft = (rect.right * scaleX) + 15;
      targetTop = (rect.top * scaleY);
      arrowDirection = ArrowDirection.left;
      arrowOffset = (rect.height * scaleY) / 2;

      // Check if there's enough space on the right
      if (targetLeft + width > screenSize.width) {
        // Position to the LEFT if no space on right
        targetLeft = (rect.left * scaleX) - width - 15;
        arrowDirection = ArrowDirection.right;
      }
    }

    // Clamp values
    targetLeft = targetLeft.clamp(10.0, screenSize.width - width - 10);
    targetTop = targetTop.clamp(60.0, screenSize.height - 100);

    // Initialize or update smooth position
    if (!_isInitialized) {
      _smoothLeft = targetLeft;
      _smoothTop = targetTop;
      _isInitialized = true;
    } else {
      // Lerp towards target for smooth following
      _smoothLeft =
          _smoothLeft + (_smoothingFactor * (targetLeft - _smoothLeft));
      _smoothTop = _smoothTop + (_smoothingFactor * (targetTop - _smoothTop));
    }

    // Use simple Positioned - lerp already provides smoothing
    return Positioned(
      left: _smoothLeft,
      top: _smoothTop,
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
    switch (widget.step) {
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
            Icon(Icons.favorite, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              'How do you',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Text(
          'feel about',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'this person?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (widget.isListening) ...[
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mic, color: Colors.red[300], size: 10),
              const SizedBox(width: 3),
              Text(
                'Safe/Unsure',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
        if (widget.voiceBuffer != null && widget.voiceBuffer!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            '"${widget.voiceBuffer}"',
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
        if (widget.isListening) ...[
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
            (widget.voiceBuffer != null && widget.voiceBuffer!.isNotEmpty)
                ? widget.voiceBuffer!
                : 'Listening...',
            style: TextStyle(
              color:
                  (widget.voiceBuffer != null && widget.voiceBuffer!.isNotEmpty)
                  ? Colors.white
                  : Colors.white.withOpacity(0.4), // Dimmer placeholder
              fontSize: 10,
              fontStyle:
                  (widget.voiceBuffer == null || widget.voiceBuffer!.isEmpty)
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
