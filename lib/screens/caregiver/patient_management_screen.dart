import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../models/user_model.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';

class PatientManagementScreen extends StatefulWidget {
  const PatientManagementScreen({super.key});

  @override
  State<PatientManagementScreen> createState() =>
      _PatientManagementScreenState();
}

class _PatientManagementScreenState extends State<PatientManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final AuthService _authService = AuthService();
  final DatabaseService _databaseService = DatabaseService();

  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _createPatient() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final caregiver = userProvider.currentUser!;
      final caregiverId = caregiver.uid;

      // Store caregiver credentials to re-authenticate later
      final caregiverEmail = caregiver.email;

      // Show dialog to get caregiver password for re-authentication
      final caregiverPassword = await _showPasswordDialog();

      if (caregiverPassword == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Create Firebase Auth user for patient (this will switch auth context)
      final firebaseUser = await _authService.createUserWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (firebaseUser == null) {
        throw 'Failed to create patient account';
      }

      // Create patient user document (authenticated as patient now)
      final patient = UserModel(
        uid: firebaseUser.uid,
        email: _emailController.text.trim(),
        name: _nameController.text.trim(),
        role: 'patient',
        caregiverId: caregiverId,
        createdAt: DateTime.now(),
      );

      await _databaseService.createUser(patient);

      // Sign back in as caregiver to link patient
      await _authService.signInWithEmail(caregiverEmail, caregiverPassword);

      // Now authenticated as caregiver, can update caregiver document
      await _databaseService.linkPatientToCaregiver(
        caregiverId,
        firebaseUser.uid,
      );

      if (mounted) {
        Helpers.showSnackBar(context, 'Patient account created successfully!');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        Helpers.showSnackBar(
          context,
          'Error creating patient: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<String?> _showPasswordDialog() async {
    final passwordController = TextEditingController();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Your Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please enter your password to create a patient account:',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Your Password',
                prefixIcon: Icon(Icons.lock),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(passwordController.text);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Add New Patient'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Create an account for your patient. They can use these credentials to log in.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Name field
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Patient Name',
                  prefixIcon: Icon(Icons.person),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter patient name';
                  }
                  if (value.length < 2) {
                    return 'Name must be at least 2 characters';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Email field
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter email';
                  }
                  if (!Helpers.isValidEmail(value)) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Password field
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock),
                  filled: true,
                  fillColor: Colors.white,
                  helperText: 'Create a simple password they can remember',
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

              const SizedBox(height: 32),

              // Create button
              ElevatedButton(
                onPressed: _isLoading ? null : _createPatient,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(56),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text('Create Patient Account'),
              ),

              const SizedBox(height: 16),

              // Note
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lightbulb_outline,
                      color: Colors.amber,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tip: Use a simple, memorable password. You can always help them log in.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
