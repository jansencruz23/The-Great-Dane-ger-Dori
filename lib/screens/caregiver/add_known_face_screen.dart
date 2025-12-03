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

  List<File> _selectedImages = [];
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
      if (source == ImageSource.gallery) {
        // Use multi-select for gallery
        // Higher quality settings to match live enrollment accuracy
        final List<XFile> images = await _imagePicker.pickMultiImage(
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 100, // No compression to preserve facial details
        );

        if (images.isNotEmpty) {
          setState(() {
            _selectedImages = images.map((xFile) => File(xFile.path)).toList();
          });
        }
      } else {
        // Use single select for camera
        // Higher quality settings to match live enrollment accuracy
        final XFile? image = await _imagePicker.pickImage(
          source: source,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 100, // No compression to preserve facial details
        );

        if (image != null) {
          setState(() {
            _selectedImages = [File(image.path)];
          });
        }
      }
    } catch (e) {
      if (mounted) {
        Helpers.showSnackBar(
          context,
          'Error picking image(s): $e',
          isError: true,
        );
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

    if (_selectedImages.isEmpty) {
      Helpers.showSnackBar(
        context,
        'Please select at least one photo',
        isError: true,
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final List<List<double>> allEmbeddings = [];

      // Process each selected image
      for (int i = 0; i < _selectedImages.length; i++) {
        final selectedImage = _selectedImages[i];

        // Detect face in image
        final faces = await _faceRecognitionService.detectFacesInFile(
          selectedImage,
        );

        if (faces.isEmpty) {
          continue;
        }

        if (faces.length > 1) {
          continue;
        }

        // Convert File to img.Image
        final bytes = await selectedImage.readAsBytes();
        var image = img.decodeImage(bytes);

        if (image == null) {
          throw 'Failed to process image ${i + 1}';
        }

        // Fix orientation (handle EXIF rotation)
        image = img.bakeOrientation(image);

        // Rotate 90 degrees counterclockwise to match live enrollment orientation
        image = img.copyRotate(image, angle: -90);

        // Extract face embedding
        final embedding = await _faceRecognitionService.extractFaceEmbedding(
          image,
          faces.first,
        );

        if (embedding == null) {
          throw 'Failed to extract face features from image ${i + 1}';
        }

        allEmbeddings.add(embedding);
      }

      // Create known face model with all embeddings
      final knownFace = KnownFaceModel(
        id: const Uuid().v4(),
        patientId: widget.patientId,
        name: _nameController.text.trim(),
        relationship: _relationshipController.text.trim(),
        embeddings: allEmbeddings,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        createdAt: DateTime.now(),
      );

      // Save to database
      await _databaseService.addKnownFace(
        knownFace,
        imageFiles: _selectedImages,
      );

      if (mounted) {
        Helpers.showSnackBar(
          context,
          'Face added successfully with ${allEmbeddings.length} image(s)!',
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
                  child: _selectedImages.isEmpty && _capturedImages == null
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
                              'Upload from Gallery (Multiple)',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: Colors.grey.shade600),
                            ),
                          ],
                        )
                      : _selectedImages.isNotEmpty
                      ? _selectedImages.length == 1
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.file(
                                  _selectedImages[0],
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: GridView.builder(
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        crossAxisSpacing: 8,
                                        mainAxisSpacing: 8,
                                      ),
                                  itemCount: _selectedImages.length,
                                  itemBuilder: (context, index) {
                                    return ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Image.file(
                                            _selectedImages[index],
                                            fit: BoxFit.cover,
                                          ),
                                          Positioned(
                                            top: 4,
                                            right: 4,
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: const BoxDecoration(
                                                color: AppColors.primary,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Text(
                                                '${index + 1}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
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
