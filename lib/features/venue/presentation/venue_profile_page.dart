import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/profile/presentation/profile_settings_page.dart';

class VenueProfilePage extends StatefulWidget {
  final String? activeVenueName;
  final List<String>? venueNames;

  const VenueProfilePage({
    super.key,
    this.activeVenueName,
    this.venueNames,
  });

  @override
  State<VenueProfilePage> createState() => _VenueProfilePageState();
}

class _VenueProfilePageState extends State<VenueProfilePage> {
  static const List<String> _venuePlaceholderPhotos = [
    'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4',
    'https://images.unsplash.com/photo-1514933651103-005eec06c04b',
    'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085',
    'https://images.unsplash.com/photo-1509042239860-f550ce710b93',
  ];

  bool _loading = true;
  String _activeVenueName = 'Venue account';
  List<String> _venueNames = const [];

  @override
  void initState() {
    super.initState();
    _loadVenueProfile();
  }

  Future<void> _loadVenueProfile() async {
    try {
      final me = await AuthRepository().getMe();
      final context = MeContextModel.fromMe(me);
      final names = widget.venueNames ?? context.memberVenues.map((v) => v.name).toList();
      String? activeName = widget.activeVenueName;

      if ((activeName == null || activeName.isEmpty) &&
          context.activeVenueId != null) {
        for (final venue in context.memberVenues) {
          if (venue.id == context.activeVenueId) {
            activeName = venue.name;
            break;
          }
        }
      }
      activeName ??= names.isNotEmpty ? names.first : 'Venue account';

      if (!mounted) return;
      setState(() {
        _activeVenueName = activeName!;
        _venueNames = names;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileSettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backdrop = _venuePlaceholderPhotos[
        _activeVenueName.hashCode.abs() % _venuePlaceholderPhotos.length];

    if (_loading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.network(backdrop, fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.8),
                    Colors.black.withValues(alpha: 0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      onPressed: _openSettings,
                      icon: const Icon(Icons.settings_outlined, color: Colors.white),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _activeVenueName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (_venueNames.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _venueNames.join('  •  '),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Add story'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
