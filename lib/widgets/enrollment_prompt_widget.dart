import 'package:flutter/material.dart';

class EnrollmentPromptWidget extends StatelessWidget {
  final String promptText;
  final String? subtext;
  final bool isListening;

  const EnrollmentPromptWidget({
    super.key,
    required this.promptText,
    this.subtext,
    this.isListening = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 25,
      left: 75,
      child: SafeArea(
        child: Text(
          'Enrolling',
          style: const TextStyle(color: Colors.white, fontSize: 24),
        ),
      ),
    );
  }
}
