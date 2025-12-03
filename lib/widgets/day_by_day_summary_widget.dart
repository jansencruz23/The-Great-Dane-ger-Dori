import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class DayByDaySummaryWidget extends StatefulWidget {
  final String summary;
  final bool isLoading;
  final VoidCallback onRefresh;

  const DayByDaySummaryWidget({
    super.key,
    required this.summary,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  State<DayByDaySummaryWidget> createState() => _DayByDaySummaryWidgetState();
}

class _DayByDaySummaryWidgetState extends State<DayByDaySummaryWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final ScrollController _scrollController = ScrollController();
  
  // Text-to-Speech
  late FlutterTts _flutterTts;
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    
    // Initialize TTS
    _flutterTts = FlutterTts();
    _initializeTts();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animationController.forward();
  }

  Future<void> _initializeTts() async {
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

  Future<void> _speak() async {
    if (widget.isLoading || widget.summary.isEmpty) return;
    
    // Remove markdown bold syntax before speaking
    final textToSpeak = widget.summary.replaceAll(RegExp(r'\*\*'), '');
    
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
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isPortrait = size.height > size.width;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          width: isPortrait ? size.width * 0.9 : size.width * 0.35,
          height: isPortrait ? size.height * 0.6 : size.height * 0.8,
          margin: EdgeInsets.only(
            left: isPortrait ? size.width * 0.05 : 16,
            top: isPortrait ? size.height * 0.2 : size.height * 0.1,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.black.withValues(alpha: 0.5),
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
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
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(alpha: 0.3),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),

                    // Content
                    Expanded(
                      child: widget.isLoading
                          ? _buildLoadingState()
                          : _buildSummaryContent(),
                    ),
                  ],
                ),
              ),
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
                  Colors.white.withValues(alpha: 0.2),
                  Colors.white.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.calendar_today_rounded,
              color: Colors.white.withValues(alpha: 0.9),
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
                  'Day-by-Day Summary',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your recent activities',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),

          // Speaker button (TTS)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.isLoading 
                  ? null 
                  : (_isSpeaking ? _stopSpeaking : _speak),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: widget.isLoading
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: widget.isLoading
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Icon(
                  _isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded,
                  color: widget.isLoading
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.8),
                  size: 20,
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Refresh button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onRefresh,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.refresh_rounded,
                  color: Colors.white.withValues(alpha: 0.8),
                  size: 20,
                ),
              ),
            ),
          ),
        ],
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
                      child: Text(
                        '●',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
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
          Text(
            'Generating summary...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 16,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
            child: _buildFormattedText(widget.summary),
          ),
        ),
      ),
    );
  }

  // Parse markdown bold syntax (**text**) and format with professional styling
  Widget _buildFormattedText(String text) {
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
                      Colors.white.withValues(alpha: 0.0),
                      Colors.white.withValues(alpha: 0.3),
                      Colors.white.withValues(alpha: 0.0),
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
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.98),
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
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.92),
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
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.98),
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
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.92),
          fontSize: 16,
          height: 1.7,
          letterSpacing: 0.2,
          fontWeight: FontWeight.w400,
        ),
      ));
    }
  }
}
