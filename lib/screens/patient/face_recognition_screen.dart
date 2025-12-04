import 'dart:ui' as ui;
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dori/services/database_service.dart';
import 'package:dori/services/speech_service.dart';
import 'package:dori/services/summarization_service.dart';
import 'package:dori/widgets/ar_overlay_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

import '../../main.dart' show cameras;
import '../../providers/user_provider.dart';
import '../../services/face_recognition_service.dart';
import '../../models/known_face_model.dart';
import '../../models/activity_log_model.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';

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
  Timer? _clockTimer;
  String _currentTime = '';

  // Enrollment mode state
  EnrollmentMode _enrollmentMode = EnrollmentMode.normal;
  bool _isSavingMinimized = false;

  // Unknown face tracking
  Face? _unknownFace;
  List<double>? _unknownFaceEmbedding;
  DateTime? _unknownFaceFirstSeen;
  static const _unknownFaceDebounceTime = Duration(seconds: 3);

  // Recognition persistence (to prevent flickering on jitter)
  DateTime? _lastRecognitionTime;
  KnownFaceModel? _lastRecognizedFace;
  Face? _lastDetectedFace; // Store the actual Face object
  static const _recognitionPersistenceDuration = Duration(seconds: 2);

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

  // Floating action menu state
  bool _isMenuExpanded = false;

  // Text Controllers
  late TextEditingController _nameController;
  late TextEditingController _relationshipController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _relationshipController = TextEditingController();
    _updateTime();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateTime();
    });
    _initializeApp();
  }

  void _updateTime() {
    if (mounted) {
      setState(() {
        _currentTime = DateFormat('h:mm a').format(DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _processingTimer?.cancel();
    _clockTimer?.cancel();
    _nameController.dispose();
    _relationshipController.dispose();
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
        final rotation = _getInputImageRotation();

        // Handle enrollment mode - capture poses
        if (_enrollmentMode == EnrollmentMode.capturingAngles) {
          final faces = await _faceRecognitionService.detectFaces(
            cameraImage,
            rotation,
          );

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
            rotation,
          );

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
        // Add delay to throttle processing (reduced to 2fps for maximum smoothness)
        await Future.delayed(const Duration(milliseconds: 500));
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

    final now = DateTime.now();

    // Handle recognized faces
    if (recognizedFaces.isNotEmpty) {
      final recognizedFace = recognizedFaces.first;

      // Find the Face key corresponding to this recognition
      final faceEntry = results.entries.firstWhere(
        (entry) => entry.value == recognizedFace,
      );

      // Update last recognition time, face, and Face object
      _lastRecognitionTime = now;
      _lastRecognizedFace = recognizedFace;
      _lastDetectedFace = faceEntry.key; // Store the actual Face object

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

    // No recognized faces - check if we should persist previous recognition
    if (_lastRecognitionTime != null &&
        _lastRecognizedFace != null &&
        _lastDetectedFace != null &&
        now.difference(_lastRecognitionTime!) <
            _recognitionPersistenceDuration) {
      // Keep displaying the last recognized face for a bit longer
      // This prevents flickering when detection temporarily fails
      print(
        'DEBUG: Persisting recognition for ${_lastRecognizedFace!.name} despite temporary detection loss',
      );

      // Keep the recognized face in detected faces to maintain display
      if (_detectedFaces.isEmpty ||
          !_detectedFaces.containsValue(_lastRecognizedFace)) {
        setState(() {
          // Reuse the last detected Face object to keep the overlay visible
          _detectedFaces = {_lastDetectedFace!: _lastRecognizedFace};
        });
      }
      return;
    }

    // Recognition persistence expired, clear it
    if (_lastRecognitionTime != null) {
      _lastRecognitionTime = null;
      _lastRecognizedFace = null;
      _lastDetectedFace = null;
      print('DEBUG: Recognition persistence expired');
    }

    // Handle unknown faces
    if (_enrollmentMode != EnrollmentMode.normal) return;

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
      // No faces detected at all, clear unknown face tracking
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
    _nameController.clear();
    _relationshipController.clear();
    _unknownFace = null;
    _unknownFaceFirstSeen = null;

    setState(() => _enrollmentMode = EnrollmentMode.prompting);

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withOpacity(0.85),
                    AppColors.secondary.withOpacity(0.5),
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_add,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Title
                  const Text(
                    'Unknown Face Detected',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          offset: Offset(0, 1),
                          blurRadius: 2,
                          color: Colors.black26,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  // Content
                  const Text(
                    'Would you like to add this person?',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Not Now'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Yes, Add',
                            style: TextStyle(fontWeight: FontWeight.bold),
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
    setState(() {
      _enrollmentMode = EnrollmentMode.saving;
      _isSavingMinimized = true; // Start minimized immediately
    });

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

      print('\n\n');
      print('🔍🔍🔍 FETCHING ALL SUMMARIES 🔍🔍🔍');
      print('═══════════════════════════════════════════════════════');
      print('PATIENT ID: $patientId');
      print('═══════════════════════════════════════════════════════\n');

      // Fetch ALL summaries for this patient (simple query, no complex filtering)
      final summaries = await _databaseService.getAllSummariesForPatient(
        patientId,
      );

      print('\n📊 TOTAL SUMMARIES FOUND: ${summaries.length}');
      print('═══════════════════════════════════════════════════════\n');

      if (summaries.isEmpty) {
        print('⚠️  NO SUMMARIES FOUND FOR THIS PATIENT!');
        print('   Patient ID: $patientId');
        print('   Check if activity logs exist in Firebase');
        print('═══════════════════════════════════════════════════════\n');

        if (mounted) {
          setState(() {
            _dayByDaySummary =
                'No activities recorded yet. Your daily summaries will appear here.';
            _isLoadingSummary = false;
          });
        }
        return;
      }

      // Print all summaries
      print('📋 ALL SUMMARY VALUES:');
      print('─────────────────────────────────────────────────────');
      for (var i = 0; i < summaries.length; i++) {
        final summary = summaries[i];
        print('\n${i + 1}. ${summary['personName']} (${summary['timestamp']})');
        print('   Summary: ${summary['summary']}');
        print('   Transcript: ${summary['rawTranscript'] ?? '(none)'}');
      }
      print('\n═══════════════════════════════════════════════════════\n');

      // Group summaries by date for Gemini
      final Map<String, List<Map<String, dynamic>>> summariesByDate = {};
      for (var summary in summaries) {
        final timestamp = summary['timestamp'] as Timestamp;
        final date = timestamp.toDate();
        final dateKey =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

        if (!summariesByDate.containsKey(dateKey)) {
          summariesByDate[dateKey] = [];
        }
        summariesByDate[dateKey]!.add(summary);
      }

      print('📅 GROUPED BY DATE: ${summariesByDate.length} days');
      for (var entry in summariesByDate.entries) {
        print('  ${entry.key}: ${entry.value.length} activities');
      }
      print('\n');

      // Send to Gemini for narrative summary
      print('🤖 SENDING TO GEMINI FOR NARRATIVE SUMMARY...\n');

      final geminiSummary = await _generateGeminiNarrative(summariesByDate);

      print('✅ RECEIVED FROM GEMINI:');
      print('┌─────────────────────────────────────────────────────┐');
      print(geminiSummary);
      print('└─────────────────────────────────────────────────────┘\n');

      if (mounted) {
        setState(() {
          _dayByDaySummary = geminiSummary;
          _isLoadingSummary = false;
        });
      }
    } catch (e) {
      print('❌ ERROR: $e');
      if (mounted) {
        setState(() {
          _dayByDaySummary = 'Error loading summaries: $e';
          _isLoadingSummary = false;
        });
      }
    }
  }

  Future<String> _generateGeminiNarrative(
    Map<String, List<Map<String, dynamic>>> summariesByDate,
  ) async {
    try {
      // Build prompt for Gemini
      final buffer = StringBuffer();
      buffer.writeln(
        'You are a warm, empathetic storyteller helping someone with memory challenges.',
      );
      buffer.writeln(
        'Create a detailed day-by-day summary of their recent activities.',
      );
      buffer.writeln('Be descriptive but concise.\n');

      // Sort dates (most recent first)
      final sortedDates = summariesByDate.keys.toList()
        ..sort((a, b) => b.compareTo(a));

      buffer.writeln('Here are the activities:');
      buffer.writeln();

      for (var dateStr in sortedDates) {
        final activities = summariesByDate[dateStr]!;
        final date = DateTime.parse(dateStr);
        final dayName = _getDayName(date);

        buffer.writeln('$dayName ($dateStr):');
        for (var activity in activities) {
          final timestamp = (activity['timestamp'] as Timestamp).toDate();
          final time =
              '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
          buffer.writeln(
            '  - $time with ${activity['personName']}: ${activity['summary']}',
          );
        }
        buffer.writeln();
      }

      buffer.writeln('Instructions:');
      buffer.writeln('- Write 3-4 sentences for each day');
      buffer.writeln('- Use warm, conversational language');
      buffer.writeln('- Include specific times and details');
      buffer.writeln('- Focus on positive moments and connections');
      buffer.writeln(
        '- Start each day with the day name (e.g., "Today", "Yesterday")',
      );
      buffer.writeln('- Write as a flowing narrative, not a list');
      buffer.writeln(
        '- IMPORTANT: Format ALL person names in bold using markdown: **Name**',
      );
      buffer.writeln(
        '  Example: "You spent time with **John** and **Sarah**."',
      );
      buffer.writeln();
      buffer.writeln('Create a warm day-by-day summary:');

      final prompt = buffer.toString();

      print('📤 GEMINI PROMPT:');
      print('─────────────────────────────────────────────────────');
      print(prompt);
      print('═══════════════════════════════════════════════════════\n');

      // Call Gemini directly
      final value = await Gemini.instance.text(prompt);
      final summary = value?.output?.trim() ?? '';
      return summary;
    } catch (e) {
      print('❌ Gemini error: $e');
      // Fallback to simple summary
      return summariesByDate.entries
          .map((entry) {
            final date = DateTime.parse(entry.key);
            final dayName = _getDayName(date);
            final people = entry.value
                .map((a) => a['personName'])
                .toSet()
                .join(', ');
            return '$dayName: You spent time with $people.';
          })
          .join('\n\n');
    }
  }

  String _getDayName(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(date.year, date.month, date.day);
    final difference = today.difference(targetDate).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    if (difference < 7) return '$difference days ago';
    return '${date.month}/${date.day}/${date.year}';
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

        // Face Guideline Overlay

        // AR overlays for recognized faces
        ..._detectedFaces.entries.map((entry) {
          if (entry.value != null) {
            return ArOverlayWidget(
              key: ValueKey(entry.key.trackingId),
              face: entry.key,
              knownFace: entry.value!,
              imageSize:
                  MediaQuery.of(context).orientation == Orientation.landscape
                  ? Size(
                      _cameraController!.value.previewSize!.width,
                      _cameraController!.value.previewSize!.height,
                    )
                  : Size(
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
                // Back button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
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
              ],
            ),
          ),
        ),

        // Bottom Left: Time and Location
        Positioned(
          bottom: 24,
          left: 24,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _currentTime,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.w300,
                    shadows: [
                      Shadow(
                        offset: Offset(0, 2),
                        blurRadius: 4,
                        color: Colors.black45,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Holy Angel University Foundation',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        shadows: const [
                          Shadow(
                            offset: Offset(0, 1),
                            blurRadius: 2,
                            color: Colors.black45,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Bottom Right: Face Count
        Positioned(
          bottom: 24,
          right: 24,
          child: SafeArea(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.face, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _detectedFaces.isEmpty
                            ? 'Scanning...'
                            : '${_detectedFaces.length} Detected',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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

        // Recording Indicator (Positioned lower to avoid overlap)
        if (_isRecording)
          Positioned(
            top: MediaQuery.of(context).padding.top + 80, // Lower position
            right: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.fiber_manual_record,
                  color: Colors.red,
                  size: 16,
                  shadows: [
                    Shadow(
                      blurRadius: 2,
                      color: Colors.black54,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                SizedBox(width: 8),
                Text(
                  'Recording',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        blurRadius: 2,
                        color: Colors.black54,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Expandable Floating Action Menu (Bottom Right)
        Positioned(
          bottom: 100,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Daily Summary Button (appears when expanded)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                height: _isMenuExpanded ? 70 : 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _isMenuExpanded ? 1.0 : 0.0,
                  child: _isMenuExpanded
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _showDayByDaySummary = !_showDayByDaySummary;
                                  _isMenuExpanded = false;
                                });
                                if (_showDayByDaySummary) {
                                  _loadDayByDaySummary();
                                }
                              },
                              borderRadius: BorderRadius.circular(25),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withValues(alpha: 0.2),
                                      Colors.white.withValues(alpha: 0.1),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(25),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.3),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 10,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(25),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                      sigmaX: 10,
                                      sigmaY: 10,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.calendar_today_rounded,
                                          color: Colors.white.withValues(
                                            alpha: 0.9,
                                          ),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'Summary',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),

              // SOS Button (appears when expanded)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                height: _isMenuExpanded ? 70 : 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _isMenuExpanded ? 1.0 : 0.0,
                  child: _isMenuExpanded
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () async {
                                print('🆘 SOS Button Pressed!');

                                final userProvider = Provider.of<UserProvider>(
                                  context,
                                  listen: false,
                                );
                                final patientId = userProvider.currentUser!.uid;

                                setState(() {
                                  _isMenuExpanded = false;
                                });

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      '🆘 SOS Triggered (Debug Mode)',
                                    ),
                                    backgroundColor: Colors.red,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(25),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withValues(alpha: 0.2),
                                      Colors.white.withValues(alpha: 0.1),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(25),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.3),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 10,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(25),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                      sigmaX: 10,
                                      sigmaY: 10,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.emergency_rounded,
                                          color: Colors.white.withValues(
                                            alpha: 0.9,
                                          ),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'SOS',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),

              // Main Menu Toggle Button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _isMenuExpanded = !_isMenuExpanded;
                    });
                  },
                  borderRadius: BorderRadius.circular(30),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isMenuExpanded
                            ? [
                                Colors.white.withValues(alpha: 0.3),
                                Colors.white.withValues(alpha: 0.2),
                              ]
                            : [
                                Colors.white.withValues(alpha: 0.2),
                                Colors.white.withValues(alpha: 0.1),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: AnimatedRotation(
                          duration: const Duration(milliseconds: 300),
                          turns: _isMenuExpanded ? 0.125 : 0, // 45 degrees
                          child: Icon(
                            _isMenuExpanded ? Icons.close : Icons.menu_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNameInputOverlay() {
    // Controller is now in state
    return Container(
      color: Colors.black.withOpacity(0.4), // Semi-transparent background
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primary.withOpacity(0.85),
                        AppColors.secondary.withOpacity(0.5),
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Enter Person\'s Name',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              offset: Offset(0, 1),
                              blurRadius: 2,
                              color: Colors.black26,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Name',
                          labelStyle: const TextStyle(color: Colors.white70),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.5),
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: Colors.white),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.1),
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
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withOpacity(0.5),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
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
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton(
                            onPressed: _cancelEnrollment,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () =>
                                _collectNameInput(_nameController.text),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.primary,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Next',
                              style: TextStyle(fontWeight: FontWeight.bold),
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
      ),
    );
  }

  Widget _buildRelationshipInputOverlay() {
    // Controller is now in state
    return Container(
      color: Colors.black.withOpacity(0.4), // Semi-transparent background
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primary.withOpacity(0.85),
                        AppColors.secondary.withOpacity(0.5),
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Relationship',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              offset: Offset(0, 1),
                              blurRadius: 2,
                              color: Colors.black26,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _relationshipController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'e.g., Friend, Family',
                          labelStyle: const TextStyle(color: Colors.white70),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.5),
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: Colors.white),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.1),
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
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withOpacity(0.5),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
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
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton(
                            onPressed: _cancelEnrollment,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => _collectRelationshipInput(
                              _relationshipController.text,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.primary,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Start Capture',
                              style: TextStyle(fontWeight: FontWeight.bold),
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
    final screenSize = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;

    // Target dimensions for minimized state (Upper Right)
    final double minHeight = 48.0;
    final double minWidth = 110.0;
    final double minTop = padding.top + 16.0;
    final double minRight = 16.0;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOutCubic,
      // Full screen (0,0,0,0) -> Upper Right Box
      top: _isSavingMinimized ? minTop : 0,
      right: _isSavingMinimized ? minRight : 0,
      left: _isSavingMinimized ? screenSize.width - (minWidth + minRight) : 0,
      bottom: _isSavingMinimized ? screenSize.height - (minTop + minHeight) : 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(_isSavingMinimized ? 0.7 : 0.8),
          borderRadius: BorderRadius.circular(_isSavingMinimized ? 24 : 0),
        ),
        padding: _isSavingMinimized
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
            : EdgeInsets.zero,
        child: _isSavingMinimized
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Saving...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
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
