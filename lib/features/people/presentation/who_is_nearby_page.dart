import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/people/data/nearby_venue_user_item_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';

/// Navbar destination: lists people currently checked in at surrounding venues.
class WhoIsNearbyPage extends StatefulWidget {
  const WhoIsNearbyPage({super.key});

  @override
  State<WhoIsNearbyPage> createState() => _WhoIsNearbyPageState();
}

class _WhoIsNearbyPageState extends State<WhoIsNearbyPage> {
  final MatchRepository _repo = MatchRepository();
  bool _loading = false;
  String? _error;
  List<NearbyVenueUserItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repo.listNearbyVenueUsers();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = items;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load nearby people right now.';
      });
    }
  }

  void _openProfile(NearbyVenueUserItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfilePreviewPage(
          checkinId: item.checkinId,
          venueId: item.venueId,
          userId: item.userId,
          userName: (item.fullName != null && item.fullName!.trim().isNotEmpty)
              ? item.fullName!.trim()
              : 'User',
          hintVenueId: item.venueId,
          hintVenueName: item.venueName,
          hintVenueType: item.venueType,
          hintVenuePhoto: item.venuePhoto,
          hideVenueInfo: true,
          fallbackBio: null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgTop = isDark
        ? const Color(0xFF121A2B)
        : theme.scaffoldBackgroundColor;
    final bgBottom = isDark
        ? const Color(0xFF0B0F17)
        : theme.scaffoldBackgroundColor;
    final colors = theme.colorScheme;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.grey[200];

    return Scaffold(
      backgroundColor: bgBottom,
      appBar: AppBar(
        backgroundColor: bgBottom,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          "Who's Nearby",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: borderColor, height: 1),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgTop, bgBottom],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? theme.colorScheme.primary.withValues(alpha: 0.12)
                      : theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? theme.colorScheme.primary.withValues(alpha: 0.35)
                        : theme.colorScheme.primary.withValues(alpha: 0.22),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(
                        alpha: isDark ? 0.18 : 0.08,
                      ),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.explore_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "People checking in at venues near yours — within about 300 m of where you checked in.",
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.88,
                          ),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : _items.isEmpty
                    ? RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.5,
                              child: const Center(
                                child: Text('No one nearby right now'),
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: GridView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: _items.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 1.5,
                                crossAxisSpacing: 1.5,
                                childAspectRatio: 0.7,
                              ),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return _NearbyUserCard(
                              item: item,
                              onTap: () => _openProfile(item),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NearbyUserCard extends StatelessWidget {
  final NearbyVenueUserItem item;
  final VoidCallback onTap;

  const _NearbyUserCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.displayPhoto;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl.isNotEmpty)
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => _placeholder(),
            )
          else
            _placeholder(),
          if (item.isFeaturedVideo)
            const Positioned.fill(
              child: Center(
                child: Icon(
                  Icons.play_circle_fill,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.72),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: Text(
              item.fullName?.trim().isNotEmpty == true
                  ? item.fullName!
                  : 'Unknown user',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 11,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: Colors.grey.shade300,
      child: const Icon(Icons.person, color: Colors.white70, size: 32),
    );
  }
}
