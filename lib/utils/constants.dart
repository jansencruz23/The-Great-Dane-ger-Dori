import 'package:flutter/material.dart';

class AppColors {
  // Coffee Shop Theme
  static const Color primary = Color(0xFF8B6F47); // Warm tan/latte
  static const Color secondary = Color(0xFFE8DCC8); // Cream/beige
  static const Color accent = Color(0xFF3E2723); // Dark espresso brown
  static const Color background = Color(0xFFF5F0E8); // Warm cream
  static const Color surface = Color(0xFFEFE6D5); // Light beige
  static const Color error = Color(0xFFD84315); // Burnt orange
  static const Color textPrimary = Color(
    0xFF2C1810,
  ); // Dark brown (almost black)
  static const Color textSecondary = Color(0xFF6D5D4B); // Medium brown
  static const Color arOverlay = Color(0xFFD4C4A8); // Light tan
  static const Color arOverlayBorder = Color(0xFF8B6F47); // Warm tan border
}

class AppConstants {
  // Face Recognition Thresholds
  static const double faceRecognitionThreshold =
      0.85; // Temporarily lowered for testing
  static const double faceDetectionConfidence = 0.2;
  static const int maxFacesPerFrame = 5;

  // AR Overlay Settings
  static const double arBubblePadding = 16.0;
  static const double arBubbleRadius = 12.0;
  static const double arBubbleOpacity = 0.9;
  static const double arTextSize = 20.0;
  static const double arSubtextSize = 16.0;

  // Speech Recognition Settings
  static const Duration speechListenDuration = Duration(seconds: 30);
  static const Duration speechPauseDuration = Duration(seconds: 3);

  // Camera Settings
  static const int targetImageWidth = 640;
  static const int targetImageHeight = 480;

  // Database Collections
  static const String usersCollection = 'users';
  static const String knownFacesCollection = 'known_faces';
  static const String activityLogsCollection = 'activity_logs';

  // Gemini API Settings
  // Note: Load .env file in main.dart using: await dotenv.load(fileName: ".env");
  static String geminiApiKey = ''; // Will be loaded from .env
  static const String geminiApiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

  // Storage Paths
  static const String faceImagesPath = 'face_images';

  // Shared Preferences Keys
  static const String kioskModeKey = 'kiosk_mode';
  static const String linkedPatientIdKey = 'linked_patient_id';
}

class AppStrings {
  static const String appName = 'Dory';
  static const String caregiverRole = 'caregiver';
  static const String patientRole = 'patient';

  // Auth Strings
  static const String loginTitle = 'Welcome Back';
  static const String registerTitle = 'Create Account';
  static const String emailHint = 'Email';
  static const String passwordHint = 'Password';
  static const String nameHint = 'Full Name';
  static const String loginButton = 'Login';
  static const String registerButton = 'Register';
  static const String noAccountText = "Don't have an account?";
  static const String haveAccountText = 'Already have an account?';

  // Caregiver Strings
  static const String caregiverDashboard = 'Caregiver Dashboard';
  static const String myPatients = 'My Patients';
  static const String addPatient = 'Add Patient';
  static const String addKnownFace = 'Add Known Face';
  static const String viewActivities = 'Vsiew Activities';

  // Patient Strings
  static const String patientHome = 'Welcome';
  static const String startRecognition = 'Start Face Recognition';
  static const String viewDailyRecap = 'View Daily Recap';
  static const String recognizing = 'Looking for familiar faces...';
  static const String noFaceDetected = 'No face detected';

  // AR Overlay
  static const String lastSeen = 'Last seen';
  static const String never = 'Never';

  // Error Messages
  static const String errorGeneric = 'An error occurred. Please try again.';
  static const String errorNoCamera = 'No camera available on this device.';
  static const String errorPermissionDenied =
      'Permission denied. Please enable in settings.';
  static const String errorNoFacesKnown = 'No known faces added yet.';
}
