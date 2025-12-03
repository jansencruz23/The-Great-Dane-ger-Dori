# Scheduled Daily Summary & SOS Features

## Overview
This document explains how to implement the scheduled daily summary TTS feature and SOS notification system.

## Files Created
- `lib/services/scheduled_summary_service.dart` - Service template for scheduled summaries and SOS

## Current Status
✅ **Implemented:**
- Text-to-Speech button in day-by-day summary widget
- SOS debug button in face recognition screen (bottom-right corner)
- Service template with all necessary methods

🚧 **TODO (Future Implementation):**
- Add required packages to pubspec.yaml
- Configure platform-specific notification permissions
- Integrate with Firebase Cloud Messaging for caregiver notifications
- Set up background task handling

---

## How to Implement Scheduled Daily Summaries

### Step 1: Add Required Packages

Add these to `pubspec.yaml`:

```yaml
dependencies:
  flutter_local_notifications: ^18.0.1
  timezone: ^0.9.4
```

Then run:
```bash
flutter pub get
```

### Step 2: Configure Android Permissions

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    
    <application>
        <!-- Add notification icon -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_icon"
            android:resource="@drawable/ic_notification" />
    </application>
</manifest>
```

### Step 3: Configure iOS Permissions

Add to `ios/Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
</array>
```

### Step 4: Initialize the Service

In `lib/main.dart`, add:

```dart
import 'services/scheduled_summary_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ... existing Firebase initialization ...
  
  // Initialize scheduled summary service
  final scheduledService = ScheduledSummaryService();
  await scheduledService.initialize();
  
  runApp(const MyApp());
}
```

### Step 5: Schedule Daily Summaries

When a patient logs in, schedule their daily summary:

```dart
// In patient_home_screen.dart or after login
final scheduledService = ScheduledSummaryService();
await scheduledService.scheduleDailySummary(
  patientId: currentUser.uid,
  hour: 20, // 8 PM
  minute: 0,
);
```

### Step 6: Test the Feature

Use the test notification method:

```dart
final scheduledService = ScheduledSummaryService();
await scheduledService.sendTestNotification();
```

---

## How to Implement SOS Notifications

### Current Implementation
The SOS button is already added to the face recognition screen (bottom-right corner, red button with emergency icon).

### To Enable Full SOS Functionality:

#### 1. Set Up Firebase Cloud Messaging (FCM)

Add to `pubspec.yaml`:
```yaml
dependencies:
  firebase_messaging: ^15.0.0
```

#### 2. Store Caregiver Device Tokens

Add to `lib/models/user_model.dart`:
```dart
class UserModel {
  // ... existing fields ...
  final String? fcmToken; // For caregivers
  final List<String>? caregiverIds; // For patients
}
```

#### 3. Implement SOS in Database Service

Add to `lib/services/database_service.dart`:
```dart
Future<void> sendSOSToCaregiver({
  required String patientId,
  required String message,
}) async {
  // 1. Get patient's caregivers
  final patient = await getUser(patientId);
  final caregiverIds = patient.caregiverIds ?? [];
  
  // 2. Get caregiver FCM tokens
  for (var caregiverId in caregiverIds) {
    final caregiver = await getUser(caregiverId);
    if (caregiver.fcmToken != null) {
      // 3. Send FCM notification
      await _sendFCMNotification(
        token: caregiver.fcmToken!,
        title: '🆘 SOS Alert',
        body: message,
      );
    }
  }
  
  // 4. Log SOS event
  await _firestore.collection('sos_events').add({
    'patientId': patientId,
    'message': message,
    'timestamp': FieldValue.serverTimestamp(),
  });
}
```

#### 4. Uncomment SOS Code

In `lib/screens/patient/face_recognition_screen.dart`, uncomment the SOS service code:

```dart
// Currently commented out (lines ~1211-1216)
final sosService = ScheduledSummaryService();
await sosService.initialize();
await sosService.sendSOSNotification(
  patientId: patientId,
  message: 'Emergency assistance requested',
);
```

---

## Testing

### Test Scheduled Summaries
1. Call `scheduleDailySummary()` with a time 1 minute in the future
2. Wait for the notification
3. Tap the notification to hear the TTS summary

### Test SOS Button
1. Tap the red SOS button in the bottom-right corner
2. Check console for `🆘 SOS Button Pressed!`
3. See the red snackbar confirmation
4. Once fully implemented, check caregiver device for notification

---

## Architecture

```
┌─────────────────────────────────────────┐
│  ScheduledSummaryService                │
├─────────────────────────────────────────┤
│  - scheduleDailySummary()               │
│  - sendSOSNotification()                │
│  - _speak() [TTS]                       │
└─────────────────────────────────────────┘
           │
           ├──> FlutterLocalNotifications
           ├──> FlutterTts
           ├──> DatabaseService
           └──> SummarizationService
```

---

## Future Enhancements

1. **Smart Scheduling**: Adjust summary time based on patient's routine
2. **SMS Backup**: Send SMS if caregiver doesn't respond to notification
3. **Location Sharing**: Include patient location in SOS
4. **Emergency Contacts**: Multiple caregiver tiers
5. **Voice Activation**: "Hey Dory, send SOS"
6. **Fall Detection**: Auto-trigger SOS on fall detection

---

## Notes

- The service template is fully documented with TODO comments
- All methods include example usage in docstrings
- The SOS button is visible for easy debugging
- TTS is already working in the day-by-day summary widget
- Notification permissions must be requested at runtime on Android 13+

---

## Support

For questions or issues, check:
- `lib/services/scheduled_summary_service.dart` - Full implementation template
- Flutter Local Notifications docs: https://pub.dev/packages/flutter_local_notifications
- Firebase Cloud Messaging docs: https://firebase.google.com/docs/cloud-messaging
