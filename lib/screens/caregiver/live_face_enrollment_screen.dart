import 'dart:async';
import 'dart:io';
import 'package:dori/services/face_recognition_service.dart';
import 'package:dori/services/speech_service.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../main.dart' show cameras;
import '../../utils/constants.dart';
import '../../utils/helpers.dart';

enum FacePose { center, left, right, up, down }

class LiveFaceEnrollmentScreen extends StatefulWidget {
  final String personName;
  final String relationship;
  final String? notes;

  const LiveFaceEnrollmentScreen({
    super.key,
    required this.personName,
    required this.relationship,
    this.notes,
  });

  @override
  State<LiveFaceEnrollmentScreen> createState() =>
      _LiveFaceEnrollmentScreenState();
}

class _LiveFaceEnrollmentScreenState extends State<LiveFaceEnrollmentScreen> {
  CameraController? _cameraController;
  final FaceRecognitionService _faceRecognitionService =
      FaceRecognitionService();

  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isStreamActive = false;

  // Captured data
  final Map<FacePose, File> _capturedImages = {};
  final Map<FacePose, List<double>> _capturedEmbeddings = {};

  // Current detected pose
  FacePose? _currentPose;

  // Auto-capture state
  DateTime? _lastCaptureTime;
  static const _captureDebounceTime = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    if (_isStreamActive && _cameraController != null) {
      _cameraController!.stopImageStream();
    }
    _cameraController?.dispose();
    _faceRecognitionService.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      await _faceRecognitionService.initialize();

      if (cameras.isEmpty) {
        throw 'No camera available';
      }

      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() => _isInitialized = true);
        _startFrameProcessing();
      }
    } catch (e) {
      if (mounted) {
        Helpers.showSnackBar(
          context,
          'Camera initialization failed: $e',
          isError: true,
        );
      }
    }
  }

  void _startFrameProcessing() {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isStreamActive) {
      return;
    }

    setState(() => _isStreamActive = true);

    _cameraController!.startImageStream((CameraImage cameraImage) async {
      if (_isProcessing) return;

      _isProcessing = true;

      try {
        final rotation = _getInputImageRotation();

        // Detect faces
        final faces = await _faceRecognitionService.detectFaces(
          cameraImage,
          rotation,
        );

        if (faces.isNotEmpty && mounted) {
          final face = faces.first;

          // Detect pose
          final pose = _detectPose(face);

          setState(() {
            _currentPose = pose;
          });

          // Auto-capture if pose is valid and not recently captured
          if (pose != null && !_capturedEmbeddings.containsKey(pose)) {
            await _attemptCapture(pose, cameraImage, face);
          }
        } else {
          setState(() {
            _currentPose = null;
          });
        }
      } catch (e) {
        print('Error processing frame: $e');
      } finally {
        await Future.delayed(const Duration(milliseconds: 300));
        _isProcessing = false;
      }
    });
  }

  InputImageRotation _getInputImageRotation() {
    final orientation = MediaQuery.of(context).orientation;

    if (orientation == Orientation.landscape) {
      return InputImageRotation.rotation0deg;
    } else {
      return InputImageRotation.rotation90deg;
    }
  }

  FacePose? _detectPose(Face face) {
    // Get head euler angles
    final yaw = face.headEulerAngleY ?? 0; // Left/right rotation
    final pitch = face.headEulerAngleX ?? 0; // Up/down rotation

    print(
      'DEBUG: Pose - Yaw: ${yaw.toStringAsFixed(1)}, Pitch: ${pitch.toStringAsFixed(1)}',
    );

    // Define pose thresholds (with tolerance)
    if (yaw.abs() < 8 && pitch.abs() < 8) {
      return FacePose.center;
    } else if (yaw < -20 && yaw > -40) {
      return FacePose.left;
    } else if (yaw > 20 && yaw < 40) {
      return FacePose.right;
    } else if (pitch < -10 && pitch > -30) {
      return FacePose.up;
    } else if (pitch > 8 && pitch < 25) {
      return FacePose.down;
    }

    return null; // Pose not clear enough
  }

  Future<void> _attemptCapture(
    FacePose pose,
    CameraImage cameraImage,
    Face face,
  ) async {
    // Check debounce
    if (_lastCaptureTime != null &&
        DateTime.now().difference(_lastCaptureTime!) < _captureDebounceTime) {
      return;
    }

    try {
      final rotation = _getInputImageRotation();

      // Crop face directly from YUV using the service (handles rotation correctly)
      final faceImage = _faceRecognitionService.cropFaceFromYUV(
        cameraImage,
        face,
        rotation,
      );

      if (faceImage == null) return;

      // Extract embedding from the cropped image
      final embedding = await _faceRecognitionService
          .getEmbeddingFromCroppedImage(faceImage);

      if (embedding == null) return;

      // Save image to temp file
      final tempDir = await getTemporaryDirectory();
      final fileName = '${widget.personName}_${pose.name}.jpg';
      final file = File('${tempDir.path}/$fileName');

      final jpg = img.encodeJpg(faceImage);
      await file.writeAsBytes(jpg);

      // Store captured data
      setState(() {
        _capturedImages[pose] = file;
        _capturedEmbeddings[pose] = embedding;
        _lastCaptureTime = DateTime.now();
      });

      print('DEBUG: Captured ${pose.name} pose');
    } catch (e) {
      print('Error capturing pose: $e');
    }
  }

  void _submitEnrollment() {
    if (_capturedEmbeddings.length < 5) {
      Helpers.showSnackBar(
        context,
        'Please capture all 5 poses',
        isError: true,
      );
      return;
    }

    // Return captured data to previous screen
    Navigator.of(context).pop({
      'images': _capturedImages.values.toList(),
      'embeddings': _capturedEmbeddings.values.toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isInitialized ? _buildCameraView() : _buildLoadingView(),
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text(
            'Initializing camera...',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraView() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final size = MediaQuery.of(context).size;
    final deviceRatio = size.width / size.height;
    final cameraRatio = _cameraController!.value.aspectRatio;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        Transform.scale(
          scale: () {
            var scale = 1.0;
            if (size.height > size.width) {
              scale = deviceRatio * cameraRatio;
            } else {
              scale = deviceRatio / cameraRatio;
            }
            if (scale < 1) scale = 1 / scale;
            return scale;
          }(),
          child: Center(child: CameraPreview(_cameraController!)),
        ),

        // Top instructions
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                // Close button
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    Text(
                      '${_capturedEmbeddings.length}/5',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Instructions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getInstructionText(),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),

                const Spacer(),

                // Progress indicators
                _buildProgressIndicators(),

                const SizedBox(height: 32),

                // Submit button
                if (_capturedEmbeddings.length == 5)
                  ElevatedButton(
                    onPressed: _submitEnrollment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(56),
                    ),
                    child: const Text('Complete Enrollment'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressIndicators() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: FacePose.values.map((pose) {
        final isCaptured = _capturedEmbeddings.containsKey(pose);
        final isActive = _currentPose == pose;

        return Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isCaptured
                    ? AppColors.primary
                    : (isActive ? Colors.yellow : Colors.grey),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: isActive ? 3 : 1,
                ),
              ),
              child: Icon(
                isCaptured ? Icons.check : _getPoseIcon(pose),
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _getPoseName(pose),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        );
      }).toList(),
    );
  }

  IconData _getPoseIcon(FacePose pose) {
    switch (pose) {
      case FacePose.center:
        return Icons.circle;
      case FacePose.left:
        return Icons.arrow_back;
      case FacePose.right:
        return Icons.arrow_forward;
      case FacePose.up:
        return Icons.arrow_upward;
      case FacePose.down:
        return Icons.arrow_downward;
    }
  }

  String _getPoseName(FacePose pose) {
    switch (pose) {
      case FacePose.center:
        return 'Center';
      case FacePose.left:
        return 'Left';
      case FacePose.right:
        return 'Right';
      case FacePose.up:
        return 'Up';
      case FacePose.down:
        return 'Down';
    }
  }

  String _getInstructionText() {
    if (_capturedEmbeddings.isEmpty) {
      return 'Look straight at the camera';
    }

    final remaining = FacePose.values
        .where((p) => !_capturedEmbeddings.containsKey(p))
        .toList();

    if (remaining.isEmpty) {
      return 'All poses captured! Tap Complete';
    }

    final next = remaining.first;
    switch (next) {
      case FacePose.center:
        return 'Look straight at the camera';
      case FacePose.left:
        return 'Turn your head to the left';
      case FacePose.right:
        return 'Turn your head to the right';
      case FacePose.up:
        return 'Tilt your head up slightly';
      case FacePose.down:
        return 'Tilt your head down slightly';
    }
  }
}
