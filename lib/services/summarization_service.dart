import 'package:flutter_gemini/flutter_gemini.dart';
import '../models/activity_log_model.dart';

class SummarizationService {
  // Generate warm, simple summary from conversation transcript
  Future<String> generateSummary({
    required String transcript,
    required String personName,
    required String relationship,
  }) async {
    if (transcript.isEmpty) {
      return 'You met with $personName today';
    }

    try {
      final prompt = _buildSummaryPrompt(transcript, personName, relationship);
      final summary = await _callGeminiAPI(prompt);
      return summary;
    } catch (e) {
      print('Error generating summary: $e');
      return _generateFallbackSummary(transcript, personName);
    }
  }

  // Generate daily recap from multiple interactions
  Future<String> generateDailyRecap(List<ActivityLogModel> activities) async {
    if (activities.isEmpty) {
      return 'You had a quiet day today with no recorded interactions.';
    }

    try {
      final prompt = _buildDailyRecapPrompt(activities);
      final recap = await _callGeminiAPI(prompt);
      return recap;
    } catch (e) {
      print('Error generating daily recap: $e');
      return _generateFallbackDailyRecap(activities);
    }
  }

  // Call Gemini API using flutter_gemini
  Future<String> _callGeminiAPI(String prompt) async {
    try {
      final value = await Gemini.instance.text(prompt);
      print('Gemini API Response: ${value?.output?.trim()}');
      return value?.output?.trim() ?? '';
    } catch (e) {
      print('Gemini API Error: $e');
      throw 'API request failed: $e';
    }
  }

  // Build summary prompt for single interaction
  String _buildSummaryPrompt(
    String transcript,
    String personName,
    String relationship,
  ) {
    return '''You are a warm, emphatetic assistant helping someone with memory challenges.
    Create a brief, warm summary (2-3 sentences) of this conversation with $personName (their $relationship).

    Conversation:
    $transcript

    Guidelines:
    - Use simple, clear language
    - Focus on positive moments
    - Highlight key topics discussed
    - Keep it warm and encouraging
    - Maximum 3 sentences

    Summary:''';
  }

  // Build daily recap prompt
  String _buildDailyRecapPrompt(List<ActivityLogModel> activities) {
    final interactionsList = activities
        .map((activity) {
          final time = activity.timestamp.hour > 12
              ? '${activity.timestamp.hour - 12}:${activity.timestamp.minute.toString().padLeft(2, '0')} PM'
              : '${activity.timestamp.hour}:${activity.timestamp.minute.toString().padLeft(2, '0')} AM';

          return '$time - ${activity.personName}: ${activity.summary ?? 'You had a nice chat'}';
        })
        .join('\n');

    return '''You are a warm, empathetic assistant helping someone with memory challenges.

    Today's interactions:
    $interactionsList

    Create a warm, story-like summary (3-5 sentences) of their day. Make it:
    - Personal and warm
    - Easy to understand
    - Focused on positive moments
    - Written as a comforting narrative

    Daily recap:''';
  }

  // Fallback summary if API fails
  String _generateFallbackSummary(String transcript, String personName) {
    final words = transcript.split(' ');
    if (words.length > 50) {
      return 'You had a lovely conversation with $personName. You talked about many things and enjoyed spending time together.';
    } else if (words.length > 20) {
      return 'You met with $personName and had a nice chat together.';
    } else {
      return 'You saw $personName today.';
    }
  }

  // Fallback daily recap if API fails
  String _generateFallbackDailyRecap(List<ActivityLogModel> activities) {
    final uniquePeople = activities.map((a) => a.personName).toSet().toList();

    if (uniquePeople.length == 1) {
      return 'Today you spent time with ${uniquePeople[0]}. You had ${activities.length} ${activities.length == 1 ? 'conversation' : 'conversations'} together.';
    } else {
      final peopleList = uniquePeople.length > 2
          ? '${uniquePeople.take(uniquePeople.length - 1).join(', ')}, and ${uniquePeople.last}'
          : uniquePeople.join(' and ');

      return 'Today was a social day! You spent time with $peopleList. You had ${activities.length} converstations in total.';
    }
  }

  // Generate day-by-day summary from activity logs
  Future<String> generateDayByDaySummary(
    Map<String, List<ActivityLogModel>> activitiesByDate,
  ) async {
    print('═══════════════════════════════════════════════════════');
    print('🤖 GENERATING DAY-BY-DAY SUMMARY WITH GEMINI');
    print('═══════════════════════════════════════════════════════');
    print('Number of days with activities: ${activitiesByDate.length}');
    
    if (activitiesByDate.isEmpty) {
      print('⚠️  No activities to summarize!');
      print('═══════════════════════════════════════════════════════\n');
      return 'No activities recorded yet. Your daily summaries will appear here.';
    }

    // Print all summaries being sent to Gemini
    print('\n📋 SUMMARIES TO BE SENT TO GEMINI:');
    print('─────────────────────────────────────────────────────');
    for (final entry in activitiesByDate.entries) {
      print('Date: ${entry.key}');
      for (final activity in entry.value) {
        print('  • ${activity.personName}: ${activity.summary}');
      }
    }
    print('═══════════════════════════════════════════════════════\n');

    try {
      final prompt = _buildDayByDayPrompt(activitiesByDate);
      
      print('📤 COMPLETE GEMINI PROMPT:');
      print('┌─────────────────────────────────────────────────────┐');
      print(prompt);
      print('└─────────────────────────────────────────────────────┘');
      print('Prompt length: ${prompt.length} characters\n');
      
      final summary = await _callGeminiAPI(prompt);
      
      print('✅ RECEIVED FROM GEMINI:');
      print('┌─────────────────────────────────────────────────────┐');
      print(summary);
      print('└─────────────────────────────────────────────────────┘');
      print('═══════════════════════════════════════════════════════\n');
      
      return summary;
    } catch (e) {
      print('❌ ERROR generating day-by-day summary: $e');
      print('Using fallback summary instead\n');
      return _generateFallbackDayByDay(activitiesByDate);
    }
  }

  // Build day-by-day prompt for Gemini
  String _buildDayByDayPrompt(
    Map<String, List<ActivityLogModel>> activitiesByDate,
  ) {
    final buffer = StringBuffer();
    buffer.writeln(
      'You are a warm, empathetic assistant helping someone with memory challenges.',
    );
    buffer.writeln(
      'Create a day-by-day summary of their recent activities. Make it warm, personal, and easy to understand.',
    );
    buffer.writeln();

    // Sort dates in descending order (most recent first)
    final sortedDates = activitiesByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    for (final dateStr in sortedDates) {
      final activities = activitiesByDate[dateStr]!;
      final date = DateTime.parse(dateStr);
      final dayName = _getDayName(date);

      buffer.writeln('$dayName ($dateStr):');

      for (final activity in activities) {
        final time = _formatTime(activity.timestamp);
        buffer.writeln(
          '  - $time with ${activity.personName}: ${activity.summary ?? "Had a conversation"}',
        );
      }
      buffer.writeln();
    }

    buffer.writeln('Guidelines:');
    buffer.writeln('- Create a warm, story-like summary for each day');
    buffer.writeln('- Use simple, clear language');
    buffer.writeln('- Focus on positive moments and connections');
    buffer.writeln('- Keep each day summary to 2-3 sentences');
    buffer.writeln('- Start each day with the day name (e.g., "Today", "Yesterday")');
    buffer.writeln();
    buffer.writeln('Day-by-day summary:');

    return buffer.toString();
  }

  // Fallback day-by-day summary if API fails
  String _generateFallbackDayByDay(
    Map<String, List<ActivityLogModel>> activitiesByDate,
  ) {
    final buffer = StringBuffer();
    final sortedDates = activitiesByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    for (final dateStr in sortedDates) {
      final activities = activitiesByDate[dateStr]!;
      final date = DateTime.parse(dateStr);
      final dayName = _getDayName(date);
      final uniquePeople =
          activities.map((a) => a.personName).toSet().toList();

      buffer.writeln('$dayName:');
      if (uniquePeople.length == 1) {
        buffer.writeln(
          'You spent time with ${uniquePeople[0]} (${activities.length} ${activities.length == 1 ? 'conversation' : 'conversations'}).',
        );
      } else {
        final peopleList = uniquePeople.join(', ');
        buffer.writeln(
          'You had ${activities.length} conversations with $peopleList.',
        );
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  // Helper: Get day name relative to today
  String _getDayName(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(date.year, date.month, date.day);
    final difference = today.difference(targetDate).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    if (difference < 7) return '${difference} days ago';

    return '${date.month}/${date.day}/${date.year}';
  }

  // Helper: Format time
  String _formatTime(DateTime timestamp) {
    final hour = timestamp.hour > 12 ? timestamp.hour - 12 : timestamp.hour;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final period = timestamp.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}
