import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_tts/flutter_tts.dart';
import 'database_service.dart';
import 'summarization_service.dart';

/// Service for scheduling daily summary notifications and TTS
///
/// TODO: To implement scheduled daily summaries:
/// 1. Add flutter_local_notifications to pubspec.yaml
/// 2. Add timezone package to pubspec.yaml
/// 3. Configure Android/iOS notification permissions
/// 4. Call scheduleDailySummary() when user logs in
/// 5. Implement background task handling for TTS
class ScheduledSummaryServicse {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final DatabaseService _databaseService = DatabaseService();
  final SummarizationService _summarizationService = SummarizationService();
  final FlutterTts _flutterTts = FlutterTts();

  /// Initialize the notification service
  Future<void> initialize() async {
    // Initialize timezone
    tz.initializeTimeZones();

    // Android initialization settings
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // iOS initialization settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Request permissions
    await _requestPermissions();
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    // Android 13+ requires runtime permission
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    // iOS permissions
    await _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Schedule daily summary at a specific time (e.g., 8 PM every day)
  ///
  /// Example usage:
  /// ```dart
  /// await scheduleDailySummary(
  ///   patientId: 'user123',
  ///   hour: 20, // 8 PM
  ///   minute: 0,
  /// );
  /// ```
  Future<void> scheduleDailySummary({
    required String patientId,
    int hour = 20, // 8 PM by default
    int minute = 0,
  }) async {
    // Calculate next scheduled time
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    // If the time has passed today, schedule for tomorrow
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    print('📅 Scheduled daily summary for: $scheduledDate');

    // Schedule the notification
    await _notifications.zonedSchedule(
      0, // Notification ID
      'Daily Summary Ready',
      'Tap to hear your day-by-day summary',
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_summary',
          'Daily Summaries',
          channelDescription: 'End of day activity summaries',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // Repeat daily
      payload: patientId, // Pass patient ID for fetching summary
    );
  }

  /// Handle notification tap - generate and speak summary
  Future<void> _onNotificationTapped(NotificationResponse response) async {
    final patientId = response.payload;
    if (patientId == null) return;

    print('🔔 Notification tapped, generating summary for: $patientId');

    try {
      // Fetch activity logs
      final logsByDate = await _databaseService.getActivityLogsByDate(
        patientId,
        daysBack: 1, // Just today's summary
      );

      if (logsByDate.isEmpty) {
        await _speak('No activities recorded today.');
        return;
      }

      // Generate summary
      final summaries = <Map<String, dynamic>>[];
      for (var entry in logsByDate.entries) {
        for (var log in entry.value) {
          summaries.add({
            'personName': log.personName,
            'summary': log.summary,
            'timestamp': log.timestamp,
          });
        }
      }

      // Group by date and generate narrative
      final summariesByDate = <String, List<Map<String, dynamic>>>{};
      for (var summary in summaries) {
        final timestamp = summary['timestamp'] as DateTime;
        final dateKey =
            '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';

        if (!summariesByDate.containsKey(dateKey)) {
          summariesByDate[dateKey] = [];
        }
        summariesByDate[dateKey]!.add(summary);
      }

      // TODO: Call Gemini to generate narrative summary
      // For now, create a simple summary
      final people = summaries.map((s) => s['personName']).toSet().join(', ');
      final summaryText = 'Today you spent time with $people.';

      // Speak the summary
      await _speak(summaryText);
    } catch (e) {
      print('❌ Error generating scheduled summary: $e');
      await _speak('Sorry, I could not generate your summary.');
    }
  }

  /// Speak text using TTS
  Future<void> _speak(String text) async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    // Remove markdown
    final cleanText = text.replaceAll(RegExp(r'\*\*'), '');
    await _flutterTts.speak(cleanText);
  }

  /// Cancel all scheduled summaries
  Future<void> cancelAllSchedules() async {
    await _notifications.cancelAll();
    print('🚫 All scheduled summaries cancelled');
  }

  /// Send immediate test notification (for debugging)
  Future<void> sendTestNotification() async {
    await _notifications.show(
      999, // Test notification ID
      'Test Notification',
      'This is a test notification from Dori',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'test_channel',
          'Test Notifications',
          channelDescription: 'Test notifications for debugging',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
    print('🧪 Test notification sent');
  }
}
