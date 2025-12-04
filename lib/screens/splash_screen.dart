import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/user_provider.dart';
import '../utils/constants.dart';
import 'auth/login_screen.dart';
import 'caregiver/caregiver_dashboard.dart';
import 'patient/patient_home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late AnimationController _shimmerController;

  late Animation<double> _logoFadeAnimation;
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();

    // Logo entrance animation
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _logoScaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.8, curve: Curves.elasticOut),
      ),
    );

    // Shimmer effect for loading
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _shimmerAnimation = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    // Exit animation
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeIn));

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeIn));

    _logoController.forward();
    _initializeApp();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _fadeController.dispose();
    _scaleController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    // Wait for entrance animation to complete
    await Future.delayed(const Duration(milliseconds: 2000));

    if (!mounted) return;

    // Initialize user session
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    await userProvider.initializeUser();

    if (!mounted) return;

    // Play exit animation
    _fadeController.forward();
    _scaleController.forward();

    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    // Navigate based on authentication state
    if (userProvider.isAuthenticated) {
      if (userProvider.isCaregiver) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const CaregiverDashboard()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const PatientHomeScreen()),
        );
      }
    } else {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Jade Green Gradient Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFE0F2F1), // Very light cool green
                  Color(0xFFB2DFDB), // Light Jade/Teal
                  Color(0xFF00A86B), // Jade Green
                ],
              ),
            ),
          ),

          // Floating Neomorphic Shapes
          _buildNeomorphicShape(top: 50, left: 30, size: 100, rotation: 0.2),
          _buildNeomorphicShape(top: 150, right: 40, size: 140, rotation: -0.1),
          _buildNeomorphicShape(
            bottom: 100,
            left: 20,
            size: 180,
            rotation: 0.15,
          ),
          _buildNeomorphicShape(
            bottom: 200,
            right: 30,
            size: 120,
            rotation: -0.2,
          ),
          _buildNeomorphicShape(top: 300, left: -20, size: 80, rotation: 0.3),
          _buildNeomorphicShape(
            bottom: 50,
            right: -10,
            size: 160,
            rotation: -0.15,
          ),

          // Main Content with animations
          FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Center(
                child: FadeTransition(
                  opacity: _logoFadeAnimation,
                  child: ScaleTransition(
                    scale: _logoScaleAnimation,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Glassmorphic Container for Logo
                        ClipRRect(
                          borderRadius: BorderRadius.circular(40),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(
                              sigmaX: 15.0,
                              sigmaY: 15.0,
                            ),
                            child: Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(40),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.4),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.3),
                                    blurRadius: 30,
                                    offset: const Offset(0, 15),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Image.asset(
                                  'web/icons/Dori_Logo.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 40),

                        // App Name with Shimmer
                        AnimatedBuilder(
                          animation: _shimmerAnimation,
                          builder: (context, child) {
                            return ShaderMask(
                              shaderCallback: (bounds) {
                                return LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: const [
                                    Colors.white70,
                                    Colors.white,
                                    Colors.white70,
                                  ],
                                  stops: [
                                    0.0,
                                    _shimmerAnimation.value.clamp(0.0, 1.0),
                                    1.0,
                                  ],
                                ).createShader(bounds);
                              },
                              child: const Text(
                                AppStrings.appName,
                                style: TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 2,
                                ),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 12),

                        // Tagline
                        Text(
                          'Your External Memory',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppColors.textPrimary.withOpacity(0.8),
                            letterSpacing: 1,
                          ),
                        ),

                        const SizedBox(height: 60),

                        // Loading Indicator with Glassmorphism
                        ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(
                              sigmaX: 10.0,
                              sigmaY: 10.0,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 30,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white.withOpacity(0.9),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    'Loading...',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.9),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNeomorphicShape({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required double size,
    required double rotation,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Transform.rotate(
        angle: rotation,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.secondary.withOpacity(0.3),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withOpacity(0.4),
                offset: const Offset(-8, -8),
                blurRadius: 16,
              ),
              BoxShadow(
                color: AppColors.primary.withOpacity(0.2),
                offset: const Offset(8, 8),
                blurRadius: 16,
              ),
            ],
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.4),
                Colors.white.withOpacity(0.1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
