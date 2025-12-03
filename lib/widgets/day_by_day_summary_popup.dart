import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../services/summarization_service.dart';
import '../providers/user_provider.dart';
import '../models/activity_log_model.dart';

class DayByDaySummaryPopup extends StatefulWidget {
  const DayByDaySummaryPopup({super.key});

  @override
  State<DayByDaySummaryPopup> createState() => _DayByDaySummaryPopupState();
}

class _DayByDaySummaryPopupState extends State<DayByDaySummaryPopup> {
  final DatabaseService _databaseService = DatabaseService();
  final SummarizationService _summarizationService = SummarizationService();
  
  String _summary = 'Loading your daily recap...';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _generateDailyRecap();
  }

  Future<void> _generateDailyRecap() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final patientId = userProvider.currentUser?.uid;

      if (patientId == null) {
        setState(() {
          _summary = 'Error: User not found.';
          _isLoading = false;
        });
        return;
      }

      // 1. Fetch today's activity logs
      final logs = await _databaseService.getTodayActivityLogs(patientId);
      
      print('DEBUG: Fetched ${logs.length} activity logs for today');
      for (var log in logs) {
        print('DEBUG: Log - ${log.personName} at ${log.timestamp}: ${log.summary}');
      }

      // 2. Generate summary using Gemini
      print('DEBUG: Calling generateDailyRecap with ${logs.length} logs...');
      final recap = await _summarizationService.generateDailyRecap(logs);
      print('DEBUG: Received recap from service: $recap');

      if (mounted) {
        setState(() {
          _summary = recap;
          _isLoading = false;
        });
        print('DEBUG: Updated UI with recap: $_summary');
      }
    } catch (e, stackTrace) {
      if (mounted) {
        setState(() {
          _summary = 'Unable to generate summary: $e'; // Show error in UI for debugging
          _isLoading = false;
        });
      }
      print('Error generating daily recap: $e');
      print('Stack trace: $stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    return Align(
      alignment: isLandscape ? Alignment.centerLeft : Alignment.center,
      child: Padding(
        padding: EdgeInsets.only(left: isLandscape ? 24.0 : 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Daily Recap',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isLoading)
                    const CircularProgressIndicator(color: Colors.white)
                  else
                    Text(
                      _summary,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
