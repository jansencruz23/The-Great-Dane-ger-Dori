import 'package:cloud_firestore/cloud_firestore.dart';

class ActivityLogModel {
  final String id;
  final String patientId;
  final String personId;
  final String personName;
  final DateTime timestamp;
  final String? rawTranscript;
  final String? summary;
  final Duration? duration;
  final Map<String, dynamic>? metadata;

  ActivityLogModel({
    required this.id,
    required this.patientId,
    required this.personId,
    required this.personName,
    required this.timestamp,
    this.rawTranscript,
    this.summary,
    this.duration,
    this.metadata,
  });

  // Create ActivityLogModel from Firestore document
  factory ActivityLogModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return ActivityLogModel(
      id: doc.id,
      patientId: data['patientId'] ?? '',
      personId: data['personId'] ?? '',
      personName: data['personName'] ?? '',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      rawTranscript: data['rawTranscript'],
      summary: data['summary'],
      duration: data['durationSeconds'] != null
          ? Duration(seconds: data['durationSeconds'] as int)
          : null,
      metadata: data['metadata'] as Map<String, dynamic>?,
    );
  }

  // Convert ActivityLogModel to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'patientId': patientId,
      'personId': personId,
      'personName': personName,
      'timestamp': Timestamp.fromDate(timestamp),
      'rawTranscript': rawTranscript,
      'summary': summary,
      'durationSeconds': duration?.inSeconds,
      'metadata': metadata,
    };
  }

  // Copy with method
  ActivityLogModel copyWith({
    String? id,
    String? patientId,
    String? personId,
    String? personName,
    DateTime? timestamp,
    String? rawTranscript,
    String? summary,
    Duration? duration,
    Map<String, dynamic>? metadata,
  }) {
    return ActivityLogModel(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      personId: personId ?? this.personId,
      personName: personName ?? this.personName,
      timestamp: timestamp ?? this.timestamp,
      rawTranscript: rawTranscript ?? this.rawTranscript,
      summary: summary ?? this.summary,
      duration: duration ?? this.duration,
      metadata: metadata ?? this.metadata,
    );
  }

  // Check if log has summary
  bool get hasSummary => summary != null && summary!.isNotEmpty;

  // Check if log has transcript
  bool get hasTranscript => rawTranscript != null && rawTranscript!.isNotEmpty;

  // Get formatted duration
  String get formattedDuration {
    if (duration == null) return 'Unknown';

    final minutes = duration!.inMinutes;
    final seconds = duration!.inSeconds % 60;

    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
}
