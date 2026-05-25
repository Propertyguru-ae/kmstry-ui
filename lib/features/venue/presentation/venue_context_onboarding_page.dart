import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_pending_page.dart';

/// Venue kayit akisi: mekan arama -> secim -> sahiplik notu -> talep gonder.
/// [fromAppShell] true ise (uygulama icinden acilmis) claim sonrasi VenuePendingPage'e
/// push yapar (back tusuyla geri donulebilir). false ise auth_gate'e yonlendirir.
class VenueContextOnboardingPage extends StatefulWidget {
  final bool fromAppShell;
  const VenueContextOnboardingPage({super.key, this.fromAppShell = false});

  @override
  State<VenueContextOnboardingPage> createState() =>
      _VenueContextOnboardingPageState();
}

class _VenueContextOnboardingPageState
    extends State<VenueContextOnboardingPage> {
  final _repo = VenueRepository();
  final _searchCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  Timer? _debounce;

  List<Venue> _results = [];
  Venue? _selected;
  bool _searching = false;
  bool _claiming = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim();
    if (_selected != null) {
      setState(() => _selected = null);
    }
    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 380), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      // Konum bilgisi olmadan sadece metin araması — backend text-only Google search yapar.
      final venues = await _repo.searchVenues(query: q);
      if (!mounted) return;
      setState(() => _results = venues);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Search failed. Please try again.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _onClaimSuccess() {
    if (widget.fromAppShell) {
      // Uygulama içinden açıldı — VenuePendingPage'e push yap, geri dönülebilir.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const VenuePendingPage()),
      );
    } else {
      // Kayıt akışından geldi — auth_gate yönlendirsin.
      Navigator.of(context).pushReplacementNamed(AuthRoutes.authGate);
    }
  }

  Future<void> _submitClaim() async {
    final venue = _selected;
    final note = _noteCtrl.text.trim();
    if (venue == null) return;
    if (note.isEmpty) {
      setState(() => _error = 'Please add a brief note about your ownership.');
      return;
    }

    setState(() {
      _claiming = true;
      _error = null;
    });

    try {
      final dbVenueId = await _repo.ensureVenueDbId(venue.id);
      await _repo.claimVenue(venueId: dbVenueId, ownerNote: note);
      if (!mounted) return;
      _onClaimSuccess();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      if (msg.contains('already pending') || msg.contains('already an active')) {
        _onClaimSuccess();
        return;
      }
      setState(() {
        _error = 'Could not submit your claim. Please try again.';
        _claiming = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? Theme.of(context).scaffoldBackgroundColor : Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _selected == null
                  ? _buildSearchView(colors, isDark)
                  : _buildClaimView(colors, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchView(ColorScheme colors, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Text(
            'Find your venue',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Search by venue name or city to get started.',
            style: TextStyle(
              fontSize: 15,
              color: colors.onSurface.withValues(alpha: 0.60),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            decoration: InputDecoration(
              prefixIcon: _searching
                  ? Transform.scale(
                      scale: 0.55,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: colors.primary,
                      ),
                    )
                  : Icon(Icons.search, color: colors.onSurface.withValues(alpha: 0.55)),
              hintText: 'Search venues...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: colors.error, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: _results.isEmpty && !_searching
                ? Center(
                    child: Text(
                      _searchCtrl.text.isEmpty
                          ? 'Type to search for your venue.'
                          : 'No venues found. Try a different name.',
                      style: TextStyle(
                        color: colors.onSurface.withValues(alpha: 0.45),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final venue = _results[i];
                      return ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: venue.photoUrl.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    venue.photoUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Icon(
                                      Icons.store_mall_directory_outlined,
                                      color: colors.primary,
                                      size: 22,
                                    ),
                                  ),
                                )
                              : Icon(
                                  Icons.store_mall_directory_outlined,
                                  color: colors.primary,
                                  size: 22,
                                ),
                        ),
                        title: Text(
                          venue.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: venue.address.isNotEmpty
                            ? Text(
                                venue.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurface.withValues(alpha: 0.55),
                                ),
                              )
                            : null,
                        onTap: () {
                          setState(() {
                            _selected = venue;
                            _error = null;
                          });
                        },
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              // TODO: "My venue is not listed" flow (future sprint)
            },
            child: const Text("My venue isn't listed"),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildClaimView(ColorScheme colors, bool isDark) {
    final venue = _selected!;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Text(
            'Claim this venue',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 20),

          // Venue preview card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? colors.surface
                  : colors.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colors.outline.withValues(alpha: 0.28),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: venue.photoUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            venue.photoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              Icons.store_mall_directory_outlined,
                              color: colors.primary,
                              size: 26,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.store_mall_directory_outlined,
                          color: colors.primary,
                          size: 26,
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        venue.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (venue.address.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          venue.address,
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.onSurface.withValues(alpha: 0.58),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _selected = null;
                    _noteCtrl.clear();
                    _error = null;
                  }),
                  child: const Text('Change'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          Text(
            'Tell us about your ownership',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A brief note helps our team verify your claim faster.',
            style: TextStyle(
              fontSize: 14,
              color: colors.onSurface.withValues(alpha: 0.60),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(
              hintText:
                  'e.g. I am the manager of this venue. You can verify by...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: colors.error, fontSize: 13)),
          ],

          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _claiming ? null : _submitClaim,
              child: _claiming
                  ? CircularProgressIndicator(color: colors.onPrimary)
                  : const Text('Submit Claim'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Our team will review your claim and notify you by email once approved.',
            style: TextStyle(
              fontSize: 12,
              color: colors.onSurface.withValues(alpha: 0.50),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
