import 'package:cloud_firestore/cloud_firestore.dart';

class KnownFaceModel {
  final String id;
  final String patientId;
  final String name;
  final String relationship;
  final List<List<double>>
  embeddings; // Changed: now stores multiple embeddings
  final List<String>? imageUrls; // Changed: now stores multiple image URLs
  final String? notes;
  final DateTime createdAt;
  final DateTime? lastSeenAt;
  final int interactionCount;

  KnownFaceModel({
    required this.id,
    required this.patientId,
    required this.name,
    required this.relationship,
    required this.embeddings,
    this.imageUrls,
    this.notes,
    required this.createdAt,
    this.lastSeenAt,
    this.interactionCount = 0,
  });

  // Create KnownFaceModel from Firestore document
  factory KnownFaceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Handle both new (embeddingsMap) and old (embedding) formats
    List<List<double>> embeddingsList;

    if (data.containsKey('embeddingsMap')) {
      // New format: embeddings stored as map to avoid Firestore nested arrays
      final embeddingsMap = data['embeddingsMap'] as Map<String, dynamic>;
      embeddingsList = [];
      for (int i = 0; i < embeddingsMap.length; i++) {
        embeddingsList.add(List<double>.from(embeddingsMap['$i'] as List));
      }
    } else if (data.containsKey('embedding')) {
      // Old format: single embedding - convert to list format
      embeddingsList = [List<double>.from(data['embedding'] as List)];
    } else {
      embeddingsList = [];
    }

    // Handle both new (imageUrls) and old (imageUrl) formats
    List<String>? urls;
    if (data.containsKey('imageUrls')) {
      urls = List<String>.from(data['imageUrls'] as List);
    } else if (data.containsKey('imageUrl') && data['imageUrl'] != null) {
      urls = [data['imageUrl'] as String];
    }

    return KnownFaceModel(
      id: doc.id,
      patientId: data['patientId'] ?? '',
      name: data['name'] ?? '',
      relationship: data['relationship'] ?? '',
      embeddings: embeddingsList,
      imageUrls: urls,
      notes: data['notes'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      lastSeenAt: data['lastSeenAt'] != null
          ? (data['lastSeenAt'] as Timestamp).toDate()
          : null,
      interactionCount: data['interactionCount'] ?? 0,
    );
  }

  // Convert KnownFaceModel to Map for Firestore
  Map<String, dynamic> toMap() {
    // Convert List<List<double>> to Map<String, List<double>>
    // Firestore doesn't support nested arrays, so we use a map structure
    final embeddingsMap = <String, dynamic>{};
    for (int i = 0; i < embeddings.length; i++) {
      embeddingsMap['$i'] = embeddings[i];
    }

    return {
      'patientId': patientId,
      'name': name,
      'relationship': relationship,
      'embeddingsMap': embeddingsMap, // Store as map instead of nested array
      'imageUrls': imageUrls,
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastSeenAt': lastSeenAt != null ? Timestamp.fromDate(lastSeenAt!) : null,
      'interactionCount': interactionCount,
    };
  }

  // Copy with method
  KnownFaceModel copyWith({
    String? id,
    String? patientId,
    String? name,
    String? relationship,
    List<List<double>>? embeddings,
    List<String>? imageUrls,
    String? notes,
    DateTime? createdAt,
    DateTime? lastSeenAt,
    int? interactionCount,
  }) {
    return KnownFaceModel(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      name: name ?? this.name,
      relationship: relationship ?? this.relationship,
      embeddings: embeddings ?? this.embeddings,
      imageUrls: imageUrls ?? this.imageUrls,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      interactionCount: interactionCount ?? this.interactionCount,
    );
  }

  // Helper: Get all embeddings as a flat list for easy iteration
  List<List<double>> getAllEmbeddings() => embeddings;

  // Helper: Get primary image URL (first one)
  String? get primaryImageUrl =>
      imageUrls != null && imageUrls!.isNotEmpty ? imageUrls!.first : null;

  // Get display text for AR overlay
  String get displayName => name;
  String get displayRelationship =>
      relationship.isNotEmpty ? relationship : 'Known person';
}
