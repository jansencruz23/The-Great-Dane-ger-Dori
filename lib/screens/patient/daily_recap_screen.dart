import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../services/database_service.dart';
import '../../services/summarization_service.dart';
import '../../models/activity_log_model.dart';
import '../../utils/constants.dart';

class DailyRecapScreen extends StatefulWidget {
  final String patientId;
  const DailyRecapScreen({super.key, required this.patientId});

  @override
  State<DailyRecapScreen> createState() => _DailyRecapScreenState();
}

class _DailyRecapScreenState extends State<DailyRecapScreen> {
  final DatabaseService _databaseService = DatabaseService();
  final SummarizationService _summarizationService = SummarizationService();
  final ScrollController _scrollController = ScrollController();
  
  // Text-to-Speech
  late FlutterTts _flutterTts;
  bool _isSpeaking = false;
  
  // Summary state
  bool _isLoadingSummary = false;
  String _dayByDaySummary = '';
  
  @override
  void initState() {
    super.initState();
    _initializeTts();
    _loadDayByDaySummary();
  }
  
  Future<void> _initializeTts() async {
    _flutterTts = FlutterTts();
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5); // Slower for clarity
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    _flutterTts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    });
  }
  
  Future<void> _loadDayByDaySummary() async {
    setState(() {
      _isLoadingSummary = true;
      _dayByDaySummary = '';
    });

    try {
      print('Loading day-by-day summary for patient: ${widget.patientId}');
      
      // Fetch activity logs grouped by date (last 7 days)
      final activitiesByDate = await _databaseService.getActivityLogsByDate(
        widget.patientId,
        daysBack: 7,
      );

      print('Fetched activities for ${activitiesByDate.length} days');

      // Generate summary using Gemini
      final summary = await _summarizationService.generateDayByDaySummary(
        activitiesByDate,
      );

      if (mounted) {
        setState(() {
          _dayByDaySummary = summary;
          _isLoadingSummary = false;
        });
      }
    } catch (e) {
      print('Error loading day-by-day summary: $e');
      if (mounted) {
        setState(() {
          _dayByDaySummary = 'Could not load your daily recap. Please try again.';
          _isLoadingSummary = false;
        });
      }
    }
  }
  
  Future<void> _speak() async {
    if (_isLoadingSummary || _dayByDaySummary.isEmpty) return;
    
    // Remove markdown bold syntax before speaking
    final textToSpeak = _dayByDaySummary.replaceAll(RegExp(r'\*\*'), '');
    
    setState(() {
      _isSpeaking = true;
    });
    
    await _flutterTts.speak(textToSpeak);
  }

  Future<void> _stopSpeaking() async {
    await _flutterTts.stop();
    setState(() {
      _isSpeaking = false;
    });
  }
  
  @override
  void dispose() {
    _flutterTts.stop();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Daily Recap',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoadingSummary ? null : _loadDayByDaySummary,
            tooltip: 'Refresh',
          ),
          // TTS button
          IconButton(
            icon: Icon(
              _isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded,
            ),
            onPressed: _isLoadingSummary
                ? null
                : (_isSpeaking ? _stopSpeaking : _speak),
            tooltip: _isSpeaking ? 'Stop' : 'Read Aloud',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.background,
              AppColors.secondary,
              AppColors.primary.withOpacity(0.3),
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoadingSummary
              ? _buildLoadingState()
              : _buildSummaryContent(),
        ),
      ),
    );
  }
  
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated bouncing dots
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 1200),
            builder: (context, value, child) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (index) {
                  final delay = index * 0.2;
                  final animValue = (value + delay) % 1.0;
                  final bounce = (animValue < 0.5 
                      ? animValue * 2 
                      : 2 - (animValue * 2));
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Transform.translate(
                      offset: Offset(0, -10 * bounce),
                      child: const Text(
                        '●',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 32,
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
            onEnd: () {
              // Restart animation
              if (mounted) {
                setState(() {});
              }
            },
          ),
          const SizedBox(height: 30),
          const Text(
            'Generating your daily recap...',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSummaryContent() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.2),
                  Colors.white.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              children: [
                // Header
                _buildHeader(),
                
                // Divider
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.0),
                        Colors.white.withOpacity(0.3),
                        Colors.white.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
                
                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      radius: const Radius.circular(10),
                      thickness: 4,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: _buildFormattedText(_dayByDaySummary),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.3),
                  AppColors.primary.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.calendar_today_rounded,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Daily Recap',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Last 7 days of activities',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // Parse markdown bold syntax (**text**) and format with professional styling
  Widget _buildFormattedText(String text) {
    if (text.isEmpty) {
      return Center(
        child: Text(
          'No activities to display',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 16,
          ),
        ),
      );
    }
    
    // Split text by paragraphs (double newlines or day headers)
    final paragraphs = text.split('\n\n');
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: paragraphs.asMap().entries.map((entry) {
        final index = entry.key;
        final paragraph = entry.value.trim();
        
        if (paragraph.isEmpty) return const SizedBox.shrink();
        
        // Check if this is a day header (starts with "Today", "Yesterday", etc.)
        final isDayHeader = paragraph.startsWith(RegExp(r'^(Today|Yesterday|Two days ago|Three days ago|Four days ago|Five days ago|Six days ago|A week ago)'));
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Add subtle divider between days (but not before first day)
            if (isDayHeader && index > 0) ...[
              const SizedBox(height: 28),
              Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.0),
                      AppColors.primary.withOpacity(0.3),
                      Colors.white.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ] else if (index > 0)
              const SizedBox(height: 20),
            
            // Build the paragraph with enhanced formatting
            _buildParagraph(paragraph, isDayHeader),
          ],
        );
      }).toList(),
    );
  }
  
  Widget _buildParagraph(String paragraph, bool isDayHeader) {
    final List<InlineSpan> spans = [];
    
    if (isDayHeader) {
      // Parse day header separately for special styling
      final headerMatch = RegExp(r'^(Today|Yesterday|Two days ago|Three days ago|Four days ago|Five days ago|Six days ago|A week ago)(.*)').firstMatch(paragraph);
      
      if (headerMatch != null) {
        final dayName = headerMatch.group(1)!;
        final restOfText = headerMatch.group(2)!;
        
        // Day name in larger, bold text
        spans.add(TextSpan(
          text: dayName,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 20,
            height: 1.4,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w700,
          ),
        ));
        
        // Rest of the header text
        if (restOfText.isNotEmpty) {
          _addFormattedSpans(spans, restOfText, isHeader: false);
        }
        
        return RichText(
          text: TextSpan(children: spans),
        );
      }
    }
    
    // Regular paragraph
    _addFormattedSpans(spans, paragraph, isHeader: false);
    
    return RichText(
      text: TextSpan(children: spans),
      textAlign: TextAlign.left,
    );
  }
  
  void _addFormattedSpans(List<InlineSpan> spans, String text, {required bool isHeader}) {
    final RegExp boldPattern = RegExp(r'\*\*(.+?)\*\*');
    
    int lastIndex = 0;
    for (final match in boldPattern.allMatches(text)) {
      // Add normal text before the bold part
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            height: 1.7,
            letterSpacing: 0.2,
            fontWeight: FontWeight.w400,
          ),
        ));
      }
      
      // Add bold text (names)
      spans.add(TextSpan(
        text: match.group(1), // The text inside **...**
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 16,
          height: 1.7,
          letterSpacing: 0.3,
          fontWeight: FontWeight.w600,
        ),
      ));
      
      lastIndex = match.end;
    }
    
    // Add remaining text after last bold part
    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          height: 1.7,
          letterSpacing: 0.2,
          fontWeight: FontWeight.w400,
        ),
      ));
    }
  }
}
