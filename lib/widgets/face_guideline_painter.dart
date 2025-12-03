import 'package:flutter/material.dart';
import '../utils/constants.dart';

class FaceGuidelinePainter extends CustomPainter {
  final Color? color;

  FaceGuidelinePainter({this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Define the guideline area (oval)
    // Adjust size based on orientation
    final isPortrait = size.height > size.width;
    final width = isPortrait ? size.width * 0.65 : size.height * 0.5;
    final height = isPortrait ? size.height * 0.45 : size.height * 0.7;

    final rect = Rect.fromCenter(center: center, width: width, height: height);

    // 1. Draw semi-transparent oval
    final ovalPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Use a dashed effect for the oval (optional, but simple stroke is fine)
    canvas.drawOval(rect, ovalPaint);

    // 2. Draw corner brackets for emphasis
    final bracketPaint = Paint()
      ..color = (color ?? AppColors.primary).withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final bracketLength = 40.0;
    final cornerRadius = 20.0;

    // Top Left
    final pathTL = Path()
      ..moveTo(rect.left, rect.top + bracketLength)
      ..lineTo(rect.left, rect.top + cornerRadius)
      ..quadraticBezierTo(
        rect.left,
        rect.top,
        rect.left + cornerRadius,
        rect.top,
      )
      ..lineTo(rect.left + bracketLength, rect.top);
    canvas.drawPath(pathTL, bracketPaint);

    // Top Right
    final pathTR = Path()
      ..moveTo(rect.right - bracketLength, rect.top)
      ..lineTo(rect.right - cornerRadius, rect.top)
      ..quadraticBezierTo(
        rect.right,
        rect.top,
        rect.right,
        rect.top + cornerRadius,
      )
      ..lineTo(rect.right, rect.top + bracketLength);
    canvas.drawPath(pathTR, bracketPaint);

    // Bottom Right
    final pathBR = Path()
      ..moveTo(rect.right, rect.bottom - bracketLength)
      ..lineTo(rect.right, rect.bottom - cornerRadius)
      ..quadraticBezierTo(
        rect.right,
        rect.bottom,
        rect.right - cornerRadius,
        rect.bottom,
      )
      ..lineTo(rect.right - bracketLength, rect.bottom);
    canvas.drawPath(pathBR, bracketPaint);

    // Bottom Left
    final pathBL = Path()
      ..moveTo(rect.left + bracketLength, rect.bottom)
      ..lineTo(rect.left + cornerRadius, rect.bottom)
      ..quadraticBezierTo(
        rect.left,
        rect.bottom,
        rect.left,
        rect.bottom - cornerRadius,
      )
      ..lineTo(rect.left, rect.bottom - bracketLength);
    canvas.drawPath(pathBL, bracketPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
