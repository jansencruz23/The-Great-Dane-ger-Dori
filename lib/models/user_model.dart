import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String role;
  final String? caregiverId;
  final List<String>? patientIds;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  UserModel({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    this.caregiverId,
    this.patientIds,
    required this.createdAt,
    this.lastLoginAt,
  });

  // Create UserModel from Firestore document
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return UserModel(
      uid: doc.id,
      email: data['email'] ?? '',
      name: data['name'] ?? '',
      role: data['role'] ?? 'patient',
      caregiverId: data['caregiverId'],
      patientIds: data['patientIds'] != null
          ? List<String>.from(data['patientIds'])
          : null,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      lastLoginAt: data['lastLoginAt'] != null
          ? (data['lastLoginAt'] as Timestamp).toDate()
          : null,
    );
  }

  // Convert UserModel to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'name': name,
      'role': role,
      'caregiverId': caregiverId,
      'patientIds': patientIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLoginAt': lastLoginAt != null
          ? Timestamp.fromDate(lastLoginAt!)
          : null,
    };
  }

  // Copy with method for updating user
  UserModel copyWith({
    String? uid,
    String? email,
    String? name,
    String? role,
    String? caregiverId,
    List<String>? patientIds,
    DateTime? createdAt,
    DateTime? lastLoginAt,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      caregiverId: caregiverId ?? this.caregiverId,
      patientIds: patientIds ?? this.patientIds,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }

  bool get isCaregiver => role == 'caregiver';
  bool get isPatient => role == 'patient';
}
