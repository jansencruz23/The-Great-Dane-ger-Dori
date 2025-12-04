import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/known_face_model.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';

class FaceRecognitionService {
  Interpreter? _interpreter;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: false,
      enableClassification: false,
      enableLandmarks: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  List<KnownFaceModel> _knownFaces = [];
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  // Initialize TensorFlow Lite model
  Future<void> initialize() async {
    try {
      // Load FaceNet-512 model for face recognition
      _interpreter = await Interpreter.fromAsset(
        'assets/models/facenet_512.tflite',
      );

      // Print model input/output shapes for debugging
      final inputTensors = _interpreter!.getInputTensors();
      final outputTensors = _interpreter!.getOutputTensors();

      print('=== Face Recognition Model Info ===');
      print('Input tensors: ${inputTensors.length}');
      for (var i = 0; i < inputTensors.length; i++) {
        print('  Input $i shape: ${inputTensors[i].shape}');
        print('  Input $i type: ${inputTensors[i].type}');
      }

      print('Output tensors: ${outputTensors.length}');
      for (var i = 0; i < outputTensors.length; i++) {
        print('  Output $i shape: ${outputTensors[i].shape}');
        print('  Output $i type: ${outputTensors[i].type}');
      }
      print('===================================');

      _isInitialized = true;
      print('Face recognition service initialized');
    } catch (e) {
      print('Face recognition service initialization failed: $e');
      throw 'Failed to initialize face recognition service';
    }
  }

  // Dispose resources
  void dispose() {
    _interpreter?.close();
    _faceDetector.close();
    _isInitialized = false;
  }

  // Update known faces list
  void updateKnownFaces(List<KnownFaceModel> faces) {
    _knownFaces = faces;
  }

  // Detect faces in camera image
  Future<List<Face>> detectFaces(
    CameraImage cameraImage,
    InputImageRotation rotation,
  ) async {
    if (!_isInitialized) {
      throw 'Face recognition not initialized';
    }

    try {
      final inputImage = _convertCameraImage(cameraImage, rotation);
      final faces = await _faceDetector.processImage(inputImage);
      return faces;
    } catch (e) {
      print('Face detection failed: $e');
      return [];
    }
  }

  // Detect faces in file
  Future<List<Face>> detectFacesInFile(File imageFile) async {
    if (!_isInitialized) {
      throw 'Face recognition not initialized';
    }

    try {
      final inputImage = InputImage.fromFile(imageFile);
      final faces = await _faceDetector.processImage(inputImage);
      return faces;
    } catch (e) {
      print('Face detection failed: $e');
      return [];
    }
  }

  // Extract face embedding from detected face (Legacy - for file images)
  Future<List<double>?> extractFaceEmbedding(img.Image image, Face face) async {
    if (!_isInitialized || _interpreter == null) {
      return null;
    }

    try {
      // Crop face from image
      final faceImage = _cropAndAlignFace(image, face);
      if (faceImage == null) return null;

      return _runInference(faceImage);
    } catch (e) {
      print('Face embedding extraction failed: $e');
      return null;
    }
  }

  // Optimized: Extract face embedding directly from YUV CameraImage
  Future<List<double>?> extractFaceEmbeddingFromYUV(
    CameraImage cameraImage,
    Face face,
    InputImageRotation rotation,
  ) async {
    if (!_isInitialized || _interpreter == null) return null;
    try {
      // 1. Crop raw face from YUV
      final rawFaceImage = _cropFaceFromYUV(cameraImage, face);
      if (rawFaceImage == null) return null;

      // 2. Align (rotate) the cropped face
      final alignedImage = _alignCroppedFace(rawFaceImage, face);

      return _runInference(alignedImage);
    } catch (e) {
      print('Face embedding extraction from YUV failed: $e');
      return null;
    }
  }

  // Public method to get embedding from an already cropped face image
  Future<List<double>?> getEmbeddingFromCroppedImage(
    img.Image faceImage,
  ) async {
    if (!_isInitialized || _interpreter == null) {
      return null;
    }
    return _runInference(faceImage);
  }

  // Helper: Run inference on a cropped face image
  Future<List<double>?> _runInference(img.Image faceImage) async {
    try {
      // Resize to model input size (160x160 for FaceNet-512)
      final resized = img.copyResize(faceImage, width: 160, height: 160);

      // Prepare input tensor (batch size 1)
      final input = _imageToByteList(resized);

      // Prepare output tensor (512-dimensional embedding, batch size 1)
      final output = List.filled(512, 0.0).reshape([1, 512]);

      // Run inference
      _interpreter!.run(input, output);

      // Extract the embedding from output
      final embedding = List<double>.from(output[0]);
      final normalized = Helpers.normalizeEmbedding(embedding);

      return normalized;
    } catch (e) {
      print('Inference failed: $e');
      return null;
    }
  }

  // Recognize face by comparing with known faces
  KnownFaceModel? recognizeFace(List<double> embedding) {
    if (_knownFaces.isEmpty) {
      print('DEBUG: No known faces loaded');
      return null;
    }

    print('DEBUG: Comparing against ${_knownFaces.length} known faces');

    // Calculate similarities for all known faces
    final matches = <({KnownFaceModel face, double similarity})>[];

    for (final knownFace in _knownFaces) {
      final template = _averageEmbeddings(knownFace.getAllEmbeddings());
      final similarity = Helpers.cosineSimilarity(embedding, template);
      matches.add((face: knownFace, similarity: similarity));

      // Print each comparison
      print(
        'DEBUG:   ${knownFace.name}: similarity = ${similarity.toStringAsFixed(4)}',
      );
    }

    // Sort by similarity (descending)
    matches.sort((a, b) => b.similarity.compareTo(a.similarity));

    // Top-1 match must exceed threshold
    final best = matches.first;

    print(
      'DEBUG: Best match: ${best.face.name} with similarity = ${best.similarity.toStringAsFixed(4)}',
    );
    print('DEBUG: Threshold: ${AppConstants.faceRecognitionThreshold}');

    // AND the gap between best and second-best should be significant
    if (best.similarity >= AppConstants.faceRecognitionThreshold) {
      // Optional: Require margin between top-2 candidates
      if (matches.length > 1) {
        final secondBest = matches[1];
        final margin = best.similarity - secondBest.similarity;

        // Require at least 0.025 difference (tune this)
        if (margin >= 0.025) {
          return best.face;
        }
      } else {
        return best.face;
      }
    }

    return null;
  }

  // Helper to average embeddings
  List<double> _averageEmbeddings(List<List<double>> embeddings) {
    if (embeddings.isEmpty) return [];

    final avgEmbedding = List<double>.filled(embeddings[0].length, 0.0);

    for (final emb in embeddings) {
      for (int i = 0; i < emb.length; i++) {
        avgEmbedding[i] += emb[i];
      }
    }

    // Average
    for (int i = 0; i < avgEmbedding.length; i++) {
      avgEmbedding[i] /= embeddings.length;
    }

    // Re-normalize after averaging
    return Helpers.normalizeEmbedding(avgEmbedding);
  }

  // Process camera frame for recognition
  Future<Map<Face, KnownFaceModel?>> processCameraFrame(
    CameraImage cameraImage,
    InputImageRotation rotation,
  ) async {
    if (!_isInitialized) return {};

    try {
      // Detect faces
      final faces = await detectFaces(cameraImage, rotation);
      if (faces.isEmpty) return {};

      // Process each face
      final results = <Face, KnownFaceModel?>{};

      for (final face in faces) {
        // Extract embedding directly from YUV buffer (optimized)
        final embedding = await extractFaceEmbeddingFromYUV(
          cameraImage,
          face,
          rotation,
        );

        if (embedding != null) {
          // Recognize face
          final match = recognizeFace(embedding);
          results[face] = match;
        } else {
          results[face] = null;
        }
      }

      return results;
    } catch (e) {
      print('Error processing camera frame: $e');
      return {};
    }
  }

  // Helper: Convert CameraImage to InputImage for ML Kit
  InputImage _convertCameraImage(
    CameraImage cameraImage,
    InputImageRotation rotation,
  ) {
    // 1. Get the raw bytes
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in cameraImage.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    // 2. Get the size
    final imageSize = Size(
      cameraImage.width.toDouble(),
      cameraImage.height.toDouble(),
    );

    // 4. Handle format (Android defaults to NV21, iOS to BGRA8888)
    final InputImageFormat inputImageFormat = Platform.isIOS
        ? InputImageFormat.bgra8888
        : InputImageFormat.nv21;

    // 5. Create the new metadata object
    final inputImageMetadata = InputImageMetadata(
      size: imageSize,
      rotation: rotation,
      format: inputImageFormat,
      bytesPerRow: cameraImage.planes[0].bytesPerRow,
    );

    // 6. Return the InputImage
    return InputImage.fromBytes(bytes: bytes, metadata: inputImageMetadata);
  }

  // Helper: Convert CameraImage to img.Image
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

    final img.Image imgImage = img.Image(width: width, height: height);

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

  img.Image _alignCroppedFace(img.Image croppedImage, Face face) {
    final leftEye = face.landmarks[FaceLandmarkType.leftEye];
    final rightEye = face.landmarks[FaceLandmarkType.rightEye];

    if (leftEye == null || rightEye == null) return croppedImage;

    // Calculate angle
    final dy = rightEye.position.y - leftEye.position.y;
    final dx = rightEye.position.x - leftEye.position.x;
    final angle = (atan2(dy, dx) * 180 / pi);

    // Only rotate if the tilt is significant (> 3 degrees) to save CPU
    if (angle.abs() > 3.0) {
      return img.copyRotate(croppedImage, angle: angle);
    }

    return croppedImage;
  }

  img.Image? _cropAndAlignFace(img.Image image, Face face) {
    try {
      // 1. Get Landmarks
      final leftEye = face.landmarks[FaceLandmarkType.leftEye];
      final rightEye = face.landmarks[FaceLandmarkType.rightEye];

      if (leftEye == null || rightEye == null) {
        return _cropFace(image, face); // Fallback to crop without alignment
      }

      // 2. Calculate Angle (Rotation needed to make eyes horizontal)
      final dy = rightEye.position.y - leftEye.position.y;
      final dx = rightEye.position.x - leftEye.position.x;

      // Calculate angle in degrees
      final angle = (atan2(dy, dx) * 180 / pi);

      // Use existing crop, but rotate the RESULT
      // This is faster than full affine transformation
      img.Image? cropped = _cropFace(image, face);
      if (cropped != null && angle.abs() > 3.0) {
        // Only rotate if tilt is significant
        return img.copyRotate(cropped, angle: angle);
      }
      return cropped;
    } catch (e) {
      print('Alignment failed: $e');
      return null;
    }
  }

  // Helper: Crop face region from image
  img.Image? _cropFace(img.Image image, Face face) {
    try {
      final rect = face.boundingBox;

      // Calculate center of face
      final centerX = rect.left + rect.width / 2;
      final centerY = rect.top + rect.height / 2;

      // Use the larger dimension to create a square
      // Add padding factor (1.3x = 30% larger than face for context)
      final size = (rect.width > rect.height ? rect.width : rect.height) * 1.3;

      // Calculate square crop coordinates centered on face
      final x = (centerX - size / 2).clamp(0, image.width).toInt();
      final y = (centerY - size / 2).clamp(0, image.height).toInt();
      final cropSize = size
          .clamp(
            0,
            (image.width - x) < (image.height - y)
                ? (image.width - x)
                : (image.height - y),
          )
          .toInt();

      // Crop square region
      final cropped = img.copyCrop(
        image,
        x: x,
        y: y,
        width: cropSize,
        height: cropSize,
      );

      // Resize to 160x160 (no distortion since it's already square)
      return img.copyResize(cropped, width: 160, height: 160);
    } catch (e) {
      print('Error cropping face: $e');
      return null;
    }
  }

  // Optimized: Crop and convert ONLY the face region from YUV buffer
  img.Image? _cropFaceFromYUV(CameraImage image, Face face) {
    try {
      // Only support YUV420 for now (standard Android format)
      if (image.format.group != ImageFormatGroup.yuv420) {
        return _convertToImage(image); // Fallback to full conversion if not YUV
      }

      final int width = image.width;
      final int height = image.height;

      // Get face bounding box with padding
      final rect = face.boundingBox;
      final padding = 20;

      // Calculate crop coordinates (clamped to image bounds)
      final int left = (rect.left - padding).toInt().clamp(0, width - 1);
      final int top = (rect.top - padding).toInt().clamp(0, height - 1);
      final int right = (rect.right + padding).toInt().clamp(0, width - 1);
      final int bottom = (rect.bottom + padding).toInt().clamp(0, height - 1);

      final int cropWidth = right - left;
      final int cropHeight = bottom - top;

      if (cropWidth <= 0 || cropHeight <= 0) return null;

      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final img.Image faceImage = img.Image(
        width: cropWidth,
        height: cropHeight,
      );

      // Iterate ONLY over the cropped region
      for (int y = 0; y < cropHeight; y++) {
        final int sourceY = top + y;

        for (int x = 0; x < cropWidth; x++) {
          final int sourceX = left + x;

          final int yIndex = sourceY * yPlane.bytesPerRow + sourceX;
          final int uvIndex =
              (sourceY ~/ 2) * uPlane.bytesPerRow + (sourceX ~/ 2);

          final int yValue = yPlane.bytes[yIndex];
          final int uValue = uPlane.bytes[uvIndex];
          final int vValue = vPlane.bytes[uvIndex];

          // YUV to RGB conversion
          final r = (yValue + 1.370705 * (vValue - 128)).clamp(0, 255).toInt();
          final g =
              (yValue - 0.337633 * (uValue - 128) - 0.698001 * (vValue - 128))
                  .clamp(0, 255)
                  .toInt();
          final b = (yValue + 1.732446 * (uValue - 128)).clamp(0, 255).toInt();

          faceImage.setPixelRgba(x, y, r, g, b, 255);
        }
      }

      return faceImage;
    } catch (e) {
      print('Error cropping face from YUV: $e');
      return null;
    }
  }

  // Public method for enrollment - crops face from YUV for UI purposes
  img.Image? cropFaceFromYUV(
    CameraImage image,
    Face face,
    InputImageRotation rotation,
  ) {
    return _cropFaceFromYUV(image, face);
  }

  // Helper: Convert image to byte list for TensorFlow Lite
  List<List<List<List<double>>>> _imageToByteList(img.Image image) {
    // Create batch size 1 for FaceNet-512
    final input = List.generate(
      1,
      (_) => List.generate(
        160,
        (_) => List.generate(160, (_) => List.filled(3, 0.0)),
      ),
    );

    for (int y = 0; y < 160; y++) {
      for (int x = 0; x < 160; x++) {
        final pixel = image.getPixel(x, y);

        // Normalize to [-1, 1] using standard FaceNet preprocessing
        // Formula: (pixel - 127.5) / 128
        final r = (pixel.r - 127.5) / 128.0;
        final g = (pixel.g - 127.5) / 128.0;
        final b = (pixel.b - 127.5) / 128.0;

        input[0][y][x][0] = r;
        input[0][y][x][1] = g;
        input[0][y][x][2] = b;
      }
    }

    return input;
  }
}
