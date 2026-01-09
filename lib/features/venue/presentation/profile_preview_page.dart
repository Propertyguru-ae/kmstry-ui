import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/moments_viewer_page.dart';

class ProfilePreviewPage extends StatefulWidget {
  final String checkinId;

  const ProfilePreviewPage({super.key, required this.checkinId});

  @override
  State<ProfilePreviewPage> createState() => _ProfilePreviewPageState();
}

class _ProfilePreviewPageState extends State<ProfilePreviewPage> {
  final _repo = CheckinRepository();

  CheckinProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _repo.getCheckinProfile(widget.checkinId);
      if (!mounted) return;

      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ profile load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    /// LOADING STATE
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    /// ERROR / EMPTY STATE
    if (_profile == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Profile unavailable',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final featuredPhoto = _profile!.photos.firstWhere((p) => p.isFeatured);

    final moments = _profile!.photos.where((p) => !p.isFeatured).toList();

    return Scaffold(
      body: Stack(
        children: [
          /// HERO IMAGE (FEATURED PHOTO)
          Positioned.fill(
            child: Image.network(
              featuredPhoto.url,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;

                return Container(
                  color: Colors.black,
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                color: Colors.black,
                child: const Icon(
                  Icons.person,
                  color: Colors.white70,
                  size: 48,
                ),
              ),
            ),
          ),

          /// DARK GRADIENT
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
            ),
          ),

          /// CONTENT
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// BACK
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),

                const Spacer(),

                /// NAME
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _profile!.user.fullName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                /// ONLINE STATUS
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Online now',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),

                const SizedBox(height: 12),

                /// VIBE (REAL DATA)
                if (_profile!.checkin.vibe != null &&
                    _profile!.checkin.vibe!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _profile!.checkin.vibe!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                /// RECENT MOMENTS TITLE
                if (moments.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Recent moments',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                const SizedBox(height: 8),

                /// RECENT MOMENTS LIST
                if (moments.isNotEmpty)
                  SizedBox(
                    height: 90,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: moments.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final photo = moments[index];

                        return GestureDetector(
                          onTap: () {
                            final imagesForViewer = [
                              featuredPhoto.url,
                              ...moments.map((p) => p.url),
                            ];

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MomentsViewerPage(
                                  images: imagesForViewer,
                                  initialIndex: index + 1,
                                ),
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              photo.url,
                              width: 70,
                              height: 90,
                              fit: BoxFit.cover,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;

                                    return Container(
                                      width: 70,
                                      height: 90,
                                      color: Colors.grey.shade300,
                                      child: const Center(
                                        child: SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 70,
                                  height: 90,
                                  color: Colors.grey.shade400,
                                  child: const Icon(
                                    Icons.broken_image,
                                    color: Colors.white70,
                                    size: 20,
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 90),
              ],
            ),
          ),

          /// ACTION BAR
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.85)),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                      ),
                      child: const Text('Wave 👋'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {},
                      child: const Text('Interested ❤️'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
