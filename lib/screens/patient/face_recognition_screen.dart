import 'dart:async';
import 'dart:io';
import 'package:dori/services/database_service.dart';
import 'package:dori/services/speech_service.dart';
import 'package:dori/services/summarization_service.dart';
import 'package:dori/widgets/ar_overlay_widget.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../main.dart' show cameras;
import '../../providers/user_provider.dart';
import '../../services/face_recognition_service.dart';
import '../../models/known_face_model.dart';
import '../../models/activity_log_model.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../widgets/face_detection_painter.dart';
import '../../widgets/day_by_day_summary_widget.dart';


enum FacePose { center, left, right, up, down }

enum EnrollmentMode {
  normal,
  prompting,
  collectingName,
  collectingRelationship,
  capturingAngles,
  saving,
}

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
  Map<String, List<ActivityLogModel>> _faceActivityLogs =
      {}; // personId -> recent logs
  KnownFaceModel? _activeRecognition;
  String _transcription = '';
  DateTime? _interactionStartTime;
  bool _isStreamActive = false;

  Timer? _processingTimer;

  // Enrollment mode state
  EnrollmentMode _enrollmentMode = EnrollmentMode.normal;

  // Unknown face tracking
  Face? _unknownFace;
  List<double>? _unknownFaceEmbedding;
  DateTime? _unknownFaceFirstSeen;
  static const _unknownFaceDebounceTime = Duration(seconds: 3);

  // Enrollment data
  String _enrollmentName = '';
  String _enrollmentRelationship = '';
  Map<FacePose, File> _enrollmentImages = {};
  Map<FacePose, List<double>> _enrollmentEmbeddings = {};
  FacePose? _currentEnrollmentPose;
  DateTime? _lastEnrollmentCapture;

  // Voice input state
  bool _isListeningForName = false;
  bool _isListeningForRelationship = false;
  String _voiceInputBuffer = '';

  // Day-by-day summary state
  bool _showDayByDaySummary = false;
  String _dayByDaySummary = '';
  bool _isLoadingSummary = false;


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
      final patientId = userProvider.currentUser!.uid;
      print('DEBUG: Loading known faces for patient ID: $patientId');

      _knownFaces = await _databaseService.getKnownFaces(patientId);
      print('DEBUG: Loaded ${_knownFaces.length} known faces');

      for (final face in _knownFaces) {
        print(
          'DEBUG: - ${face.name} (${face.getAllEmbeddings().length} embeddings)',
        );
      }

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
        // Handle enrollment mode - capture poses
        if (_enrollmentMode == EnrollmentMode.capturingAngles) {
          final faces = await _faceRecognitionService.detectFaces(cameraImage);

          if (faces.isNotEmpty && mounted) {
            final face = faces.first;
            final pose = _detectPose(face);

            setState(() => _currentEnrollmentPose = pose);

            // Auto-capture if pose is valid and not yet captured
            if (pose != null && !_enrollmentEmbeddings.containsKey(pose)) {
              await _attemptEnrollmentCapture(pose, cameraImage, face);
            }
          }
        }
        // Normal recognition mode
        else if (_enrollmentMode == EnrollmentMode.normal) {
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
        }
      } catch (e) {
        print('Error processing frame: $e');
      } finally {
        // Add delay to throttle processing (process ~10 frames per second)
        await Future.delayed(const Duration(milliseconds: 100));
        _isProcessing = false;
      }
    });
  }

  Future<void> _handleFaceRecognition(
    Map<Face, KnownFaceModel?> results,
  ) async {
    // Skip if in enrollment mode
    if (_enrollmentMode != EnrollmentMode.normal) {
      return;
    }

    final recognizedFaces = results.values
        .where((face) => face != null)
        .toList();

    // Handle recognized faces
    if (recognizedFaces.isNotEmpty) {
      final recognizedFace = recognizedFaces.first;

      // Clear unknown face tracking since we recognized someone
      _unknownFace = null;
      _unknownFaceEmbedding = null;
      _unknownFaceFirstSeen = null;

      // Fetch activity logs for this person if not already cached
      if (!_faceActivityLogs.containsKey(recognizedFace?.id)) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        final logs = await _databaseService.getPersonActivityLogs(
          userProvider.currentUser!.uid,
          recognizedFace!.id,
          limit: 1, // Only fetch 1 previous summary
        );
        setState(() {
          _faceActivityLogs[recognizedFace.id] = logs;
        });
      }

      // Start recording if not already recording
      if (!_isRecording || _activeRecognition?.id != recognizedFace?.id) {
        if (_isRecording) {
          await _stopRecording();
        }
        await _startRecording(recognizedFace!);
      }
      return;
    }

    // Handle unknown faces
    final unknownFaceEntry = results.entries
        .where((entry) => entry.value == null)
        .firstOrNull;

    if (unknownFaceEntry != null) {
      final now = DateTime.now();

      // If this is a new unknown face, start tracking
      if (_unknownFace == null || _unknownFaceFirstSeen == null) {
        _unknownFace = unknownFaceEntry.key;
        _unknownFaceFirstSeen = now;
        _unknownFaceEmbedding = null; // Will extract in next frame
        print('DEBUG: Started tracking unknown face');
      }
      // If same unknown face has been present for debounce time, prompt enrollment
      else if (now.difference(_unknownFaceFirstSeen!) >=
          _unknownFaceDebounceTime) {
        print(
          'DEBUG: Unknown face persisted for ${_unknownFaceDebounceTime.inSeconds}s, prompting enrollment',
        );
        await _promptEnrollment(unknownFaceEntry.key);
      }
    } else {
      // No faces detected, clear unknown face tracking
      _unknownFace = null;
      _unknownFaceEmbedding = null;
      _unknownFaceFirstSeen = null;

      if (_isRecording) {
        await _stopRecording();
      }
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
      String finalTranscript = '';
      try {
        // Stop speech recognition
        finalTranscript = await _speechService.stopListening();
      } catch (e) {
        print('Warning: Error stopping speech recognition: $e');
        // Continue to save log even if speech service fails
      }

      if (_interactionStartTime != null) {
        // Generate summary (service handles empty transcripts)
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

        print('DEBUG: Creating activity log for ${log.personName}');
        await _databaseService.createActivityLog(log);
        print('DEBUG: Activity log created successfully');
        
        // Refresh the day-by-day summary if it's visible
        if (_showDayByDaySummary) {
          _loadDayByDaySummary();
        }
      }
    } catch (e) {
      print('Error saving activity log: $e');
    } finally {
      setState(() {
        _isRecording = false;
        _activeRecognition = null;
        _transcription = '';
        _interactionStartTime = null;
      });
    }
  }

  // ==================== ENROLLMENT WORKFLOW ====================

  Future<void> _promptEnrollment(Face face) async {
    _unknownFace = null;
    _unknownFaceFirstSeen = null;

    setState(() => _enrollmentMode = EnrollmentMode.prompting);

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Unknown Face Detected'),
        content: const Text('Would you like to add this person?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, Add'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => _enrollmentMode = EnrollmentMode.collectingName);
    } else {
      setState(() => _enrollmentMode = EnrollmentMode.normal);
    }
  }

  Future<void> _collectNameInput(String name) async {
    if (name.trim().isEmpty) return;
    _enrollmentName = name.trim();
    setState(() => _enrollmentMode = EnrollmentMode.collectingRelationship);
  }

  Future<void> _collectRelationshipInput(String relationship) async {
    if (relationship.trim().isEmpty) return;
    _enrollmentRelationship = relationship.trim();
    setState(() => _enrollmentMode = EnrollmentMode.capturingAngles);
  }

  void _cancelEnrollment() {
    setState(() {
      _enrollmentMode = EnrollmentMode.normal;
      _enrollmentImages.clear();
      _enrollmentEmbeddings.clear();
      _enrollmentName = '';
      _enrollmentRelationship = '';
    });
  }

  Future<void> _saveEnrollment() async {
    setState(() => _enrollmentMode = EnrollmentMode.saving);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);

      final newFace = KnownFaceModel(
        id: '',
        patientId: userProvider.currentUser!.uid,
        name: _enrollmentName,
        relationship: _enrollmentRelationship,
        imageUrls: [],
        embeddings: _enrollmentEmbeddings.values.toList(),
        createdAt: DateTime.now(),
        lastSeenAt: null,
        interactionCount: 0,
      );

      await _databaseService.addKnownFace(
        newFace,
        imageFiles: _enrollmentImages.values.toList(),
      );

      _knownFaces = await _databaseService.getKnownFaces(
        userProvider.currentUser!.uid,
      );
      print(
        'DEBUG: Reloaded ${_knownFaces.length} known faces after enrollment',
      );
      _faceRecognitionService.updateKnownFaces(_knownFaces);

      if (mounted) {
        Helpers.showSnackBar(context, 'Successfully added $_enrollmentName!');
        setState(() {
          _enrollmentMode = EnrollmentMode.normal;
          _enrollmentImages.clear();
          _enrollmentEmbeddings.clear();
        });
      }
    } catch (e) {
      print('Error saving enrollment: $e');
      if (mounted) {
        Helpers.showSnackBar(context, 'Failed to save: $e', isError: true);
        setState(() => _enrollmentMode = EnrollmentMode.normal);
      }
    }
  }

  // Voice input helpers
  Future<void> _startVoiceInput(bool isForName) async {
    setState(() {
      if (isForName) {
        _isListeningForName = true;
      } else {
        _isListeningForRelationship = true;
      }
      _voiceInputBuffer = '';
    });

    try {
      await _speechService.startListening(
        onResult: (text) {
          setState(() => _voiceInputBuffer = text);
        },
      );
    } catch (e) {
      print('Error starting voice input: $e');
    }
  }

  Future<void> _stopVoiceInput(bool isForName) async {
    try {
      final result = await _speechService.stopListening();

      if (result.isNotEmpty) {
        if (isForName) {
          await _collectNameInput(result);
        } else {
          await _collectRelationshipInput(result);
        }
      }
    } catch (e) {
      print('Error stopping voice input: $e');
    } finally {
      setState(() {
        _isListeningForName = false;
        _isListeningForRelationship = false;
        _voiceInputBuffer = '';
      });
    }
  }

  // Pose detection
  FacePose? _detectPose(Face face) {
    final yaw = face.headEulerAngleY ?? 0;
    final pitch = face.headEulerAngleX ?? 0;

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
    return null;
  }

  // Image conversion helpers
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

  // Enrollment capture
  Future<void> _attemptEnrollmentCapture(
    FacePose pose,
    CameraImage cameraImage,
    Face face,
  ) async {
    if (_lastEnrollmentCapture != null &&
        DateTime.now().difference(_lastEnrollmentCapture!) <
            const Duration(seconds: 2)) {
      return;
    }

    try {
      final image = _convertToImage(cameraImage);
      if (image == null) return;

      final embedding = await _faceRecognitionService.extractFaceEmbedding(
        image,
        face,
      );
      if (embedding == null) return;

      final tempDir = await getTemporaryDirectory();
      final fileName = '${_enrollmentName}_${pose.name}.jpg';
      final file = File('${tempDir.path}/$fileName');
      final jpg = img.encodeJpg(image);
      await file.writeAsBytes(jpg);

      setState(() {
        _enrollmentImages[pose] = file;
        _enrollmentEmbeddings[pose] = embedding;
        _lastEnrollmentCapture = DateTime.now();
      });

      print(
        'DEBUG: Captured ${pose.name} for enrollment (${_enrollmentEmbeddings.length}/5)',
      );

      if (_enrollmentEmbeddings.length == 5) {
        await _saveEnrollment();
      }
    } catch (e) {
      print('Error capturing enrollment: $e');
    }
  }

  // ==================== DAY-BY-DAY SUMMARY ====================

  Future<void> _toggleDayByDaySummary() async {
    setState(() {
      _showDayByDaySummary = !_showDayByDaySummary;
    });

    // Load summary if showing and not already loaded
    if (_showDayByDaySummary && _dayByDaySummary.isEmpty) {
      await _loadDayByDaySummary();
    }
  }

  Future<void> _loadDayByDaySummary() async {
    setState(() {
      _isLoadingSummary = true;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final patientId = userProvider.currentUser!.uid;

      // Fetch activity logs grouped by date (last 7 days)
      final logsByDate = await _databaseService.getActivityLogsByDate(
        patientId,
        daysBack: 7,
      );

      // Generate summary using Gemini
      final summary = await _summarizationService.generateDayByDaySummary(
        logsByDate,
      );

      if (mounted) {
        setState(() {
          _dayByDaySummary = summary;
          _isLoadingSummary = false;
        });
      }
    } catch (e) {
      print('Error loading day-by-day summary: $e');
      if (mounted) {
        setState(() {
          _dayByDaySummary =
              'Unable to load summary at this time. Please try again later.';
          _isLoadingSummary = false;
        });
      }
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
              recentLogs: _faceActivityLogs[entry.value!.id] ?? [],
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
                    // Day-by-day summary toggle button (centered)
                    Expanded(
                      child: Center(
                        child: GestureDetector(
                          onTap: _toggleDayByDaySummary,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: _showDayByDaySummary
                                    ? [
                                        Colors.white.withValues(alpha: 0.3),
                                        Colors.white.withValues(alpha: 0.2),
                                      ]
                                    : [
                                        Colors.black.withValues(alpha: 0.5),
                                        Colors.black.withValues(alpha: 0.3),
                                      ],
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.4),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Icon(
                              _showDayByDaySummary
                                  ? Icons.close_rounded
                                  : Icons.calendar_today_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
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
                      )
                    else
                      const SizedBox(width: 48), // Spacer for alignment
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

        // Day-by-day summary widget
        if (_showDayByDaySummary)
          DayByDaySummaryWidget(
            summary: _dayByDaySummary,
            isLoading: _isLoadingSummary,
            onRefresh: _loadDayByDaySummary,
          ),

        // Enrollment UI Overlays
        if (_enrollmentMode == EnrollmentMode.collectingName)
          _buildNameInputOverlay(),
        if (_enrollmentMode == EnrollmentMode.collectingRelationship)
          _buildRelationshipInputOverlay(),
        if (_enrollmentMode == EnrollmentMode.capturingAngles)
          _buildEnrollmentCaptureOverlay(),
        if (_enrollmentMode == EnrollmentMode.saving) _buildSavingOverlay(),
      ],
    );
  }

  Widget _buildNameInputOverlay() {
    final nameController = TextEditingController();
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      child: SafeArea(
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Enter Person\'s Name',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isListeningForName
                              ? () => _stopVoiceInput(true)
                              : () => _startVoiceInput(true),
                          icon: Icon(
                            _isListeningForName ? Icons.stop : Icons.mic,
                          ),
                          label: Text(
                            _isListeningForName
                                ? _voiceInputBuffer.isEmpty
                                      ? 'Listening...'
                                      : _voiceInputBuffer
                                : 'Voice Input',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: _cancelEnrollment,
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => _collectNameInput(nameController.text),
                        child: const Text('Next'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRelationshipInputOverlay() {
    final relationshipController = TextEditingController();
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      child: SafeArea(
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Relationship',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: relationshipController,
                    decoration: const InputDecoration(
                      labelText: 'e.g., Friend, Family',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isListeningForRelationship
                              ? () => _stopVoiceInput(false)
                              : () => _startVoiceInput(false),
                          icon: Icon(
                            _isListeningForRelationship
                                ? Icons.stop
                                : Icons.mic,
                          ),
                          label: Text(
                            _isListeningForRelationship
                                ? _voiceInputBuffer.isEmpty
                                      ? 'Listening...'
                                      : _voiceInputBuffer
                                : 'Voice Input',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: _cancelEnrollment,
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => _collectRelationshipInput(
                          relationshipController.text,
                        ),
                        child: const Text('Start Capture'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEnrollmentCaptureOverlay() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    'Enrolling: $_enrollmentName',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_enrollmentEmbeddings.length}/5 poses captured',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: FacePose.values.map((pose) {
                final captured = _enrollmentEmbeddings.containsKey(pose);
                final active = _currentEnrollmentPose == pose;
                return Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: captured
                            ? AppColors.accent
                            : (active ? Colors.yellow : Colors.grey),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: active ? 3 : 1,
                        ),
                      ),
                      child: Icon(
                        captured ? Icons.check : Icons.circle,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pose.name.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _cancelEnrollment,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white),
              ),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Saving enrollment...',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}
