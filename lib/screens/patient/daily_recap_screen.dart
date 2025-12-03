import 'package:flutter/material.dart';

class DailyRecapScreen extends StatefulWidget {
  final String patientId;
  const DailyRecapScreen({super.key, required this.patientId});

  @override
  State<DailyRecapScreen> createState() => _DailyRecapScreenState();
}

class _DailyRecapScreenState extends State<DailyRecapScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily Recap')),
      body: const Placeholder(),
    );
  }
}
