import 'dart:async';
import 'dart:io';
import 'package:dori/services/face_recognition_service.dart';
import 'package:dori/services/speech_service.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
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
  Face? _detectedFace;

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
        // Detect faces
        final faces = await _faceRecognitionService.detectFaces(cameraImage);

        if (faces.isNotEmpty && mounted) {
          final face = faces.first;

          // Detect pose
          final pose = _detectPose(face);

          setState(() {
            _detectedFace = face;
            _currentPose = pose;
          });

          // Auto-capture if pose is valid and not recently captured
          if (pose != null && !_capturedEmbeddings.containsKey(pose)) {
            await _attemptCapture(pose, cameraImage, face);
          }
        } else {
          setState(() {
            _detectedFace = null;
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
      // Convert camera image to img.Image
      final image = _convertToImage(cameraImage);
      if (image == null) return;

      // Extract embedding
      final embedding = await _faceRecognitionService.extractFaceEmbedding(
        image,
        face,
      );

      if (embedding == null) return;

      // Save image to temp file
      final tempDir = await getTemporaryDirectory();
      final fileName = '${widget.personName}_${pose.name}.jpg';
      final file = File('${tempDir.path}/$fileName');

      final jpg = img.encodeJpg(image);
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

  img.Image? _convertToImage(CameraImage cameraImage) {
    try {
      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        return _convertYUV420(cameraImage);
      } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        return _convertBGRA8888(cameraImage);
      }
      return null;
    } catch (e) {
      print('Error converting camera image: $e');
      return null;
    }
  }

  img.Image _convertYUV420(CameraImage image) {
    final width = image.width;
    final height = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final imgImage = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final yIndex = y * yPlane.bytesPerRow + x;
        final uvIndex = (y ~/ 2) * uPlane.bytesPerRow + (x ~/ 2);

        final yValue = yPlane.bytes[yIndex];
        final uValue = uPlane.bytes[uvIndex];
        final vValue = vPlane.bytes[uvIndex];

        final r = (yValue + 1.370705 * (vValue - 128)).clamp(0, 255).toInt();
        final g =
            (yValue - 0.337633 * (uValue - 128) - 0.698001 * (vValue - 128))
                .clamp(0, 255)
                .toInt();
        final b = (yValue + 1.732446 * (uValue - 128)).clamp(0, 255).toInt();

        imgImage.setPixelRgba(x, y, r, g, b, 255);
      }
    }

    return imgImage;
  }

  img.Image _convertBGRA8888(CameraImage image) {
    return img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: image.planes[0].bytes.buffer,
      order: img.ChannelOrder.bgra,
    );
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

        // Pose guide overlay
        _buildPoseGuideOverlay(),

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

  Widget _buildPoseGuideOverlay() {
    if (_detectedFace == null) return const SizedBox();

    // Draw a circle guide for the face
    return CustomPaint(
      painter: _FaceGuidePainter(
        detectedFace: _detectedFace!,
        currentPose: _currentPose,
      ),
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

class _FaceGuidePainter extends CustomPainter {
  final Face detectedFace;
  final FacePose? currentPose;

  _FaceGuidePainter({required this.detectedFace, this.currentPose});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = currentPose != null ? Colors.greenAccent : Colors.white;

    // Draw oval guide
    final rect = detectedFace.boundingBox;
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.6,
      height: size.height * 0.7,
    );

    canvas.drawOval(ovalRect, paint);
  }

  @override
  bool shouldRepaint(_FaceGuidePainter oldDelegate) {
    return oldDelegate.currentPose != currentPose;
  }
}
