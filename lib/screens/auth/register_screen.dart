import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../caregiver/caregiver_dashboard.dart';
import '../patient/patient_home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;
  String _selectedRole = 'patient';
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
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final userProvider = Provider.of<UserProvider>(context, listen: false);

    final success = await userProvider.register(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      name: _nameController.text.trim(),
      role: _selectedRole,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (success) {
      Helpers.showSnackBar(context, 'Account created successfully');

      // Navigate based on role
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

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
        userProvider.error ?? 'Registration failed',
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

          // 2. Floating Neomorphic Quadrilaterals
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
                      // Back Button
                      Align(
                        alignment: Alignment.topLeft,
                        child: IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: AppColors.textPrimary,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Glassmorphism Register Card
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
                                      AppStrings.registerTitle,
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
                                      'Create your account',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: AppColors.textSecondary,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),

                                    const SizedBox(height: 24),

                                    // Name field
                                    _buildTextField(
                                      controller: _nameController,
                                      label: AppStrings.nameHint,
                                      icon: Icons.person_outline,
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Please enter your name';
                                        }
                                        if (value.length < 2) {
                                          return 'Name must be at least 2 characters';
                                        }
                                        return null;
                                      },
                                    ),

                                    const SizedBox(height: 16),

                                    // Email field
                                    _buildTextField(
                                      controller: _emailController,
                                      label: AppStrings.emailHint,
                                      icon: Icons.email_outlined,
                                      keyboardType: TextInputType.emailAddress,
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

                                    const SizedBox(height: 16),

                                    // Password field
                                    _buildTextField(
                                      controller: _passwordController,
                                      label: AppStrings.passwordHint,
                                      icon: Icons.lock_outline,
                                      obscureText: !_isPasswordVisible,
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
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Please enter a password';
                                        }
                                        if (value.length < 6) {
                                          return 'Password must be at least 6 characters';
                                        }
                                        return null;
                                      },
                                    ),

                                    const SizedBox(height: 16),

                                    // Confirm password field
                                    _buildTextField(
                                      controller: _confirmPasswordController,
                                      label: 'Confirm Password',
                                      icon: Icons.lock_outline,
                                      obscureText: !_isConfirmPasswordVisible,
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _isConfirmPasswordVisible
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                          color: AppColors.textPrimary,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _isConfirmPasswordVisible =
                                                !_isConfirmPasswordVisible;
                                          });
                                        },
                                      ),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Please confirm your password';
                                        }
                                        if (value != _passwordController.text) {
                                          return 'Passwords do not match';
                                        }
                                        return null;
                                      },
                                    ),

                                    const SizedBox(height: 24),

                                    // Role selection
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.5),
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            'I am a:',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textPrimary,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          _buildRoleOption(
                                            value: 'patient',
                                            title: 'Patient',
                                            subtitle:
                                                'I need memory assistance',
                                          ),
                                          _buildRoleOption(
                                            value: 'caregiver',
                                            title: 'Caregiver',
                                            subtitle: 'I care for someone',
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 32),

                                    // Register button
                                    GestureDetector(
                                      onTap: _isLoading
                                          ? null
                                          : _handleRegister,
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
                                                  AppStrings.registerButton,
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

                                    // Login link
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          AppStrings.haveAccountText,
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 14,
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop(),
                                          child: Text(
                                            'Sign In',
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.5)),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: AppColors.textSecondary),
          prefixIcon: Icon(icon, color: AppColors.textPrimary),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(20),
        ),
        validator: validator,
      ),
    );
  }

  Widget _buildRoleOption({
    required String value,
    required String title,
    required String subtitle,
  }) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedRole = value;
        });
      },
      child: Row(
        children: [
          Radio<String>(
            value: value,
            groupValue: _selectedRole,
            onChanged: (String? newValue) {
              setState(() {
                _selectedRole = newValue!;
              });
            },
            activeColor: AppColors.primary,
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
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
