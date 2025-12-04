import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../providers/user_provider.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';

import '../auth/login_screen.dart';
import 'face_recognition_screen.dart';
import 'daily_recap_screen.dart';

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Background Gradient
          Container(
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
          ),
          SafeArea(
            child: Column(
              children: [
                // Scrollable content area
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Hello,',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                  ),
                                  Text(
                                    user.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineMedium,
                                  ),
                                ],
                              ),

                              // Logout button
                              IconButton(
                                icon: const Icon(
                                  Icons.logout,
                                  color: AppColors.error,
                                ),
                                tooltip: 'Logout',
                                onPressed: () async {
                                  await userProvider.logout();
                                  if (context.mounted) {
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(
                                        builder: (_) => const LoginScreen(),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // Date
                          Text(
                            DateFormat(
                              'EEEE, MMMM dd, yyyy',
                            ).format(DateTime.now()),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.textSecondary),
                          ),

                          SizedBox(
                            height:
                                MediaQuery.of(context).size.height >
                                    MediaQuery.of(context).size.width
                                ? 48
                                : 24,
                          ),

                          // Welcome message
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primary.withOpacity(0.1),
                                  AppColors.secondary.withOpacity(0.1),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.primary.withOpacity(0.2),
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.face,
                                  size: 80,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Your Memory Assistant',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineMedium,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'I\'ll help you recognize familiar faces and remember your conversations',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Bottom buttons - Fixed at bottom
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isLandscape =
                          MediaQuery.of(context).size.width >
                          MediaQuery.of(context).size.height;
                      final buttonHeight = isLandscape ? 56.0 : 70.0;
                      final iconSize = isLandscape ? 28.0 : 32.0;

                      if (isLandscape) {
                        // Side by side in landscape
                        return Row(
                          children: [
                            // Main action button - Start Remembering (Green Glassmorphism)
                            Expanded(
                              child: _buildGlassButton(
                                context: context,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const FaceRecognitionScreen(),
                                    ),
                                  );
                                },
                                height: buttonHeight,
                                iconSize: iconSize,
                                icon: Icons.camera_alt,
                                label: AppStrings.startRecognition,
                                isPrimary: true,
                                isLandscape: true,
                              ),
                            ),

                            const SizedBox(width: 16),

                            // Secondary action button - View Daily Recap (White Glassmorphism)
                            Expanded(
                              child: _buildGlassButton(
                                context: context,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          DailyRecapScreen(patientId: user.uid),
                                    ),
                                  );
                                },
                                height: buttonHeight,
                                iconSize: iconSize,
                                icon: Icons.auto_stories,
                                label: AppStrings.viewDailyRecap,
                                isPrimary: false,
                                isLandscape: true,
                              ),
                            ),
                          ],
                        );
                      } else {
                        // Stacked vertically in portrait
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Subtle hint text
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                'Tap "Start Remembering" to begin identifying people around you',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AppColors.textSecondary
                                          .withOpacity(0.7),
                                      fontSize: 12,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                            ),

                            // Main action button - Start Remembering (Green Glassmorphism)
                            _buildGlassButton(
                              context: context,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const FaceRecognitionScreen(),
                                  ),
                                );
                              },
                              height: buttonHeight,
                              iconSize: iconSize,
                              icon: Icons.camera_alt,
                              label: AppStrings.startRecognition,
                              isPrimary: true,
                              isLandscape: false,
                            ),

                            const SizedBox(height: 16),

                            // Secondary action button - View Daily Recap (White Glassmorphism)
                            _buildGlassButton(
                              context: context,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        DailyRecapScreen(patientId: user.uid),
                                  ),
                                );
                              },
                              height: buttonHeight,
                              iconSize: iconSize,
                              icon: Icons.auto_stories,
                              label: AppStrings.viewDailyRecap,
                              isPrimary: false,
                              isLandscape: false,
                            ),
                          ],
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassButton({
    required BuildContext context,
    required VoidCallback onTap,
    required double height,
    required double iconSize,
    required IconData icon,
    required String label,
    required bool isPrimary,
    required bool isLandscape,
  }) {
    final baseColor = isPrimary ? AppColors.primary : Colors.white;
    final textColor = isPrimary ? Colors.white : AppColors.primary;
    final borderColor = isPrimary
        ? Colors.white.withOpacity(0.3)
        : AppColors.primary.withOpacity(0.4);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                baseColor.withOpacity(0.85),
                baseColor.withOpacity(0.65),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: isPrimary ? 1.5 : 2),
            boxShadow: [
              BoxShadow(
                color: isPrimary
                    ? AppColors.primary.withOpacity(0.3)
                    : Colors.black.withOpacity(0.1),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: isLandscape ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  Icon(icon, size: iconSize, color: textColor),
                  SizedBox(width: isLandscape ? 12 : 16),
                  Flexible(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
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
