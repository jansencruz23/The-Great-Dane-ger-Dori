import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/known_face_model.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';

class FaceRecognitionService {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableLandmarks: true,
      enableContours: false,
      enableClassification: false,
      minFaceSize: 0.1,
    ),
  );

  _RecognitionWorker? _worker;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  // Initialize Service and Worker
  Future<void> initialize() async {
    try {
      _worker = _RecognitionWorker();
      await _worker!.spawn();

      _isInitialized = true;
      print('Face recognition service initialized');
    } catch (e) {
      print('Face recognition service initialization failed: $e');
      throw 'Failed to initialize face recognition service';
    }
  }

  // Dispose resources
  void dispose() {
    _worker?.dispose();
    _faceDetector.close();
    _isInitialized = false;
  }

  // Update known faces list
  void updateKnownFaces(List<KnownFaceModel> faces) {
    _worker?.updateFaces(faces);
  }

  // Detect faces in camera image (Main Thread - fast platform call)
  Future<List<Face>> detectFaces(
    CameraImage cameraImage, {
    InputImageRotation? rotation,
  }) async {
    if (!_isInitialized) {
      throw 'Face recognition not initialized';
    }

    try {
      final inputImage = _convertCameraImage(cameraImage, rotation: rotation);
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

  // Extract face embedding (Delegated to Worker)
  Future<List<double>?> extractFaceEmbedding(img.Image image, Face face) async {
    // This method is kept for compatibility but should ideally not be used directly
    // if we want to use the worker.
    // For now, we'll return null or throw, as we want to enforce using processCameraFrame
    print(
      'Warning: extractFaceEmbedding called directly. Use processCameraFrame for performance.',
    );
    return null;
  }

  // Process camera frame for recognition (Delegated to Worker)
  Future<Map<Face, KnownFaceModel?>> processCameraFrame(
    CameraImage cameraImage, {
    InputImageRotation? rotation,
  }) async {
    if (!_isInitialized || _worker == null) return {};

    try {
      // 1. Detect faces (Main Thread)
      final faces = await detectFaces(cameraImage, rotation: rotation);
      if (faces.isEmpty) return {};

      // 2. Prepare data for worker
      final isolateData = _IsolateData(
        cameraImage: cameraImage,
        rotation: rotation,
      );

      final faceRects = faces.map((f) => f.boundingBox).toList();

      // 3. Process in worker (Isolate)
      // This handles conversion, cropping, embedding, and matching
      final matches = await _worker!.process(isolateData, faceRects);

      // 4. Map results back to faces
      final results = <Face, KnownFaceModel?>{};
      for (int i = 0; i < faces.length; i++) {
        if (i < matches.length) {
          results[faces[i]] = matches[i];
        } else {
          results[faces[i]] = null;
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
    CameraImage cameraImage, {
    InputImageRotation? rotation,
  }) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in cameraImage.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final imageSize = Size(
      cameraImage.width.toDouble(),
      cameraImage.height.toDouble(),
    );

    final imageRotation =
        rotation ??
        (Platform.isAndroid
            ? InputImageRotation.rotation90deg
            : InputImageRotation.rotation0deg);

    final inputImageFormat = Platform.isIOS
        ? InputImageFormat.bgra8888
        : InputImageFormat.nv21;

    final inputImageMetadata = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: cameraImage.planes[0].bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: inputImageMetadata);
  }
}

// ==================== WORKER IMPLEMENTATION ====================

class _RecognitionWorker {
  late Isolate _isolate;
  late SendPort _sendPort;
  final ReceivePort _receivePort = ReceivePort();
  final Map<int, Completer<List<KnownFaceModel?>>> _pendingRequests = {};
  int _nextRequestId = 0;

  Future<void> spawn() async {
    final rootToken = RootIsolateToken.instance!;
    _isolate = await Isolate.spawn(
      _workerEntry,
      _WorkerInit(_receivePort.sendPort, rootToken),
    );

    final completer = Completer<void>();
    _receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        completer.complete();
      } else if (message is _WorkerResponse) {
        final reqCompleter = _pendingRequests.remove(message.requestId);
        reqCompleter?.complete(message.results);
      }
    });

    await completer.future;
  }

  void updateFaces(List<KnownFaceModel> faces) {
    _sendPort.send(_UpdateFacesCommand(faces));
  }

  Future<List<KnownFaceModel?>> process(
    _IsolateData data,
    List<Rect> faceRects,
  ) {
    final id = _nextRequestId++;
    final completer = Completer<List<KnownFaceModel?>>();
    _pendingRequests[id] = completer;
    _sendPort.send(_ProcessCommand(data, faceRects, id));
    return completer.future;
  }

  void dispose() {
    _receivePort.close();
    _isolate.kill();
  }
}

// Worker Entry Point
void _workerEntry(_WorkerInit init) async {
  // Initialize platform channels
  BackgroundIsolateBinaryMessenger.ensureInitialized(init.rootToken);

  final receivePort = ReceivePort();
  init.sendPort.send(receivePort.sendPort);

  Interpreter? interpreter;
  List<KnownFaceModel> knownFaces = [];

  try {
    interpreter = await Interpreter.fromAsset(
      'assets/models/MobileFaceNet.tflite',
    );
    print('Worker: Model loaded successfully');
  } catch (e) {
    print('Worker: Failed to load model: $e');
  }

  receivePort.listen((message) async {
    if (message is _UpdateFacesCommand) {
      knownFaces = message.faces;
    } else if (message is _ProcessCommand) {
      if (interpreter == null) {
        init.sendPort.send(
          _WorkerResponse(
            message.requestId,
            List.filled(message.faceRects.length, null),
          ),
        );
        return;
      }

      try {
        // 1. Convert Image
        final image = _convertToImage(message.imageData);
        if (image == null) {
          init.sendPort.send(
            _WorkerResponse(
              message.requestId,
              List.filled(message.faceRects.length, null),
            ),
          );
          return;
        }

        // 2. Process each face
        final results = <KnownFaceModel?>[];
        for (final rect in message.faceRects) {
          final embedding = _extractEmbedding(interpreter, image, rect);
          if (embedding != null) {
            final match = _recognizeFace(embedding, knownFaces);
            results.add(match);
          } else {
            results.add(null);
          }
        }

        init.sendPort.send(_WorkerResponse(message.requestId, results));
      } catch (e) {
        print('Worker: Error processing frame: $e');
        init.sendPort.send(
          _WorkerResponse(
            message.requestId,
            List.filled(message.faceRects.length, null),
          ),
        );
      }
    }
  });
}

// Worker Helpers
img.Image? _convertToImage(_IsolateData data) {
  try {
    if (data.formatGroup == ImageFormatGroup.yuv420) {
      return _convertYUV420(data);
    } else if (data.formatGroup == ImageFormatGroup.bgra8888) {
      return _convertBGRA8888(data);
    }
    return null;
  } catch (e) {
    print('Worker: Error converting image: $e');
    return null;
  }
}

img.Image _convertYUV420(_IsolateData data) {
  final width = data.width;
  final height = data.height;
  final yPlane = data.planes[0];
  final uPlane = data.planes[1];
  final vPlane = data.planes[2];
  final yRowStride = data.bytesPerRow[0];
  final uRowStride = data.bytesPerRow[1];
  final uvPixelStride = data.planesPixelStride[1];

  final img.Image imgImage = img.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final yIndex = y * yRowStride + x;
      final uvIndex = (y ~/ 2) * uRowStride + (x ~/ 2) * uvPixelStride;

      final yValue = yPlane[yIndex];
      final uValue = uPlane[uvIndex];
      final vValue = vPlane[uvIndex];

      final r = (yValue + 1.370705 * (vValue - 128)).clamp(0, 255).toInt();
      final g = (yValue - 0.337633 * (uValue - 128) - 0.698001 * (vValue - 128))
          .clamp(0, 255)
          .toInt();
      final b = (yValue + 1.732446 * (uValue - 128)).clamp(0, 255).toInt();

      imgImage.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  return imgImage;
}

img.Image _convertBGRA8888(_IsolateData data) {
  return img.Image.fromBytes(
    width: data.width,
    height: data.height,
    bytes: data.planes[0].buffer,
    order: img.ChannelOrder.bgra,
  );
}

List<double>? _extractEmbedding(
  Interpreter interpreter,
  img.Image image,
  Rect rect,
) {
  try {
    // Crop
    final padding = 20;
    final x = (rect.left - padding).clamp(0, image.width).toInt();
    final y = (rect.top - padding).clamp(0, image.height).toInt();
    final width = (rect.width + padding * 2).clamp(0, image.width - x).toInt();
    final height = (rect.height + padding * 2)
        .clamp(0, image.height - y)
        .toInt();

    final faceImage = img.copyCrop(
      image,
      x: x,
      y: y,
      width: width,
      height: height,
    );
    final resized = img.copyResize(faceImage, width: 112, height: 112);

    // Preprocess
    final input = List.generate(
      1, // Batch size 1
      (_) => List.generate(
        112,
        (_) => List.generate(112, (_) => List.filled(3, 0.0)),
      ),
    );

    for (int y = 0; y < 112; y++) {
      for (int x = 0; x < 112; x++) {
        final pixel = resized.getPixel(x, y);
        final r = (pixel.r - 127.5) / 128.0;
        final g = (pixel.g - 127.5) / 128.0;
        final b = (pixel.b - 127.5) / 128.0;
        input[0][y][x][0] = r;
        input[0][y][x][1] = g;
        input[0][y][x][2] = b;
      }
    }

    // Inference
    final output = List.filled(1 * 192, 0.0).reshape([1, 192]);
    interpreter.run(input, output);

    final embedding = List<double>.from(output[0]);
    return Helpers.normalizeEmbedding(embedding);
  } catch (e) {
    print('Worker: Error extracting embedding: $e');
    return null;
  }
}

KnownFaceModel? _recognizeFace(
  List<double> embedding,
  List<KnownFaceModel> knownFaces,
) {
  KnownFaceModel? bestMatch;
  double bestSimilarity = 0.0;

  for (final knownFace in knownFaces) {
    final allEmbeddings = knownFace.getAllEmbeddings();
    for (final knownEmbedding in allEmbeddings) {
      final similarity = Helpers.cosineSimilarity(embedding, knownEmbedding);
      final distance = Helpers.euclideanDistance(embedding, knownEmbedding);

      if (similarity >= AppConstants.faceRecognitionThreshold &&
          distance <= 0.7 &&
          similarity > bestSimilarity) {
        bestSimilarity = similarity;
        bestMatch = knownFace;
      }
    }
  }
  return bestMatch;
}

// Protocol Classes
class _WorkerInit {
  final SendPort sendPort;
  final RootIsolateToken rootToken;
  _WorkerInit(this.sendPort, this.rootToken);
}

class _UpdateFacesCommand {
  final List<KnownFaceModel> faces;
  _UpdateFacesCommand(this.faces);
}

class _ProcessCommand {
  final _IsolateData imageData;
  final List<Rect> faceRects;
  final int requestId;
  _ProcessCommand(this.imageData, this.faceRects, this.requestId);
}

class _WorkerResponse {
  final int requestId;
  final List<KnownFaceModel?> results;
  _WorkerResponse(this.requestId, this.results);
}

class _IsolateData {
  final List<Uint8List> planes;
  final List<int> bytesPerRow;
  final List<int> planesPixelStride;
  final int width;
  final int height;
  final ImageFormatGroup formatGroup;
  final InputImageRotation? rotation;

  _IsolateData({required CameraImage cameraImage, this.rotation})
    : planes = cameraImage.planes.map((p) => p.bytes).toList(),
      bytesPerRow = cameraImage.planes.map((p) => p.bytesPerRow).toList(),
      planesPixelStride = cameraImage.planes
          .map((p) => p.bytesPerPixel ?? 1)
          .toList(),
      width = cameraImage.width,
      height = cameraImage.height,
      formatGroup = cameraImage.format.group;
}
