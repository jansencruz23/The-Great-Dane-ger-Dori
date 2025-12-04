import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../services/database_service.dart';
import '../../models/user_model.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../auth/login_screen.dart';
import 'patient_management_screen.dart';
import 'manage_known_faces_screen.dart';
import 'activity_history_screen.dart';

class CaregiverDashboard extends StatefulWidget {
  const CaregiverDashboard({super.key});

  @override
  State<CaregiverDashboard> createState() => _CaregiverDashboardState();
}

class _CaregiverDashboardState extends State<CaregiverDashboard>
    with SingleTickerProviderStateMixin {
  final DatabaseService _databaseService = DatabaseService();
  List<UserModel> _patients = [];
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  final List<Color> _profileColors = [
    const Color(0xFF00A86B), // Jade Green (Base)
    const Color(0xFF2E7D32), // Forest Green (Monochromatic Shade)
    const Color(0xFF009688), // Teal (Analogous)
    const Color(0xFF80CBC4), // Seafoam (Tint)
    const Color(0xFFE0F2F1), // Pale Aqua (Light Tint)
    const Color(0xFF78909C), // Blue Grey (Neutral Cool)
    Colors.white, // White (Neutral)
    const Color(0xFFFFD54F), // Amber/Gold (Triadic/Rich pairing)
    const Color(0xFFFF8A65), // Deep Orange/Coral (Split Complementary)
    const Color(0xFFF06292), // Pink/Rose (Complementary)
  ];

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
    _loadPatients();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadPatients() async {
    setState(() => _isLoading = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final patients = await _databaseService.getCaregiversPatients(
        userProvider.currentUser!.uid,
      );

      setState(() {
        _patients = patients;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        Helpers.showSnackBar(
          context,
          'Error loading patients $e',
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

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

          // 3. Main Content
          SafeArea(
            child: Column(
              children: [
                // Custom AppBar
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppStrings.caregiverDashboard,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: AppColors.error),
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
                ),

                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadPatients,
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _buildContent(user),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (_) => const PatientManagementScreen(),
                ),
              )
              .then((_) => _loadPatients());
        },
        icon: const Icon(Icons.person_add),
        label: const Text('Add Patient'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  Widget _buildContent(UserModel user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      physics: const AlwaysScrollableScrollPhysics(),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Welcome header
            Text(
              'Welcome, ${user.name}',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Manage your patients and their memory assistance',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),

            const SizedBox(height: 32),

            // Statistics
            if (_patients.isNotEmpty)
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.people,
                      label: 'Patients',
                      value: _patients.length.toString(),
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.face,
                      label: 'Known Faces',
                      value: '${_patients.length * 5}+',
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 32),

            // Patients list
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppStrings.myPatients,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_patients.isEmpty)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                              builder: (_) => const PatientManagementScreen(),
                            ),
                          )
                          .then((_) => _loadPatients());
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add First Patient'),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            if (_patients.isEmpty)
              _buildEmptyState()
            else
              ..._patients.map((patient) => _buildPatientCard(patient)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 36),
              const SizedBox(height: 12),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.5)),
          ),
          child: Column(
            children: [
              Icon(
                Icons.people_outline,
                size: 80,
                color: AppColors.textSecondary.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No patients yet',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Add your first patient to start managing their memory assistance',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPatientCard(UserModel patient) {
    final baseColor = patient.profileColor != null
        ? Color(patient.profileColor!)
        : Colors.white;

    // Calculate contrast color based on the base color
    final isDark = baseColor.computeLuminance() < 0.5;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: baseColor.withOpacity(0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.all(20),
                leading: CircleAvatar(
                  radius: 30,
                  backgroundColor: Helpers.generateColorFromString(
                    patient.name,
                  ),
                  child: Text(
                    Helpers.getInitials(patient.name),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  patient.name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  patient.email,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: subTextColor),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: subTextColor,
                ),
                onTap: () {
                  _showPatientActions(patient);
                },
              ),
              Divider(height: 1, color: subTextColor.withOpacity(0.2)),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ManageKnownFacesScreen(
                                patientId: patient.uid,
                                patientName: patient.name,
                              ),
                            ),
                          );
                        },
                        icon: Icon(Icons.face, size: 18, color: textColor),
                        label: Text(
                          'Faces',
                          style: TextStyle(color: textColor),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textColor,
                          side: BorderSide(
                            color: subTextColor.withOpacity(0.5),
                          ),
                          backgroundColor: Colors.white.withOpacity(0.2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ActivityHistoryScreen(
                                patientId: patient.uid,
                                patientName: patient.name,
                              ),
                            ),
                          );
                        },
                        icon: Icon(Icons.history, size: 18, color: textColor),
                        label: Text(
                          'Activity',
                          style: TextStyle(color: textColor),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textColor,
                          side: BorderSide(
                            color: subTextColor.withOpacity(0.5),
                          ),
                          backgroundColor: Colors.white.withOpacity(0.2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _showColorPicker(patient),
                      icon: Icon(Icons.color_lens, color: textColor),
                      tooltip: 'Change Color',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.2),
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

  void _showPatientActions(UserModel patient) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              patient.name,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.face, color: AppColors.primary),
              title: const Text('Manage Known Faces'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ManageKnownFacesScreen(
                      patientId: patient.uid,
                      patientName: patient.name,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.history, color: AppColors.secondary),
              title: const Text('View Activity History'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ActivityHistoryScreen(
                      patientId: patient.uid,
                      patientName: patient.name,
                    ),
                  ),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit, color: AppColors.primary),
              title: const Text('Edit Patient Info'),
              onTap: () {
                Navigator.of(context).pop();
                _editPatient(patient);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: AppColors.error),
              title: const Text('Delete Patient'),
              onTap: () {
                Navigator.of(context).pop();
                _deletePatient(patient);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showColorPicker(UserModel patient) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pick Profile Color',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: _profileColors.map((color) {
                final isSelected =
                    patient.profileColor == color.value ||
                    (patient.profileColor == null && color == Colors.white);
                return GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    _updatePatientColor(patient, color);
                  },
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.grey.withOpacity(0.3),
                        width: 1,
                      ),
                      boxShadow: [
                        if (isSelected)
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.4),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                      ],
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updatePatientColor(UserModel patient, Color color) async {
    try {
      final updatedPatient = patient.copyWith(profileColor: color.value);

      // Optimistic update
      setState(() {
        final index = _patients.indexWhere((p) => p.uid == patient.uid);
        if (index != -1) {
          _patients[index] = updatedPatient;
        }
      });

      await _databaseService.updateUser(updatedPatient);
    } catch (e) {
      // Revert on error
      _loadPatients();
      if (mounted) {
        Helpers.showSnackBar(
          context,
          'Error updating color: $e',
          isError: true,
        );
      }
    }
  }

  void _editPatient(UserModel patient) {
    final nameController = TextEditingController(text: patient.name);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Patient Info'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Patient Name',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
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
              Text(
                'Email: ${patient.email}',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final updatedPatient = patient.copyWith(
                name: nameController.text.trim(),
              );

              try {
                await _databaseService.updateUser(updatedPatient);

                if (context.mounted) {
                  Navigator.of(context).pop();
                  Helpers.showSnackBar(context, 'Patient updated successfully');
                  _loadPatients();
                }
              } catch (e) {
                if (context.mounted) {
                  Helpers.showSnackBar(
                    context,
                    'Error updating patient: $e',
                    isError: true,
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deletePatient(UserModel patient) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Patient'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete ${patient.name}?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: AppColors.error, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This will delete all known faces and activity logs for this patient. This action cannot be undone.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
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
            onPressed: () async {
              try {
                await _databaseService.deleteUser(patient.uid);

                if (context.mounted) {
                  Navigator.of(context).pop();
                  Helpers.showSnackBar(context, 'Patient deleted successfully');
                  _loadPatients();
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.of(context).pop();
                  Helpers.showSnackBar(
                    context,
                    'Error deleting patient: $e',
                    isError: true,
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
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
