import 'package:flutter/material.dart';
import '../../checkin/data/checkin_repository.dart';
import '../../checkin/data/checkin_profile_model.dart';

class MomentsViewerPage extends StatefulWidget {
  final List<CheckinProfilePhoto> photos;
  final int initialIndex;
  final bool allowFeature;

  const MomentsViewerPage({
    super.key,
    required this.photos,
    required this.initialIndex,
    this.allowFeature = false,
  });

  @override
  State<MomentsViewerPage> createState() => _MomentsViewerPageState();
}

class _MomentsViewerPageState extends State<MomentsViewerPage> {
  late PageController _controller;
  late int _currentIndex;
  final CheckinRepository _repo = CheckinRepository();
  bool _loading = false;
  late List<CheckinProfilePhoto> _photos;
  bool _hasChanged = false;

  @override
  void initState() {
    super.initState();
    _photos = List.from(widget.photos);
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  Future<void> _setFeatured() async {
    setState(() => _loading = true);

    try {
      final selectedPhoto = _photos[_currentIndex];

      await _repo.setFeaturedPhoto(selectedPhoto.id);

      if (!mounted) return;

      setState(() {
        _photos = _photos.map((photo) {
          return CheckinProfilePhoto(
            id: photo.id,
            url: photo.url,
            isFeatured: photo.id == selectedPhoto.id,
          );
        }).toList();
        _hasChanged = true;
      });
    } catch (e) {
      print("Feature error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to set featured photo")),
      );
    }

    if (mounted) setState(() => _loading = false);
  }

  Widget _buildFeatureButton(CheckinProfilePhoto currentPhoto) {
    return GestureDetector(
      onTap: currentPhoto.isFeatured || _loading ? null : _setFeatured,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
        ),
        child: _loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(
                Icons.star,
                color: currentPhoto.isFeatured ? Colors.amber : Colors.white,
                size: 26,
              ),
      ),
    );
  }

  Widget _buildDeleteButton(CheckinProfilePhoto currentPhoto) {
    return GestureDetector(
      onTap: _loading ? null : () => _confirmDelete(currentPhoto),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.delete_outline,
          color: Colors.redAccent,
          size: 26,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(CheckinProfilePhoto photo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black,
          title: const Text(
            "Delete photo?",
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            "This action cannot be undone.",
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Delete", style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await _deletePhoto(photo);
    }
  }

  Future<void> _deletePhoto(CheckinProfilePhoto photo) async {
    setState(() => _loading = true);

    try {
      await _repo.deletePhoto(photo.id);

      if (!mounted) return;

      Navigator.pop(context, true); // profile reload
    } catch (e) {
      print("Delete error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to delete photo")));
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final currentPhoto = _photos[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemCount: _photos.length,
            itemBuilder: (context, index) {
              return Center(
                child: InteractiveViewer(
                  child: Image.network(_photos[index].url, fit: BoxFit.contain),
                ),
              );
            },
          ),

          /// CLOSE BUTTON
          /// if (widget.allowFeature)
          Positioned(
            top: 40,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context, _hasChanged),
            ),
          ),

          /// ⭐ FEATURE BUTTON
          /// BOTTOM ACTIONS (sadece izin varsa)
          if (widget.allowFeature)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // ⭐ FEATURE
                  _buildFeatureButton(currentPhoto),

                  // 🗑 DELETE
                  _buildDeleteButton(currentPhoto),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
