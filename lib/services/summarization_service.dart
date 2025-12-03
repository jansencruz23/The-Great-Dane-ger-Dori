import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
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
      print('DEBUG: Prompt sent to Gemini:\n$prompt');
      final recap = await _callGeminiAPI(prompt);
      print('DEBUG: Gemini response: $recap');
      return recap;
    } catch (e) {
      print('Error generating daily recap: $e');
      return _generateFallbackDailyRecap(activities);
    }
  }

  // Call Gemini API
  Future<String> _callGeminiAPI(String prompt) async {
    final url = '${AppConstants.geminiApiUrl}?key=${AppConstants.geminiApiKey}';

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'content': [
          {
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.6,
          'maxOutputTokens': 256,
          'topP': 0.9,
          'topK': 40,
        },
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final text = data['candidates'][0]['content']['parts'][0]['text'];
      return text.trim();
    } else {
      throw 'API request failed: ${response.statusCode}';
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
}
