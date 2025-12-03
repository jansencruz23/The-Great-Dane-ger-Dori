import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/known_face_model.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';

class FaceRecognitionService {
  Interpreter? _interpreter;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: false,
      enableLandmarks: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  List<KnownFaceModel> _knownFaces = [];
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  // Initialize TensorFlow Lite model
  Future<void> initialize() async {
    try {
      // Load MobileFaceNet model for face recognition
      _interpreter = await Interpreter.fromAsset(
        'assets/models/MobileFaceNet.tflite',
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
  Future<List<Face>> detectFaces(CameraImage cameraImage) async {
    if (!_isInitialized) {
      throw 'Face recognition not initialized';
    }

    try {
      final inputImage = _convertCameraImage(cameraImage);
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

  // Extract face embedding from detected face
  Future<List<double>?> extractFaceEmbedding(img.Image image, Face face) async {
    if (!_isInitialized || _interpreter == null) {
      return null;
    }

    try {
      // Crop face from image
      final faceImage = _cropFace(image, face);
      if (faceImage == null) return null;

      // Resize to model input size (112x112 for MobileFaceNet)
      final resized = img.copyResize(faceImage, width: 112, height: 112);

      // Prepare input tensor (batch size 2)
      final input = _imageToByteList(resized);

      // Prepare output tensor (192-dimensional embedding, batch size 2)
      final output = List.filled(2 * 192, 0.0).reshape([2, 192]);

      // Run inference
      _interpreter!.run(input, output);

      // Use only the first batch output (both batches contain the same image)
      // Averaging identical duplicates provides no benefit and may degrade quality
      final embedding = List<double>.from(output[0]);

      // Debug: Check embedding stats
      final embeddingSum = embedding.reduce((a, b) => a + b);
      final embeddingMean = embeddingSum / embedding.length;
      print(
        'DEBUG: Embedding stats - Length: ${embedding.length}, Mean: ${embeddingMean.toStringAsFixed(4)}, First 5 values: ${embedding.take(5).toList()}',
      );

      final normalized = Helpers.normalizeEmbedding(embedding);
      final normalizedSum = normalized.reduce((a, b) => a + b);
      print(
        'DEBUG: Normalized embedding sum: ${normalizedSum.toStringAsFixed(4)}',
      );

      return normalized;
    } catch (e) {
      print('Face embedding extraction failed: $e');
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

    KnownFaceModel? bestMatch;
    double bestSimilarity = 0.0;
    double bestDistance = double.infinity;
    int bestEmbeddingIndex = -1;

    for (final knownFace in _knownFaces) {
      // Compare against ALL stored embeddings for this person
      final allEmbeddings = knownFace.getAllEmbeddings();

      for (int i = 0; i < allEmbeddings.length; i++) {
        final similarity = Helpers.cosineSimilarity(
          embedding,
          allEmbeddings[i],
        );

        final distance = Helpers.euclideanDistance(embedding, allEmbeddings[i]);

        print(
          'DEBUG: ${knownFace.name} (angle $i): similarity=$similarity, distance=$distance (thresholds: similarity>=0.7, distance<=0.8)',
        );

        // Use both metrics: high similarity AND low distance for stricter matching
        if (similarity >= AppConstants.faceRecognitionThreshold &&
            distance <= 0.7 &&
            similarity > bestSimilarity) {
          bestSimilarity = similarity;
          bestDistance = distance;
          bestMatch = knownFace;
          bestEmbeddingIndex = i;
        }
      }
    }

    if (bestMatch != null) {
      print(
        'DEBUG: Best match: ${bestMatch.name} with similarity=$bestSimilarity, distance=$bestDistance (from angle $bestEmbeddingIndex)',
      );
    } else {
      print(
        'DEBUG: No match found. Best similarity was: $bestSimilarity, distance: $bestDistance',
      );
    }

    return bestMatch;
  }

  // Process camera frame for recognition
  Future<Map<Face, KnownFaceModel?>> processCameraFrame(
    CameraImage cameraImage,
  ) async {
    if (!_isInitialized) return {};

    try {
      // Detect faces
      final faces = await detectFaces(cameraImage);
      if (faces.isEmpty) return {};

      // Convert camera image to img.Image
      final image = _convertToImage(cameraImage);
      if (image == null) return {};

      // Process each face
      final results = <Face, KnownFaceModel?>{};

      for (final face in faces) {
        // Extract embedding
        final embedding = await extractFaceEmbedding(image, face);

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
  InputImage _convertCameraImage(CameraImage cameraImage) {
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

    // 3. Handle rotation - Android typically needs 90 degrees in portrait mode
    final InputImageRotation imageRotation = Platform.isAndroid
        ? InputImageRotation.rotation90deg
        : InputImageRotation.rotation0deg;

    // 4. Handle format (Android defaults to NV21, iOS to BGRA8888)
    final InputImageFormat inputImageFormat = Platform.isIOS
        ? InputImageFormat.bgra8888
        : InputImageFormat.nv21;

    // 5. Create the new metadata object
    final inputImageMetadata = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: cameraImage.planes[0].bytesPerRow,
    );

    print(
      'DEBUG: Image size: ${imageSize.width}x${imageSize.height}, rotation: $imageRotation',
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

  // Helper: Crop face region from image
  img.Image? _cropFace(img.Image image, Face face) {
    try {
      final rect = face.boundingBox;

      // Add padding
      final padding = 20;
      final x = (rect.left - padding).clamp(0, image.width).toInt();
      final y = (rect.top - padding).clamp(0, image.height).toInt();
      final width = (rect.width + padding * 2)
          .clamp(0, image.width - x)
          .toInt();
      final height = (rect.height + padding * 2)
          .clamp(0, image.height - y)
          .toInt();

      return img.copyCrop(image, x: x, y: y, width: width, height: height);
    } catch (e) {
      print('Error cropping face: $e');
      return null;
    }
  }

  // Helper: Convert image to byte list for TensorFlow Lite
  List<List<List<List<double>>>> _imageToByteList(img.Image image) {
    // Create batch size 2 (duplicate the same image for both batch slots)
    final input = List.generate(
      2,
      (_) => List.generate(
        112,
        (_) => List.generate(112, (_) => List.filled(3, 0.0)),
      ),
    );

    for (int y = 0; y < 112; y++) {
      for (int x = 0; x < 112; x++) {
        final pixel = image.getPixel(x, y);

        // Normalize to [-1, 1] using correct MobileFaceNet preprocessing
        // Formula: (pixel - 127.5) / 128
        final r = (pixel.r - 127.5) / 128.0;
        final g = (pixel.g - 127.5) / 128.0;
        final b = (pixel.b - 127.5) / 128.0;

        // Fill both batch slots with the same image
        input[0][y][x][0] = r;
        input[0][y][x][1] = g;
        input[0][y][x][2] = b;

        input[1][y][x][0] = r;
        input[1][y][x][1] = g;
        input[1][y][x][2] = b;
      }
    }

    return input;
  }
}
