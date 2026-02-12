import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/chat/data/chat_list_item_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_repository.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:kmstry_frontend/features/venue/presentation/moments_viewer_page.dart';

enum ProfileActionState {
  showActions,
  incomingInterested,
  waitingResponse,
  proactivePass,
  reactivePass,
  matched,
}

class ProfilePreviewPage extends StatefulWidget {
  final String checkinId;
  final String venueId;

  const ProfilePreviewPage({
    super.key,
    required this.checkinId,
    required this.venueId,
  });

  @override
  State<ProfilePreviewPage> createState() => _ProfilePreviewPageState();
}

class _ProfilePreviewPageState extends State<ProfilePreviewPage> {
  final _repo = CheckinRepository();
  final _chatRepo = ChatRepository();
  bool _isVibeExpanded = false;
  bool _isVibeOverflowing = false;

  CheckinProfile? _profile;
  bool _loading = true;
  ProfileActionState? _actionState;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  bool _checkTextOverflow(String text, double maxWidth, TextStyle style) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 2,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    return textPainter.didExceedMaxLines;
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _repo.getCheckinProfile(widget.checkinId);
      if (!mounted) return;
      // 🔍 DEBUG: chat geliyor mu?
      debugPrint('🧪 PROFILE DEBUG');
      debugPrint('isMatched: ${profile.isMatched}');
      debugPrint('chatId: ${profile.chatId}');

      setState(() {
        _profile = profile;
        _actionState = _determineActionState(profile);
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ profile load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  ProfileActionState _determineActionState(CheckinProfile profile) {
    final myAction = profile.myActionAtThisVenue;
    final theirAction = profile.theirActionAtThisVenue;

    // 1) GLOBAL MATCH
    if (profile.isMatched) {
      return ProfileActionState.matched;
    }

    // 2) THEY SENT INTERESTED
    if (theirAction == 'interested') {
      if (myAction == 'interested') {
        return ProfileActionState.matched;
      }

      if (myAction == 'pass') {
        // Check timestamps to determine if pass was sent BEFORE or AFTER interested
        final myActionTime = profile.myActionCreatedAt;
        final theirActionTime = profile.theirActionCreatedAt;

        // Only hard lock if pass was sent AFTER receiving interested
        if (myActionTime != null &&
            theirActionTime != null &&
            myActionTime.isAfter(theirActionTime)) {
          // Reactive pass: I sent pass AFTER they sent interested (hard lock)
          return ProfileActionState.reactivePass;
        }

        // Proactive pass: I sent pass BEFORE they sent interested
        // Show incomingInterested so user can respond
        return ProfileActionState.incomingInterested;
      }

      return ProfileActionState.incomingInterested;
    }

    // 3) I SENT INTERESTED, WAITING
    if (myAction == 'interested') {
      // If they responded with PASS AFTER my interested → hard reject
      if (theirAction == 'pass' &&
          profile.theirActionCreatedAt != null &&
          profile.myActionCreatedAt != null &&
          profile.theirActionCreatedAt!.isAfter(profile.myActionCreatedAt!)) {
        return ProfileActionState.reactivePass;
      }

      // Otherwise still waiting
      return ProfileActionState.waitingResponse;
    }

    // 4) I SENT PASS (SOFT)
    if (myAction == 'pass') {
      return ProfileActionState.proactivePass;
    }

    // 5) NOTHING YET
    return ProfileActionState.showActions;
  }

  Future<void> _handleAction(String action) async {
    if (_profile == null) return;

    // Only allow actions in showActions or incomingInterested states
    if (_actionState != ProfileActionState.showActions &&
        _actionState != ProfileActionState.incomingInterested) {
      return;
    }

    try {
      await _repo.sendFeedAction(
        targetUserId: _profile!.user.id,
        venueId: widget.venueId,
        checkinId: widget.checkinId,
        action: action,
      );
      if (!mounted) return;

      // Reload profile to get updated state
      await _loadProfile();
    } catch (e) {
      debugPrint('❌ feed action error: $e');
    }
  }

  Future<void> _openChat() async {
    final profile = _profile;
    if (profile == null) return;

    debugPrint('🧪 OPEN CHAT → chatId = ${profile.chatId}');

    if (profile.chatId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ChatId gelmedi (backend kontrol et)')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessageDetailPage(
          chatId: profile.chatId!,
          otherUserId: profile.user.id,
          otherName: profile.user.fullName,
          otherPhotoUrl: profile.photos.first.url,
        ),
      ),
    );
  }

  void _showNoChatYetSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Henüz mesaj yok. Önce mesajlar listesinden sohbet başlatın.',
        ),
        duration: Duration(seconds: 4),
      ),
    );
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

    final featuredPhoto = _profile!.photos.firstWhere(
      (p) => p.isFeatured,
      orElse: () => _profile!.photos.first,
    );

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
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final vibeText = _profile!.checkin.vibe!;
                        const style = TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        );

                        _isVibeOverflowing = _checkTextOverflow(
                          vibeText,
                          constraints.maxWidth,
                          style,
                        );

                        return AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                vibeText,
                                style: style,
                                maxLines: _isVibeExpanded ? null : 2,
                                overflow: _isVibeExpanded
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                              ),

                              if (_isVibeOverflowing)
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _isVibeExpanded = !_isVibeExpanded;
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      _isVibeExpanded ? 'See less' : 'See more',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Builder(
                      builder: (context) {
                        final count = moments.length;

                        // 🔥 1 FOTO
                        if (count == 1) {
                          return _buildMomentImage(
                            moments.first,
                            width: double.infinity,
                            height: 160,
                            initialIndex: 1,
                          );
                        }

                        // 🔥 2 FOTO
                        if (count == 2) {
                          return Row(
                            children: [
                              Expanded(
                                child: _buildMomentImage(
                                  moments[0],
                                  height: 140,
                                  initialIndex: 1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildMomentImage(
                                  moments[1],
                                  height: 140,
                                  initialIndex: 2,
                                ),
                              ),
                            ],
                          );
                        }

                        // 🔥 3+ FOTO (scroll)
                        return SizedBox(
                          height: 90,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: count,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, index) {
                              return _buildMomentImage(
                                moments[index],
                                width: 70,
                                height: 90,
                                initialIndex: index + 1,
                              );
                            },
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
          if (_actionState != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildActionBarContainer(),
            ),
        ],
      ),
    );
  }

  Widget _buildActionBarContainer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.85)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Banner for incomingInterested
          if (_actionState == ProfileActionState.incomingInterested)
            Container(
              padding: const EdgeInsets.only(bottom: 12),
              child: const Center(
                child: Text(
                  'Kmstry you! What do you think?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

          // Text for proactivePass
          if (_actionState == ProfileActionState.proactivePass)
            Container(
              padding: const EdgeInsets.only(bottom: 12),
              child: const Center(
                child: Text(
                  'Already no Kmstry',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
            ),

          // Action buttons/content
          _buildActionBar(),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    switch (_actionState!) {
      case ProfileActionState.incomingInterested:
      case ProfileActionState.showActions:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _handleAction('interested'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white),
                ),
                child: const Text('Kmstry 👋'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _handleAction('pass'),
                child: const Text('Not Kmstry'),
              ),
            ),
          ],
        );

      case ProfileActionState.proactivePass:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _handleAction('interested'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white),
                ),
                child: const Text('Kmstry 👋'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: null, // Disabled
                child: const Text('Not Kmstry'),
              ),
            ),
          ],
        );

      case ProfileActionState.waitingResponse:
        return const Center(
          child: Text(
            'Waiting response',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        );

      case ProfileActionState.reactivePass:
        return const Center(
          child: Text(
            'No Kmstry already',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        );

      case ProfileActionState.matched:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _openChat,
            child: const Text('Message'),
          ),
        );
    }
  }

  Widget _buildMomentImage(
    photo, {
    double? width,
    required double height,
    required int initialIndex,
  }) {
    return GestureDetector(
      onTap: () {
        final featuredPhoto = _profile!.photos.firstWhere((p) => p.isFeatured);
        final moments = _profile!.photos.where((p) => !p.isFeatured).toList();

        final photosForViewer = [featuredPhoto, ...moments];

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MomentsViewerPage(
              photos: photosForViewer,
              initialIndex: initialIndex,
              allowFeature: false, // 👈 BURASI ÖNEMLİ
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          photo.url,
          width: width,
          height: height,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
