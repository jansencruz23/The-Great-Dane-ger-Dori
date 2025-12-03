import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

import '../../main.dart' show cameras;
import '../../providers/user_provider.dart';
import '../../services/face_recognition_service.dart';
import '../../services/database_service.dart';
import '../../services/speech_service.dart';
import '../../services/summarization_service.dart';
import '../../models/known_face_model.dart';
import '../../models/activity_log_model.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../widgets/ar_overlay_widget.dart';
import '../../widgets/face_detection_painter.dart';

class FaceRecognitionScreen extends StatefulWidget {
  const FaceRecognitionScreen({super.key});

  @override
  State<FaceRecognitionScreen> createState() => _FaceRecognitionScreenState();
}

class _FaceRecognitionScreenState extends State<FaceRecognitionScreen> {
  CameraController? _cameraController;
  final FaceRecognitionService _faceRecognitionService =
      FaceRecognitionService();
  final DatabaseService _databaseService = DatabaseService();
  final SpeechService _speechService = SpeechService();
  final SummarizationService _summarizationService = SummarizationService();

  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isRecording = false;

  List<KnownFaceModel> _knownFaces = [];
  Map<Face, KnownFaceModel?> _detectedFaces = {};
  KnownFaceModel? _activeRecognition;
  String _transcription = '';
  DateTime? _interactionStartTime;
  bool _isStreamActive = false;

  Timer? _processingTimer;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void dispose() {
    _processingTimer?.cancel();
    if (_isStreamActive && _cameraController != null) {
      _cameraController!.stopImageStream();
    }
    _cameraController?.dispose();
    _faceRecognitionService.dispose();
    _speechService.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    // Request permissions
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();
    final speechStatus = await Permission.speech.request();

    if (!cameraStatus.isGranted) {
      if (mounted) {
        Helpers.showSnackBar(
          context,
          'Camera permission is required',
          isError: true,
        );
      }
      return;
    }

    if (!micStatus.isGranted || !speechStatus.isGranted) {
      if (mounted) {
        Helpers.showSnackBar(
          context,
          'Microphone permission is required for transcription',
          isError: true,
        );
      }
    }

    try {
      // Initialize services
      await _faceRecognitionService.initialize();
      await _speechService.initialize();

      // Load known faces
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      _knownFaces = await _databaseService.getKnownFaces(
        userProvider.currentUser!.uid,
      );
      _faceRecognitionService.updateKnownFaces(_knownFaces);

      // Initialize camera
      if (cameras.isEmpty) {
        throw 'No camera available';
      }

      _cameraController = CameraController(
        cameras[0],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() => _isInitialized = true);

        // Start processing frames
        _startFrameProcessing();
      }
    } catch (e) {
      if (mounted) {
        Helpers.showSnackBar(
          context,
          'Initialization failed: $e',
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
        // Process the camera frame
        final results = await _faceRecognitionService.processCameraFrame(
          cameraImage,
        );

        print('DEBUG: Detected ${results.length} faces');
        for (var entry in results.entries) {
          print(
            'DEBUG: Face - Recognized as: ${entry.value?.name ?? "Unknown"}',
          );
        }

        if (mounted) {
          setState(() {
            _detectedFaces = results;
          });

          // Handle face recognition
          await _handleFaceRecognition(results);
        }
      } catch (e) {
        print('Error processing frame: $e');
      } finally {
        // Add delay to throttle processing (process ~2 frames per second)
        await Future.delayed(const Duration(milliseconds: 500));
        _isProcessing = false;
      }
    });
  }

  Future<void> _handleFaceRecognition(
    Map<Face, KnownFaceModel?> results,
  ) async {
    final recognizedFaces = results.values
        .where((face) => face != null)
        .toList();

    if (recognizedFaces.isEmpty) {
      if (_isRecording) {
        await _stopRecording();
      }
      return;
    }

    final recognizedFace = recognizedFaces.first;

    // Start recording if not already recording
    if (!_isRecording || _activeRecognition?.id != recognizedFace?.id) {
      if (_isRecording) {
        await _stopRecording();
      }
      await _startRecording(recognizedFace!);
    }
  }

  Future<void> _startRecording(KnownFaceModel face) async {
    setState(() {
      _activeRecognition = face;
      _isRecording = true;
      _transcription = '';
      _interactionStartTime = DateTime.now();
    });

    // Update last seen
    await _databaseService.updateFaceLastSeen(face.id);

    // Start speech recognition
    try {
      await _speechService.startListening(
        onResult: (text) {
          setState(() {
            _transcription = text;
          });
        },
      );
    } catch (e) {
      print('Error starting speech recognition: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording || _activeRecognition == null) return;

    try {
      // Stop speech recognition
      final finalTranscript = await _speechService.stopListening();

      if (finalTranscript.isNotEmpty && _interactionStartTime != null) {
        // Generate summary
        final summary = await _summarizationService.generateSummary(
          transcript: finalTranscript,
          personName: _activeRecognition!.name,
          relationship: _activeRecognition!.relationship,
        );

        // Save activity log
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        final log = ActivityLogModel(
          id: '',
          patientId: userProvider.currentUser!.uid,
          personId: _activeRecognition!.id,
          personName: _activeRecognition!.name,
          timestamp: _interactionStartTime!,
          rawTranscript: finalTranscript,
          summary: summary,
          duration: DateTime.now().difference(_interactionStartTime!),
        );

        await _databaseService.createActivityLog(log);
      }
    } catch (e) {
      print('Error stopping recording: $e');
    } finally {
      setState(() {
        _isRecording = false;
        _activeRecognition = null;
        _transcription = '';
        _interactionStartTime = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isInitialized
          ? _buildCameraView()
          : const Center(
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
          scale: deviceRatio / cameraRatio,
          child: Center(child: CameraPreview(_cameraController!)),
        ),

        // Face detection overlay
        if (_detectedFaces.isNotEmpty)
          CustomPaint(
            painter: FaceDetectionPainter(
              faces: _detectedFaces.keys.toList(),
              imageSize: Size(
                _cameraController!.value.previewSize!.height,
                _cameraController!.value.previewSize!.width,
              ),
            ),
          ),

        // AR overlays for recognized faces
        ..._detectedFaces.entries.map((entry) {
          if (entry.value != null) {
            return ArOverlayWidget(
              face: entry.key,
              knownFace: entry.value!,
              imageSize: Size(
                _cameraController!.value.previewSize!.height,
                _cameraController!.value.previewSize!.width,
              ),
            );
          }
          return const SizedBox.shrink();
        }),

        // Top controls
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Back button and status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    if (_isRecording)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.fiber_manual_record,
                              color: Colors.white,
                              size: 16,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Recording',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),

                const Spacer(),

                // Transcription display
                if (_isRecording && _transcription.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Conversation:',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _transcription,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                // Status message
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Text(
                    _detectedFaces.isEmpty
                        ? 'Looking for faces...'
                        : '${_detectedFaces.length} face(s) detected',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
