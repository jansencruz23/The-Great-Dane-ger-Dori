import 'package:dori/providers/user_provider.dart';
import 'package:dori/screens/splash_screen.dart';
import 'package:dori/utils/constants.dart' show AppColors, AppConstants;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_gemini/flutter_gemini.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env file
  try {
    await dotenv.load(fileName: ".env");
    // Load the API key from .env
    AppConstants.geminiApiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    
    if (AppConstants.geminiApiKey.isEmpty) {
      print('Warning: GEMINI_API_KEY not found in .env file');
    } else {
      // Debug: Print API key info (first and last 4 chars only for security)
      final keyLength = AppConstants.geminiApiKey.length;
      final keyPreview = keyLength > 8 
          ? '${AppConstants.geminiApiKey.substring(0, 4)}...${AppConstants.geminiApiKey.substring(keyLength - 4)}'
          : 'TOO_SHORT';
      print('✅ Gemini API Key loaded: $keyPreview (length: $keyLength)');
      
      Gemini.init(apiKey: AppConstants.geminiApiKey);
      print('✅ Gemini initialized successfully');
    }
  } catch (e) {
    print('Error loading .env file: $e');
  }

  // Initialize Firebase
  await Firebase.initializeApp();

  try {
    cameras = await availableCameras();
  } catch (e) {
    print('Error initializing camera: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => UserProvider())],
      child: MaterialApp(
        title: 'Dory',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          fontFamily: 'Roboto',
          textTheme: const TextTheme(
            headlineLarge: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            headlineMedium: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            bodyLarge: TextStyle(fontSize: 18, color: AppColors.textPrimary),
            bodyMedium: TextStyle(fontSize: 16, color: AppColors.textSecondary),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}
