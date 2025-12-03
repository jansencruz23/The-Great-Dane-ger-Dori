import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../utils/constants.dart';

class FaceDetectionPainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;

  FaceDetectionPainter({required this.faces, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = AppColors.arOverlayBorder;

    final Paint fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = AppColors.arOverlayBorder.withValues(alpha: .1);

    for (final face in faces) {
      // Scale face bounding box to screen size
      final scaleX = size.width / imageSize.width;
      final scaleY = size.height / imageSize.height;

      final rect = Rect.fromLTRB(
        face.boundingBox.left * scaleX,
        face.boundingBox.top * scaleY,
        face.boundingBox.right * scaleX,
        face.boundingBox.bottom * scaleY,
      );

      // Draw rounded rectangle
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));

      canvas.drawRRect(rrect, fillPaint);
      canvas.drawRRect(rrect, paint);

      // Draw corner accents for better visibility
      _drawCornerAccents(canvas, rect, paint);

      // Draw facial landmarks if available
      if (face.landmarks.isNotEmpty) {
        _drawLandmarks(canvas, face, scaleX, scaleY);
      }
    }
  }

  void _drawCornerAccents(Canvas canvas, Rect rect, Paint paint) {
    final accentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..color = AppColors.arOverlayBorder;

    const cornerLength = 20.0;

    // Top-left corner
    canvas.drawLine(
      Offset(rect.left, rect.top),
      Offset(rect.left + cornerLength, rect.top),
      accentPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.top),
      Offset(rect.left, rect.top + cornerLength),
      accentPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(rect.right, rect.top),
      Offset(rect.right - cornerLength, rect.top),
      accentPaint,
    );
    canvas.drawLine(
      Offset(rect.right, rect.top),
      Offset(rect.right, rect.top + cornerLength),
      accentPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(rect.left, rect.bottom),
      Offset(rect.left + cornerLength, rect.bottom),
      accentPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.bottom),
      Offset(rect.left, rect.bottom - cornerLength),
      accentPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(rect.right, rect.bottom),
      Offset(rect.right - cornerLength, rect.bottom),
      accentPaint,
    );
    canvas.drawLine(
      Offset(rect.right, rect.bottom),
      Offset(rect.right, rect.bottom - cornerLength),
      accentPaint,
    );
  }

  void _drawLandmarks(Canvas canvas, Face face, double scaleX, double scaleY) {
    final landmarkPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = AppColors.accent;

    for (final landmark in face.landmarks.values) {
      if (landmark != null) {
        final position = landmark.position;
        canvas.drawCircle(
          Offset(position.x * scaleX, position.y * scaleY),
          3,
          landmarkPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(FaceDetectionPainter oldDelegate) {
    return oldDelegate.faces != faces || oldDelegate.imageSize != imageSize;
  }
}
