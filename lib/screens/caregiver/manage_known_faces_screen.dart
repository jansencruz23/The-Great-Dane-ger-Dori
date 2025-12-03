import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/known_face_model.dart';
import '../../services/database_service.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import 'add_known_face_screen.dart';
import 'edit_known_face_screen.dart';

class ManageKnownFacesScreen extends StatefulWidget {
  final String patientId;
  final String patientName;

  const ManageKnownFacesScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<ManageKnownFacesScreen> createState() => _ManageKnownFacesScreenState();
}

class _ManageKnownFacesScreenState extends State<ManageKnownFacesScreen> {
  final DatabaseService _databaseService = DatabaseService();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _sortBy = 'name'; // 'name', 'recent', 'interactions'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Manage Known Faces\n${widget.patientName}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              _showSearchDialog();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Sort and Filter Bar
          _buildSortFilterBar(),

          // Known Faces List
          Expanded(
            child: StreamBuilder<List<KnownFaceModel>>(
              stream: _databaseService.streamKnownFaces(widget.patientId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: AppColors.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading faces',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var faces = snapshot.data!;

                // Apply search filter
                if (_searchQuery.isNotEmpty) {
                  faces = faces
                      .where(
                        (face) =>
                            face.name.toLowerCase().contains(
                              _searchQuery.toLowerCase(),
                            ) ||
                            face.relationship.toLowerCase().contains(
                              _searchQuery.toLowerCase(),
                            ),
                      )
                      .toList();
                }

                // Apply sorting
                faces = _sortFaces(faces);

                if (faces.isEmpty) {
                  return _buildEmptyState();
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    // Force rebuild by waiting a bit
                    await Future.delayed(const Duration(milliseconds: 500));
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: faces.length,
                    itemBuilder: (context, index) {
                      return _buildFaceCard(faces[index]);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (_) =>
                      AddKnownFaceScreen(patientId: widget.patientId),
                ),
              )
              .then((_) {
                // Stream will auto-update, no need to manually refresh
              });
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Face'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  Widget _buildSortFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          const Text(
            'Sort by:',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String>(
              value: _sortBy,
              isExpanded: true,
              underline: Container(),
              items: const [
                DropdownMenuItem(value: 'name', child: Text('Name (A-Z)')),
                DropdownMenuItem(
                  value: 'recent',
                  child: Text('Recently Added'),
                ),
                DropdownMenuItem(
                  value: 'interactions',
                  child: Text('Most Interactions'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _sortBy = value;
                  });
                }
              },
            ),
          ),
          if (_searchQuery.isNotEmpty) ...[
            const SizedBox(width: 8),
            Chip(
              label: Text('Search: $_searchQuery'),
              deleteIcon: const Icon(Icons.close, size: 18),
              onDeleted: () {
                setState(() {
                  _searchQuery = '';
                  _searchController.clear();
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFaceCard(KnownFaceModel face) {
    return Dismissible(
      key: Key(face.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) => _confirmDelete(face),
      background: Container(
        margin: const EdgeInsets.only(bottom: 16),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white, size: 32),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: _buildFaceImage(face),
          title: Text(
            face.name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                face.relationship,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.visibility,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${face.interactionCount} interactions',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  if (face.lastSeenAt != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatLastSeen(face.lastSeenAt!),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, color: AppColors.primary),
                onPressed: () => _editFace(face),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: AppColors.error),
                onPressed: () => _deleteFace(face),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFaceImage(KnownFaceModel face) {
    if (face.primaryImageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: face.primaryImageUrl!,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            width: 60,
            height: 60,
            color: Colors.grey.shade200,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (context, url, error) => _buildPlaceholderAvatar(face),
        ),
      );
    }

    return _buildPlaceholderAvatar(face);
  }

  Widget _buildPlaceholderAvatar(KnownFaceModel face) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Helpers.generateColorFromString(face.name),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          Helpers.getInitials(face.name),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _searchQuery.isNotEmpty ? Icons.search_off : Icons.face_outlined,
              size: 80,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty ? 'No faces found' : 'No known faces yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Try a different search term'
                  : 'Add your first known face to help with recognition',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (_searchQuery.isEmpty) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          AddKnownFaceScreen(patientId: widget.patientId),
                    ),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('Add First Face'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search Faces'),
        content: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: 'Enter name or relationship',
            prefixIcon: Icon(Icons.search),
          ),
          autofocus: true,
          onSubmitted: (value) {
            setState(() {
              _searchQuery = value.trim();
            });
            Navigator.of(context).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
              });
              Navigator.of(context).pop();
            },
            child: const Text('Clear'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _searchQuery = _searchController.text.trim();
              });
              Navigator.of(context).pop();
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  void _editFace(KnownFaceModel face) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => EditKnownFaceScreen(face: face)));
  }

  Future<bool> _confirmDelete(KnownFaceModel face) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Known Face?'),
        content: Text(
          'Are you sure you want to delete ${face.name}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _performDelete(face);
      return true;
    }

    return false;
  }

  void _deleteFace(KnownFaceModel face) async {
    final confirm = await _confirmDelete(face);
    if (!confirm) return;
  }

  Future<void> _performDelete(KnownFaceModel face) async {
    try {
      await _databaseService.deleteKnownFace(face.id);

      // Delete associated images from storage
      if (face.imageUrls != null) {
        for (final imageUrl in face.imageUrls!) {
          try {
            await _databaseService.deleteFaceImage(imageUrl);
          } catch (e) {
            print('Error deleting image: $e');
          }
        }
      }

      if (mounted) {
        Helpers.showSnackBar(context, '${face.name} deleted successfully');
      }
    } catch (e) {
      if (mounted) {
        Helpers.showSnackBar(context, 'Error deleting face: $e', isError: true);
      }
    }
  }

  List<KnownFaceModel> _sortFaces(List<KnownFaceModel> faces) {
    switch (_sortBy) {
      case 'name':
        faces.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'recent':
        faces.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case 'interactions':
        faces.sort((a, b) => b.interactionCount.compareTo(a.interactionCount));
        break;
    }
    return faces;
  }

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${lastSeen.day}/${lastSeen.month}/${lastSeen.year}';
    }
  }
}
