import 'dart:io';
import 'package:dori/services/database_service.dart';
import 'package:dori/services/speech_service.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../services/face_recognition_service.dart';
import '../../models/known_face_model.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import 'package:image/image.dart' as img;
import 'live_face_enrollment_screen.dart';

class AddKnownFaceScreen extends StatefulWidget {
  final String patientId;

  const AddKnownFaceScreen({super.key, required this.patientId});

  @override
  State<AddKnownFaceScreen> createState() => _AddKnownFaceScreenState();
}

class _AddKnownFaceScreenState extends State<AddKnownFaceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _relationshipController = TextEditingController();
  final _notesController = TextEditingController();

  final DatabaseService _databaseService = DatabaseService();
  final FaceRecognitionService _faceRecognitionService =
      FaceRecognitionService();
  final ImagePicker _imagePicker = ImagePicker();

  File? _selectedImage;
  bool _isProcessing = false;

  // Live enrollment data
  List<File>? _capturedImages;
  List<List<double>>? _capturedEmbeddings;

  @override
  void initState() {
    super.initState();
    _initializeFaceRecognition();
  }

  Future<void> _initializeFaceRecognition() async {
    try {
      await _faceRecognitionService.initialize();
    } catch (e) {
      if (mounted) {
        Helpers.showSnackBar(
          context,
          'Failed to initialize face recognition',
          isError: true,
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _relationshipController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        Helpers.showSnackBar(context, 'Error picking image: $e', isError: true);
      }
    }
  }

  Future<void> _startLiveEnrollment() async {
    if (!_formKey.currentState!.validate()) return;

    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => LiveFaceEnrollmentScreen(
          personName: _nameController.text.trim(),
          relationship: _relationshipController.text.trim(),
          notes: _notesController.text.trim(),
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _capturedImages = (result['images'] as List).cast<File>();
        _capturedEmbeddings = (result['embeddings'] as List)
            .cast<List<double>>();
      });

      // Auto-save after live enrollment
      await _saveFaceWithLiveData();
    }
  }

  Future<void> _saveFace() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedImage == null) {
      Helpers.showSnackBar(context, 'Please select a photo', isError: true);
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // Detect face in image
      final faces = await _faceRecognitionService.detectFacesInFile(
        _selectedImage!,
      );

      if (faces.isEmpty) {
        throw 'No face detected in the image. Please choose a clear photo with a visible face.';
      }

      if (faces.length > 1) {
        throw 'Multiple faces detected. Please choose a photo with only one person.';
      }

      // Convert File to img.Image
      final bytes = await _selectedImage!.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        throw 'Failed to process image';
      }

      // Extract face embedding
      final embedding = await _faceRecognitionService.extractFaceEmbedding(
        image,
        faces.first,
      );

      if (embedding == null) {
        throw 'Failed to extract face features';
      }

      // Create known face model (with single embedding for now - will be multiple in live enrollment)
      final knownFace = KnownFaceModel(
        id: const Uuid().v4(),
        patientId: widget.patientId,
        name: _nameController.text.trim(),
        relationship: _relationshipController.text.trim(),
        embeddings: [embedding], // Wrap single embedding in a list
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        createdAt: DateTime.now(),
      );

      // Save to database
      await _databaseService.addKnownFace(knownFace, imageFile: _selectedImage);

      if (mounted) {
        Helpers.showSnackBar(context, 'Face added successfully!');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        Helpers.showSnackBar(context, e.toString(), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _saveFaceWithLiveData() async {
    if (_capturedEmbeddings == null || _capturedImages == null) return;

    setState(() => _isProcessing = true);

    try {
      final knownFace = KnownFaceModel(
        id: const Uuid().v4(),
        patientId: widget.patientId,
        name: _nameController.text.trim(),
        relationship: _relationshipController.text.trim(),
        embeddings: _capturedEmbeddings!,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        createdAt: DateTime.now(),
      );

      await _databaseService.addKnownFace(
        knownFace,
        imageFiles: _capturedImages,
      );

      if (mounted) {
        Helpers.showSnackBar(
          context,
          'Face enrolled with ${_capturedEmbeddings!.length} angles!',
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        Helpers.showSnackBar(context, e.toString(), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Add Known Face'),
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
              // Live Enrollment Button (Primary)
              ElevatedButton.icon(
                onPressed: _isProcessing ? null : _startLiveEnrollment,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Live Face Enrollment (Recommended)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(56),
                ),
              ),

              const SizedBox(height: 16),

              // Divider
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),

              const SizedBox(height: 16),

              // Image picker (Secondary option)
              GestureDetector(
                onTap: () => _showImagePickerOptions(),
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade300, width: 2),
                  ),
                  child: _selectedImage == null && _capturedImages == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Upload from Gallery',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: Colors.grey.shade600),
                            ),
                          ],
                        )
                      : _selectedImage != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.file(_selectedImage!, fit: BoxFit.cover),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: AppColors.primary,
                              size: 48,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_capturedImages!.length} angles captured',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // Name field
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Relationship field
              TextFormField(
                controller: _relationshipController,
                decoration: const InputDecoration(
                  labelText: 'Relationship',
                  hintText: 'e.g., Daughter, Friend, Doctor',
                  prefixIcon: Icon(Icons.favorite),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter relationship';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Notes field
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'e.g., Lives nearby, visits weekly',
                  prefixIcon: Icon(Icons.note),
                  filled: true,
                  fillColor: Colors.white,
                ),
                maxLines: 3,
              ),

              const SizedBox(height: 32),

              // Save button
              ElevatedButton(
                onPressed: _isProcessing ? null : _saveFace,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(56),
                ),
                child: _isProcessing
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
                    : const Text('Save Face'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select Photo',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.primary),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: AppColors.secondary,
              ),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }
}
