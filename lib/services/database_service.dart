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
      print('DEBUG getActivityLogs: patientId=$patientId, startDate=$startDate, endDate=$endDate, limit=$limit');
      
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

      print('DEBUG: Executing Firestore query...');
      final querySnapshot = await query.get();
      print('DEBUG: Query returned ${querySnapshot.docs.length} documents');

      final logs = querySnapshot.docs
          .map((doc) {
            print('DEBUG: Processing doc ${doc.id}');
            return ActivityLogModel.fromFirestore(doc);
          })
          .toList();

      print('DEBUG: Converted to ${logs.length} ActivityLogModel objects');
      return logs;
    } catch (e, stackTrace) {
      print('Error fetching activity logs: $e');
      print('Stack trace: $stackTrace');
      throw 'Error fetching activity logs: $e';
    }
  }

  // Simple method to get ALL summaries for a patient (no date filtering, no ordering)
  Future<List<Map<String, dynamic>>> getAllSummariesForPatient(String patientId) async {
    try {
      print('🔍 Fetching all summaries for patient: $patientId');
      
      final querySnapshot = await _firestore
          .collection(AppConstants.activityLogsCollection)
          .where('patientId', isEqualTo: patientId)
          .get();
      
      print('✅ Found ${querySnapshot.docs.length} activity logs');
      
      final summaries = <Map<String, dynamic>>[];
      
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        summaries.add({
          'id': doc.id,
          'personName': data['personName'],
          'summary': data['summary'],
          'timestamp': data['timestamp'],
          'rawTranscript': data['rawTranscript'],
        });
      }
      
      return summaries;
    } catch (e) {
      print('❌ Error fetching summaries: $e');
      return [];
    }
  }

  // DEBUG: Get ALL activity logs (no filter) for debugging
  Future<List<Map<String, dynamic>>> getAllActivityLogsForDebug() async {
    try {
      final querySnapshot = await _firestore
          .collection(AppConstants.activityLogsCollection)
          .get();
      
      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('Error fetching all activity logs: $e');
      return [];
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

  Future<List<ActivityLogModel>> getPersonActivityLogs(
    String patientId,
    String personId, {
    int limit = 3,
  }) async {
    try {
      final querySnapshot = await _firestore
          .collection(AppConstants.activityLogsCollection)
          .where('patientId', isEqualTo: patientId)
          .where('personId', isEqualTo: personId)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      return querySnapshot.docs
          .map((doc) => ActivityLogModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('Error fetching person activity logs: $e');
      return [];
    }
  }

  // Get activity logs grouped by date for day-by-day summaries
  Future<Map<String, List<ActivityLogModel>>> getActivityLogsByDate(
    String patientId, {
    int daysBack = 7,
  }) async {
    try {
      final now = DateTime.now();
      // Start from midnight of (daysBack) days ago
      final startDate = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: daysBack));

      print('═══════════════════════════════════════════════════════');
      print('DEBUG: FETCHING ACTIVITY LOGS BY DATE');
      print('═══════════════════════════════════════════════════════');
      print('Patient ID: $patientId');
      print('Start date: $startDate');
      print('Current date: $now');
      print('Days back: $daysBack');

      final logs = await getActivityLogs(
        patientId,
        startDate: startDate,
      );

      print('\n📊 TOTAL LOGS FETCHED: ${logs.length}');
      print('═══════════════════════════════════════════════════════\n');

      if (logs.isEmpty) {
        print('⚠️  NO LOGS FOUND IN FIREBASE!');
        print('   Check if:');
        print('   1. Patient ID matches: $patientId');
        print('   2. Logs exist in "activity_logs" collection');
        print('   3. Date range is correct');
        print('═══════════════════════════════════════════════════════\n');
      }

      // Print ALL summary values from Firebase
      for (var i = 0; i < logs.length; i++) {
        final log = logs[i];
        print('┌─────────────────────────────────────────────────────┐');
        print('│ LOG #${i + 1}');
        print('├─────────────────────────────────────────────────────┤');
        print('│ ID: ${log.id}');
        print('│ Patient ID: ${log.patientId}');
        print('│ Person ID: ${log.personId}');
        print('│ Person Name: ${log.personName}');
        print('│ Timestamp: ${log.timestamp}');
        print('│ Duration: ${log.duration?.inSeconds ?? 0} seconds');
        print('├─────────────────────────────────────────────────────┤');
        print('│ 📝 SUMMARY FROM FIREBASE:');
        print('│ ${log.summary ?? "(no summary)"}');
        print('├─────────────────────────────────────────────────────┤');
        print('│ 🎤 RAW TRANSCRIPT:');
        print('│ ${log.rawTranscript ?? "(no transcript)"}');
        print('└─────────────────────────────────────────────────────┘\n');
      }

      // Group logs by date
      final Map<String, List<ActivityLogModel>> logsByDate = {};

      for (final log in logs) {
        final dateKey = _getDateKey(log.timestamp);
        if (!logsByDate.containsKey(dateKey)) {
          logsByDate[dateKey] = [];
        }
        logsByDate[dateKey]!.add(log);
      }

      print('═══════════════════════════════════════════════════════');
      print('📅 GROUPED BY DATE: ${logsByDate.length} days');
      print('═══════════════════════════════════════════════════════');
      for (final entry in logsByDate.entries) {
        print('Date: ${entry.key} → ${entry.value.length} log(s)');
        for (var log in entry.value) {
          print('  - ${log.personName}: ${log.summary}');
        }
      }
      print('═══════════════════════════════════════════════════════\n');

      return logsByDate;
    } catch (e) {
      print('❌ ERROR fetching activity logs by date: $e');
      return {};
    }
  }

  // Helper: Get date key in YYYY-MM-DD format
  String _getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
