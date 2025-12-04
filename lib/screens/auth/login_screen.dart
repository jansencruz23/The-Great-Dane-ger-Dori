import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import 'register_screen.dart';
import '../caregiver/caregiver_dashboard.dart';
import '../patient/patient_home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final userProvider = Provider.of<UserProvider>(context, listen: false);

    final success = await userProvider.login(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (success) {
      // Navigate based on role
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
      Helpers.showSnackBar(
        context,
        userProvider.error ?? 'Login failed',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Jade Green Gradient Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFE0F2F1), // Very light cool green (Background)
                  Color(0xFFB2DFDB), // Light Jade/Teal (Secondary)
                  Color(0xFF00A86B), // Jade Green (Primary)
                ],
              ),
            ),
          ),

          // 2. Floating Neomorphic Quadrilaterals (10 shapes)
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
          _buildNeomorphicShape(top: 80, right: 100, size: 60, rotation: 0.4),
          _buildNeomorphicShape(
            bottom: 350,
            left: 50,
            size: 90,
            rotation: -0.3,
          ),
          _buildNeomorphicShape(top: 400, right: 20, size: 110, rotation: 0.1),
          _buildNeomorphicShape(
            bottom: 20,
            left: 150,
            size: 70,
            rotation: -0.25,
          ),

          // 3. Main Content with Glassmorphism
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // App Icon
                      Center(
                        child: Container(
                          width: 120,
                          height: 120,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'web/icons/Dori_Logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Glassmorphism Login Card
                      ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(
                            sigmaX: 10.0,
                            sigmaY: 10.0,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Title
                                    Text(
                                      'Dori',
                                      style: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                        letterSpacing: 0.5,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),

                                    const SizedBox(height: 8),

                                    Text(
                                      "'Wag mag-alala kung walang maalala",
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: AppColors.textSecondary,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),

                                    const SizedBox(height: 24),

                                    // Email field
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.5),
                                        ),
                                      ),
                                      child: TextFormField(
                                        controller: _emailController,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                        ),
                                        decoration: InputDecoration(
                                          labelText: AppStrings.emailHint,
                                          labelStyle: TextStyle(
                                            color: AppColors.textSecondary,
                                          ),
                                          prefixIcon: const Icon(
                                            Icons.email_outlined,
                                            color: AppColors.textPrimary,
                                          ),
                                          border: InputBorder.none,
                                          contentPadding: const EdgeInsets.all(
                                            20,
                                          ),
                                        ),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter your email';
                                          }
                                          if (!Helpers.isValidEmail(value)) {
                                            return 'Please enter a valid email';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),

                                    const SizedBox(height: 16),

                                    // Password field
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.5),
                                        ),
                                      ),
                                      child: TextFormField(
                                        controller: _passwordController,
                                        obscureText: !_isPasswordVisible,
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                        ),
                                        decoration: InputDecoration(
                                          labelText: AppStrings.passwordHint,
                                          labelStyle: TextStyle(
                                            color: AppColors.textSecondary,
                                          ),
                                          prefixIcon: const Icon(
                                            Icons.lock_outline,
                                            color: AppColors.textPrimary,
                                          ),
                                          suffixIcon: IconButton(
                                            icon: Icon(
                                              _isPasswordVisible
                                                  ? Icons.visibility_off
                                                  : Icons.visibility,
                                              color: AppColors.textPrimary,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                _isPasswordVisible =
                                                    !_isPasswordVisible;
                                              });
                                            },
                                          ),
                                          border: InputBorder.none,
                                          contentPadding: const EdgeInsets.all(
                                            20,
                                          ),
                                        ),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter your password';
                                          }
                                          if (value.length < 6) {
                                            return 'Password must be at least 6 characters.';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),

                                    const SizedBox(height: 24),

                                    // Login button
                                    GestureDetector(
                                      onTap: _isLoading ? null : _handleLogin,
                                      child: Container(
                                        height: 58,
                                        decoration: BoxDecoration(
                                          color: AppColors.primary,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppColors.primary
                                                  .withOpacity(0.4),
                                              blurRadius: 15,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: _isLoading
                                              ? const SizedBox(
                                                  height: 20,
                                                  width: 20,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                          Color
                                                        >(Colors.white),
                                                  ),
                                                )
                                              : const Text(
                                                  AppStrings.loginButton,
                                                  style: TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 16),

                                    // Register link
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          AppStrings.noAccountText,
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 14,
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const RegisterScreen(),
                                              ),
                                            );
                                          },
                                          child: Text(
                                            'Sign Up',
                                            style: TextStyle(
                                              color: AppColors.accent,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
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
