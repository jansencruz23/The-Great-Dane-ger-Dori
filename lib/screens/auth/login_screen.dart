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
      body: Container(
        color: AppColors.background,
        child: Stack(
          children: [
            // Neomorphic background shapes - Rounded rectangles
            Positioned(
              top: 80,
              left: 30,
              child: Container(
                width: 180,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(40),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.background, const Color(0xFFE8DCC8)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD4C4A8),
                      offset: const Offset(12, 12),
                      blurRadius: 24,
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.9),
                      offset: const Offset(-12, -12),
                      blurRadius: 24,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 120,
              right: 20,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(50),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.background, const Color(0xFFE8DCC8)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD4C4A8),
                      offset: const Offset(12, 12),
                      blurRadius: 24,
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.9),
                      offset: const Offset(-12, -12),
                      blurRadius: 24,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 280,
              right: 60,
              child: Container(
                width: 140,
                height: 90,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(35),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.background, const Color(0xFFE8DCC8)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD4C4A8),
                      offset: const Offset(12, 12),
                      blurRadius: 24,
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.9),
                      offset: const Offset(-12, -12),
                      blurRadius: 24,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 200,
              left: 40,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.background, const Color(0xFFE8DCC8)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD4C4A8),
                      offset: const Offset(12, 12),
                      blurRadius: 24,
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.9),
                      offset: const Offset(-12, -12),
                      blurRadius: 24,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 300,
              left: 20,
              child: Container(
                width: 120,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.background, const Color(0xFFE8DCC8)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD4C4A8),
                      offset: const Offset(12, 12),
                      blurRadius: 24,
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.9),
                      offset: const Offset(-12, -12),
                      blurRadius: 24,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 450,
              right: 40,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(38),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.background, const Color(0xFFE8DCC8)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD4C4A8),
                      offset: const Offset(12, 12),
                      blurRadius: 24,
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.9),
                      offset: const Offset(-12, -12),
                      blurRadius: 24,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 50,
              left: 60,
              child: Container(
                width: 130,
                height: 95,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(36),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.background, const Color(0xFFE8DCC8)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD4C4A8),
                      offset: const Offset(12, 12),
                      blurRadius: 24,
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.9),
                      offset: const Offset(-12, -12),
                      blurRadius: 24,
                    ),
                  ],
                ),
              ),
            ),
            // Main content
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
                        // App Icon - BLUE
                        Center(
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.face,
                              size: 70,
                              color: Colors.white,
                            ),
                          ),
                        ),

                        const SizedBox(height: 40),

                        // Main Login Card - CREAM WHITE with Neomorphism
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              // Dark shadow (bottom-right)
                              BoxShadow(
                                color: const Color(0xFFD4C4A8),
                                blurRadius: 30,
                                offset: const Offset(15, 15),
                                spreadRadius: 0,
                              ),
                              // Light shadow (top-left)
                              BoxShadow(
                                color: Colors.white,
                                blurRadius: 30,
                                offset: const Offset(-15, -15),
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Title
                                  Text(
                                    AppStrings.loginTitle,
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
                                    'Sign in to continue',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: AppColors.textSecondary,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),

                                  const SizedBox(height: 24),

                                  // Email field - YELLOW
                                  Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.secondary,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.secondary.withValues(
                                            alpha: 0.3,
                                          ),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: TextFormField(
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      style: const TextStyle(
                                        color: Colors.black,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: AppStrings.emailHint,
                                        labelStyle: TextStyle(
                                          color: Colors.black.withValues(
                                            alpha: 0.6,
                                          ),
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.email_outlined,
                                          color: Colors.black,
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

                                  // Password field - LIGHT BLUE
                                  Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.25,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: AppColors.primary,
                                        width: 2,
                                      ),
                                    ),
                                    child: TextFormField(
                                      controller: _passwordController,
                                      obscureText: !_isPasswordVisible,
                                      style: const TextStyle(
                                        color: Colors.black,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: AppStrings.passwordHint,
                                        labelStyle: TextStyle(
                                          color: Colors.black.withValues(
                                            alpha: 0.6,
                                          ),
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.lock_outline,
                                          color: Colors.black,
                                        ),
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _isPasswordVisible
                                                ? Icons.visibility_off
                                                : Icons.visibility,
                                            color: Colors.black,
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

                                  // Login button - DARK BLUE
                                  GestureDetector(
                                    onTap: _isLoading ? null : _handleLogin,
                                    child: Container(
                                      height: 58,
                                      decoration: BoxDecoration(
                                        color: AppColors.accent,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.accent.withValues(
                                              alpha: 0.4,
                                            ),
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
                                    mainAxisAlignment: MainAxisAlignment.center,
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
