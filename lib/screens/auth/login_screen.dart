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
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Animation controllers for floating shapes
  late List<AnimationController> _floatControllers;
  late List<Animation<Offset>> _floatAnimations;
  final List<Offset> _randomDirections = [];

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

    // Initialize 10 floating animation controllers
    _floatControllers = List.generate(
      10,
      (index) => AnimationController(
        duration: Duration(seconds: 5 + (index % 10) * 2),
        vsync: this,
      )..repeat(reverse: true),
    );

    // Generate random directions
    final random = DateTime.now().millisecondsSinceEpoch;
    for (int i = 0; i < 10; i++) {
      final dx = (((random + i * 17) % 120) - 60).toDouble();
      final dy = (((random + i * 23) % 120) - 60).toDouble();
      _randomDirections.add(Offset(dx, dy));
    }

    _floatAnimations = List.generate(
      10,
      (index) =>
          Tween<Offset>(
            begin: Offset.zero,
            end: _randomDirections[index],
          ).animate(
            CurvedAnimation(
              parent: _floatControllers[index],
              curve: Curves.easeInOut,
            ),
          ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    for (var controller in _floatControllers) {
      controller.dispose();
    }
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1A4D4A), // Deep jade
              const Color(0xFF2A6D68), // Rich jade
              const Color(0xFF3A8D86), // Bright jade
              const Color(0xFF2A6D68), // Rich jade
            ],
            stops: const [0.0, 0.35, 0.65, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Neomorphic background shapes - Rounded rectangles
            AnimatedBuilder(
              animation: _floatAnimations[0],
              builder: (context, child) => Positioned(
                top: 80 + _floatAnimations[0].value.dy,
                left: 30 + _floatAnimations[0].value.dx,
                child: Container(
                  width: 180,
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(40),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.background, const Color(0xFF5AA99E)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1A4D4A),
                        offset: const Offset(12, 12),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _floatAnimations[1],
              builder: (context, child) => Positioned(
                bottom: 120 + _floatAnimations[1].value.dy,
                right: 20 + _floatAnimations[1].value.dx,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(50),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.background, const Color(0xFF5AA99E)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1A4D4A),
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
            ),
            AnimatedBuilder(
              animation: _floatAnimations[2],
              builder: (context, child) => Positioned(
                top: 280 + _floatAnimations[2].value.dy,
                right: 60 + _floatAnimations[2].value.dx,
                child: Container(
                  width: 140,
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(35),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.background, const Color(0xFF5AA99E)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1A4D4A),
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
            ),
            AnimatedBuilder(
              animation: _floatAnimations[3],
              builder: (context, child) => Positioned(
                top: 200 + _floatAnimations[3].value.dy,
                left: 40 + _floatAnimations[3].value.dx,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.background, const Color(0xFF5AA99E)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1A4D4A),
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
            ),
            AnimatedBuilder(
              animation: _floatAnimations[4],
              builder: (context, child) => Positioned(
                bottom: 300 + _floatAnimations[4].value.dy,
                left: 20 + _floatAnimations[4].value.dx,
                child: Container(
                  width: 120,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.background, const Color(0xFF5AA99E)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1A4D4A),
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
            ),
            AnimatedBuilder(
              animation: _floatAnimations[5],
              builder: (context, child) => Positioned(
                top: 450 + _floatAnimations[5].value.dy,
                right: 40 + _floatAnimations[5].value.dx,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(38),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.background, const Color(0xFF5AA99E)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1A4D4A),
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
            ),
            AnimatedBuilder(
              animation: _floatAnimations[6],
              builder: (context, child) => Positioned(
                bottom: 50 + _floatAnimations[6].value.dy,
                left: 60 + _floatAnimations[6].value.dx,
                child: Container(
                  width: 130,
                  height: 95,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(36),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.background, const Color(0xFF5AA99E)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1A4D4A),
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
            ),
            AnimatedBuilder(
              animation: _floatAnimations[7],
              builder: (context, child) => Positioned(
                top: 150 + _floatAnimations[7].value.dy,
                right: 20 + _floatAnimations[7].value.dx,
                child: Container(
                  width: 90,
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.background, const Color(0xFF5AA99E)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1A4D4A),
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
            ),
            AnimatedBuilder(
              animation: _floatAnimations[8],
              builder: (context, child) => Positioned(
                bottom: 200 + _floatAnimations[8].value.dy,
                right: 50 + _floatAnimations[8].value.dx,
                child: Container(
                  width: 105,
                  height: 85,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(34),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.background, const Color(0xFF5AA99E)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1A4D4A),
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
            ),
            AnimatedBuilder(
              animation: _floatAnimations[9],
              builder: (context, child) => Positioned(
                top: 360 + _floatAnimations[9].value.dy,
                left: 25 + _floatAnimations[9].value.dx,
                child: Container(
                  width: 115,
                  height: 115,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(42),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.background, const Color(0xFF5AA99E)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1A4D4A),
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
                        // App Icon - Jade Glassmorphism
                        Center(
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF3A8D86,
                              ).withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: const Color(
                                  0xFF5AA99E,
                                ).withValues(alpha: 0.5),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF1A4D4A,
                                  ).withValues(alpha: 0.4),
                                  blurRadius: 30,
                                  offset: const Offset(0, 15),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.face,
                              size: 70,
                              color: const Color(0xFFC5F5F0),
                            ),
                          ),
                        ),

                        const SizedBox(height: 40),

                        // Main Login Card - Jade Glassmorphism
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF2A6D68,
                            ).withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: const Color(
                                0xFF5AA99E,
                              ).withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF0D2624,
                                ).withValues(alpha: 0.5),
                                blurRadius: 40,
                                offset: const Offset(0, 20),
                                spreadRadius: 5,
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
                                      color: const Color(0xFFC5F5F0),
                                      letterSpacing: 0.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),

                                  const SizedBox(height: 8),

                                  Text(
                                    'Sign in to continue',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: const Color(0xFF9DE5DC),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),

                                  const SizedBox(height: 24),

                                  // Email field - Jade Glassmorphism
                                  Container(
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF5AA99E,
                                      ).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF5AA99E,
                                        ).withValues(alpha: 0.4),
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(
                                            0xFF1A4D4A,
                                          ).withValues(alpha: 0.3),
                                          blurRadius: 15,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: TextFormField(
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      style: const TextStyle(
                                        color: Color(0xFFC5F5F0),
                                      ),
                                      decoration: InputDecoration(
                                        labelText: AppStrings.emailHint,
                                        labelStyle: TextStyle(
                                          color: const Color(
                                            0xFF9DE5DC,
                                          ).withValues(alpha: 0.8),
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.email_outlined,
                                          color: Color(0xFF9DE5DC),
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

                                  // Password field - Jade Glassmorphism
                                  Container(
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF3A8D86,
                                      ).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF5AA99E,
                                        ).withValues(alpha: 0.5),
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(
                                            0xFF1A4D4A,
                                          ).withValues(alpha: 0.3),
                                          blurRadius: 15,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: TextFormField(
                                      controller: _passwordController,
                                      obscureText: !_isPasswordVisible,
                                      style: const TextStyle(
                                        color: Color(0xFFC5F5F0),
                                      ),
                                      decoration: InputDecoration(
                                        labelText: AppStrings.passwordHint,
                                        labelStyle: TextStyle(
                                          color: const Color(
                                            0xFF9DE5DC,
                                          ).withValues(alpha: 0.8),
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.lock_outline,
                                          color: Color(0xFF9DE5DC),
                                        ),
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _isPasswordVisible
                                                ? Icons.visibility_off
                                                : Icons.visibility,
                                            color: const Color(0xFF9DE5DC),
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
                                          return 'Password must be at least 6 characters';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),

                                  const SizedBox(height: 24),

                                  // Login button - Dark Jade
                                  GestureDetector(
                                    onTap: _isLoading ? null : _handleLogin,
                                    child: Container(
                                      height: 58,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1A4D4A),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: const Color(
                                            0xFF3A8D86,
                                          ).withValues(alpha: 0.5),
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(
                                              0xFF0D2624,
                                            ).withValues(alpha: 0.6),
                                            blurRadius: 20,
                                            offset: const Offset(0, 8),
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
                                                      >(Color(0xFFC5F5F0)),
                                                ),
                                              )
                                            : const Text(
                                                AppStrings.loginButton,
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFFC5F5F0),
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
                                          color: const Color(0xFF9DE5DC),
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
                                            color: const Color(0xFF5AA99E),
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
