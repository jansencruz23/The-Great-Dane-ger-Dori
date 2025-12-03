import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

import '../models/user_model.dart';
import '../models/known_face_model.dart';
import '../models/activity_log_model.dart';
import '../utils/constants.dart';

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ==================== USER OPERATIONS ====================

  Future<UserModel?> getUser(String uid) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .get();

      if (doc.exists) {
        return UserModel.fromFirestore(doc);
      }

      return null;
    } catch (e) {
      throw 'Error fetching user: $e';
    }
  }

  Future<void> createUser(UserModel user) async {
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .set(user.toMap());
    } catch (e) {
      throw 'Error creating user: $e';
    }
  }

  Future<void> updateUser(UserModel user) async {
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .update(user.toMap());
    } catch (e) {
      throw 'Error updating user: $e';
    }
  }

  Future<void> updateUserLastLogin(String uid) async {
    try {
      await _firestore.collection(AppConstants.usersCollection).doc(uid).update(
        {'lastLoginAt': FieldValue.serverTimestamp()},
      );
    } catch (e) {
      throw 'Error updating user last login: $e';
    }
  }

  Future<void> linkPatientToCaregiver(
    String caregiverId,
    String patientId,
  ) async {
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(caregiverId)
          .update({
            'patientIds': FieldValue.arrayUnion([patientId]),
          });
    } catch (e) {
      throw 'Error linking patient to caregiver: $e';
    }
  }

  Future<List<UserModel>> getCaregiversPatients(String caregiverId) async {
    try {
      final caregiver = await getUser(caregiverId);
      if (caregiver == null || caregiver.patientIds == null) {
        return [];
      }

      final patients = <UserModel>[];
      for (final patientId in caregiver.patientIds!) {
        final patient = await getUser(patientId);
        if (patient != null) {
          patients.add(patient);
        }
      }

      return patients;
    } catch (e) {
      throw 'Error fetching caregivers patients: $e';
    }
  }

  // ==================== KNOWN FACES OPERATIONS ====================

  Future<String> addKnownFace(
    KnownFaceModel face, {
    File? imageFile,
    List<File>? imageFiles,
  }) async {
    try {
      List<String>? imageUrls;

      // Upload multiple images if provided (for live enrollment)
      if (imageFiles != null && imageFiles.isNotEmpty) {
        imageUrls = [];
        for (final file in imageFiles) {
          final url = await uploadFaceImage(face.patientId, file);
          imageUrls.add(url);
        }
      }
      // Upload single image if provided (for gallery upload)
      else if (imageFile != null) {
        final url = await uploadFaceImage(face.patientId, imageFile);
        imageUrls = [url];
      }

      final faceWithImage = face.copyWith(imageUrls: imageUrls);

      final docRef = await _firestore
          .collection(AppConstants.knownFacesCollection)
          .add(faceWithImage.toMap());

      return docRef.id;
    } catch (e) {
      throw 'Error adding known face: $e';
    }
  }

  Future<void> updateKnownFace(KnownFaceModel face) async {
    try {
      await _firestore
          .collection(AppConstants.knownFacesCollection)
          .doc(face.id)
          .update(face.toMap());
    } catch (e) {
      throw 'Error updating known face: $e';
    }
  }

  Future<void> deleteKnownFace(String faceId) async {
    try {
      await _firestore
          .collection(AppConstants.knownFacesCollection)
          .doc(faceId)
          .delete();
    } catch (e) {
      throw 'Error deleting known face: $e';
    }
  }

  Future<List<KnownFaceModel>> getKnownFaces(String patientId) async {
    try {
      final querySnapshot = await _firestore
          .collection(AppConstants.knownFacesCollection)
          .where('patientId', isEqualTo: patientId)
          .get();

      return querySnapshot.docs
          .map((doc) => KnownFaceModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      throw 'Error fetching known faces: $e';
    }
  }

  Stream<List<KnownFaceModel>> streamKnownFaces(String patientId) {
    return _firestore
        .collection(AppConstants.knownFacesCollection)
        .where('patientId', isEqualTo: patientId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => KnownFaceModel.fromFirestore(doc))
              .toList(),
        );
  }

  Future<void> updateFaceLastSeen(String faceId) async {
    try {
      await _firestore
          .collection(AppConstants.knownFacesCollection)
          .doc(faceId)
          .update({
            'lastSeenAt': FieldValue.serverTimestamp(),
            'interactionCount': FieldValue.increment(1),
          });
    } catch (e) {
      throw 'Error updating face last seen: $e';
    }
  }

  // ==================== ACTIVITY LOG OPERATIONS ====================

  Future<String> createActivityLog(ActivityLogModel log) async {
    try {
      final docRef = await _firestore
          .collection(AppConstants.activityLogsCollection)
          .add(log.toMap());

      return docRef.id;
    } catch (e) {
      throw 'Error creating activity log: $e';
    }
  }

  Future<void> updateActivityLog(ActivityLogModel log) async {
    try {
      await _firestore
          .collection(AppConstants.activityLogsCollection)
          .doc(log.id)
          .update(log.toMap());
    } catch (e) {
      throw 'Error updating activity log: $e';
    }
  }

  Future<List<ActivityLogModel>> getActivityLogs(
    String patientId, {
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    try {
      Query query = _firestore
          .collection(AppConstants.activityLogsCollection)
          .where('patientId', isEqualTo: patientId)
          .orderBy('timestamp', descending: true);

      if (startDate != null) {
        query = query.where('timestamp', isGreaterThanOrEqualTo: startDate);
      }

      if (endDate != null) {
        query = query.where('timestamp', isLessThanOrEqualTo: endDate);
      }

      if (limit != null) {
        query = query.limit(limit);
      }

      final querySnapshot = await query.get();

      return querySnapshot.docs
          .map((doc) => ActivityLogModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      throw 'Error fetching activity logs: $e';
    }
  }

  Stream<List<ActivityLogModel>> streamActivityLogs(String patientId) {
    return _firestore
        .collection(AppConstants.activityLogsCollection)
        .where('patientId', isEqualTo: patientId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ActivityLogModel.fromFirestore(doc))
              .toList(),
        );
  }

  Future<List<ActivityLogModel>> getTodayActivityLogs(String patientId) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return await getActivityLogs(
      patientId,
      startDate: startOfDay,
      endDate: endOfDay,
    );
  }

  // ==================== STORAGE OPERATIONS ====================

  Future<String> uploadFaceImage(String patientId, File imageFile) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child(
        '${AppConstants.faceImagesPath}/$patientId/$fileName',
      );

      await ref.putFile(imageFile);
      final url = await ref.getDownloadURL();
      return url;
    } catch (e) {
      throw 'Error uploading face image: $e';
    }
  }

  Future<void> deleteFaceImage(String imageUrl) async {
    try {
      final ref = _storage.refFromURL(imageUrl);
      await ref.delete();
    } catch (e) {
      throw 'Error deleting face image: $e';
    }
  }

  // ==================== STATISTICS ====================

  Future<Map<String, dynamic>> getPatientStatistics(String patientId) async {
    try {
      final knownFaces = await getKnownFaces(patientId);
      final todayLogs = await getTodayActivityLogs(patientId);

      return {
        'totalKnownFaces': knownFaces.length,
        'todayInteractions': todayLogs.length,
        'mostSeenPerson': _getMostSeenPerson(knownFaces),
        'lastInteraction': todayLogs.isNotEmpty
            ? todayLogs.first.timestamp
            : null,
      };
    } catch (e) {
      throw 'Error fetching patient statistics: $e';
    }
  }

  KnownFaceModel? _getMostSeenPerson(List<KnownFaceModel> faces) {
    if (faces.isEmpty) return null;

    faces.sort((a, b) => b.interactionCount.compareTo(a.interactionCount));
    return faces.first;
  }
}
