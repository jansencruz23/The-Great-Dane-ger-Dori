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
import '../../widgets/enrollment_bubble_widget.dart';
import '../../widgets/enrollment_prompt_widget.dart';

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

  // Blocklist for faces the user feels unsure about (store embeddings)
  List<List<double>> _blockedFaceEmbeddings = [];

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
  bool _isListeningForEnrollmentPrompt = false;
  String _voiceInputBuffer = '';
  EnrollmentStep? _currentEnrollmentStep;
  String _enrollmentPromptText = '';
  String _enrollmentPromptSubtext = '';

  // Day-by-day summary state
  bool _showDayByDaySummary = false;
  String _dayByDaySummary = '';
  bool _isLoadingSummary = false;

  // Floating action menu state
  bool _isMenuExpanded = false;

  // Frame counters for performance optimization
  int _promptingFrameCount = 0;
  int _noFaceFrameCount = 0;

  @override
  void initState() {
    super.initState();

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

            // Extract embedding for unknown face (for blocklist comparison)
            final unknownFaceEntry = results.entries
                .where((entry) => entry.value == null)
                .firstOrNull;
            if (unknownFaceEntry != null && _unknownFaceEmbedding == null) {
              // Extract embedding for blocklist check
              final embedding = await _faceRecognitionService
                  .extractFaceEmbeddingFromYUV(
                    cameraImage,
                    unknownFaceEntry.key,
                    rotation,
                  );
              if (embedding != null) {
                _unknownFaceEmbedding = embedding;
                print('DEBUG: Extracted embedding for unknown face');
              }
            }

            // Handle face recognition
            await _handleFaceRecognition(results);
          }
        }
        // During prompting/collecting modes - lighter tracking with reduced frequency
        else if (_enrollmentMode == EnrollmentMode.prompting ||
            _enrollmentMode == EnrollmentMode.collectingName ||
            _enrollmentMode == EnrollmentMode.collectingRelationship) {
          // Only detect faces every few frames to save CPU
          _promptingFrameCount = (_promptingFrameCount + 1) % 3;

          if (_promptingFrameCount == 0) {
            final faces = await _faceRecognitionService.detectFaces(
              cameraImage,
              rotation,
            );

            if (mounted) {
              if (faces.isEmpty) {
                _noFaceFrameCount++;
                // Only cancel if face has been gone for multiple frames
                if (_noFaceFrameCount >= 3) {
                  print('DEBUG: Face left frame, canceling enrollment');
                  _noFaceFrameCount = 0;
                  await _handleEnrollmentNo();
                }
              } else {
                _noFaceFrameCount = 0;
                // Update the tracked face position for smooth following
                setState(() {
                  _unknownFace = faces.first;
                });
              }
            }
          }
        }
      } catch (e) {
        print('Error processing frame: $e');
      } finally {
        // Faster frame rate during prompting for smoother UI
        final delay =
            (_enrollmentMode == EnrollmentMode.prompting ||
                _enrollmentMode == EnrollmentMode.collectingName ||
                _enrollmentMode == EnrollmentMode.collectingRelationship)
            ? const Duration(milliseconds: 100) // 10fps for smooth bubble
            : const Duration(milliseconds: 500); // 2fps for recognition
        await Future.delayed(delay);
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
      // If same unknown face has been present for debounce time, check blocklist and prompt enrollment
      else if (now.difference(_unknownFaceFirstSeen!) >=
          _unknownFaceDebounceTime) {
        // Check if this face is in the blocklist first
        if (_unknownFaceEmbedding != null &&
            _isFaceBlocked(_unknownFaceEmbedding!)) {
          print('DEBUG: Face is in blocklist, skipping enrollment prompt');
          // Reset tracking so we don't keep checking this face
          _unknownFace = null;
          _unknownFaceEmbedding = null;
          _unknownFaceFirstSeen = null;
          return;
        }

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

  /// Checks if a face embedding matches any blocked face
  bool _isFaceBlocked(List<double> embedding) {
    if (_blockedFaceEmbeddings.isEmpty) return false;

    const double blockThreshold = 0.7; // Same as recognition threshold

    for (final blockedEmb in _blockedFaceEmbeddings) {
      final similarity = Helpers.cosineSimilarity(embedding, blockedEmb);
      if (similarity >= blockThreshold) {
        print('DEBUG: Face matches blocklist with similarity $similarity');
        return true;
      }
    }
    return false;
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
    _unknownFace = face;
    _unknownFaceFirstSeen = null;

    setState(() {
      _enrollmentMode = EnrollmentMode.prompting;
      _currentEnrollmentStep = EnrollmentStep.promptEnrollment;
      _enrollmentPromptText = 'How do you feel about this person?';
      _enrollmentPromptSubtext = 'Say "I feel safe" or "I feel unsure"';
      _isListeningForEnrollmentPrompt = true;
      _voiceInputBuffer = '';
    });

    // Start voice listening for safe/unsure response
    try {
      await _speechService.startListening(
        onResult: (text) {
          setState(() => _voiceInputBuffer = text.toLowerCase());

          // Check for cancel command
          if (_voiceInputBuffer.contains('cancel') ||
              _voiceInputBuffer.contains('stop') ||
              _voiceInputBuffer.contains('nevermind') ||
              _voiceInputBuffer.contains('never mind')) {
            _handleEnrollmentNo(); // Cancel is same as feeling unsure
            return;
          }

          // Check for safe/unsure responses
          if (_voiceInputBuffer.contains('safe') ||
              _voiceInputBuffer.contains('yes') ||
              _voiceInputBuffer.contains('comfortable') ||
              _voiceInputBuffer.contains('trust') ||
              _voiceInputBuffer.contains('know')) {
            _handleEnrollmentYes();
          } else if (_voiceInputBuffer.contains('unsure') ||
              _voiceInputBuffer.contains('no') ||
              _voiceInputBuffer.contains('uncertain') ||
              _voiceInputBuffer.contains("don't know") ||
              _voiceInputBuffer.contains('not sure')) {
            _handleEnrollmentNo();
          }
        },
      );
    } catch (e) {
      print('Error starting voice input: $e');
    }
  }

  Future<void> _handleEnrollmentYes() async {
    // Stop current listening
    try {
      await _speechService.stopListening();
    } catch (e) {
      print('Error stopping voice: $e');
    }

    setState(() {
      _enrollmentMode = EnrollmentMode.collectingName;
      _currentEnrollmentStep = EnrollmentStep.collectingName;
      _enrollmentPromptText = 'What is their name?';
      _isListeningForEnrollmentPrompt = false;
      _isListeningForName = true;
      _voiceInputBuffer = '';
    });

    // Start listening for name
    _startVoiceInput(true);
  }

  Future<void> _handleEnrollmentNo() async {
    // Stop current listening
    try {
      await _speechService.stopListening();
    } catch (e) {
      print('Error stopping voice: $e');
    }

    // Add the unknown face embedding to blocklist so it won't be detected again
    if (_unknownFaceEmbedding != null) {
      _blockedFaceEmbeddings.add(List.from(_unknownFaceEmbedding!));
      print(
        'DEBUG: Added face to blocklist. Total blocked: ${_blockedFaceEmbeddings.length}',
      );
    }

    setState(() {
      _enrollmentMode = EnrollmentMode.normal;
      _currentEnrollmentStep = null;
      _isListeningForEnrollmentPrompt = false;
      _voiceInputBuffer = '';
      _unknownFace = null;
      _unknownFaceEmbedding = null;
      _unknownFaceFirstSeen = null;
    });
  }

  Future<void> _collectNameInput(String name) async {
    if (name.trim().isEmpty) return;
    _enrollmentName = name.trim();

    // Stop current listening
    try {
      await _speechService.stopListening();
    } catch (e) {
      print('Error stopping voice: $e');
    }

    setState(() {
      _enrollmentMode = EnrollmentMode.collectingRelationship;
      _currentEnrollmentStep = EnrollmentStep.collectingRelationship;
      _enrollmentPromptText = 'What is their relationship to you?';
      _enrollmentPromptSubtext =
          'Say their relationship, then say "next" or "done" (or say "cancel" to stop)';
      _isListeningForName = false;
      _isListeningForRelationship = true;
      _voiceInputBuffer = '';
    });

    // Start listening for relationship
    _startVoiceInput(false);
  }

  Future<void> _collectRelationshipInput(String relationship) async {
    if (relationship.trim().isEmpty) return;
    _enrollmentRelationship = relationship.trim();

    // Stop current listening
    try {
      await _speechService.stopListening();
    } catch (e) {
      print('Error stopping voice: $e');
    }

    setState(() {
      _enrollmentMode = EnrollmentMode.capturingAngles;
      _currentEnrollmentStep = null;
      _enrollmentPromptText = 'Capturing face angles...';
      _enrollmentPromptSubtext = 'Please turn your head slowly';
      _isListeningForRelationship = false;
      _voiceInputBuffer = '';
    });
  }

  void _cancelEnrollment() async {
    // Stop any active voice listening
    try {
      await _speechService.stopListening();
    } catch (e) {
      print('Error stopping voice: $e');
    }

    setState(() {
      _enrollmentMode = EnrollmentMode.normal;
      _currentEnrollmentStep = null;
      _enrollmentImages.clear();
      _enrollmentEmbeddings.clear();
      _enrollmentName = '';
      _enrollmentRelationship = '';
      _enrollmentPromptText = '';
      _enrollmentPromptSubtext = '';
      _isListeningForEnrollmentPrompt = false;
      _isListeningForName = false;
      _isListeningForRelationship = false;
      _voiceInputBuffer = '';
      _unknownFace = null;
      _unknownFaceFirstSeen = null;
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
    print('🎤 Starting voice input for ${isForName ? "name" : "relationship"}');

    // ALWAYS restart speech service for clean state
    try {
      print('🛑 Stopping any existing speech recognition...');
      await _speechService.stopListening();
      // Small delay to ensure clean stop
      await Future.delayed(const Duration(milliseconds: 300));
      print('✅ Speech service stopped');
    } catch (e) {
      print('⚠️ Error stopping speech (might not be running): $e');
    }

    setState(() {
      if (isForName) {
        _isListeningForName = true;
      } else {
        _isListeningForRelationship = true;
      }
      _voiceInputBuffer = '';
    });

    try {
      print('🎤 Starting fresh speech recognition session...');
      await _speechService.startListening(
        onResult: (text) {
          // Just update the buffer, don't proceed yet
          setState(() => _voiceInputBuffer = text);

          // Enhanced debug logging
          print('═══════════════════════════════════════════════════');
          print('DEBUG: Voice input received: "$text"');
          print('═══════════════════════════════════════════════════');
        },
      );
      print('✅ Speech recognition started successfully');

      // Wait for speech to finish (pauseFor will trigger auto-stop after 3 seconds)
      await Future.delayed(
        const Duration(seconds: 5),
      ); // Wait longer than listenFor

      // Get the final transcript after speech service stops
      final finalInput = await _speechService.stopListening();

      print('DEBUG: Speech finished. Final input: "$finalInput"');

      // Auto-proceed with whatever was said
      if (finalInput.trim().isNotEmpty) {
        print('DEBUG: ✓ Auto-proceeding with input: "$finalInput"');
        if (isForName) {
          _collectNameInput(finalInput);
        } else {
          _collectRelationshipInput(finalInput);
        }
      } else {
        print('DEBUG: ⚠ No input received, restarting...');
        // Restart listening if nothing was said
        _startVoiceInput(isForName);
      }
    } catch (e) {
      print('❌ Error starting voice input: $e');
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

        // Enrollment bubble for unknown faces
        if (_enrollmentMode != EnrollmentMode.normal &&
            _unknownFace != null &&
            _currentEnrollmentStep != null)
          EnrollmentBubbleWidget(
            face: _unknownFace!,
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
            step: _currentEnrollmentStep!,
            voiceBuffer: _voiceInputBuffer,
            isListening:
                _isListeningForEnrollmentPrompt ||
                _isListeningForName ||
                _isListeningForRelationship,
            onYes: _handleEnrollmentYes,
            onNo: _handleEnrollmentNo,
            onCancel: _cancelEnrollment,
          ),

        // Top-left prompt text
        if (_enrollmentMode != EnrollmentMode.normal &&
            _enrollmentPromptText.isNotEmpty)
          EnrollmentPromptWidget(
            promptText: _enrollmentPromptText,
            subtext: _enrollmentPromptSubtext,
            isListening:
                _isListeningForEnrollmentPrompt ||
                _isListeningForName ||
                _isListeningForRelationship,
          ),

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
                      'Holy Angel University',
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
