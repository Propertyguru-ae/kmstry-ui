import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/app_sheet.dart';
import 'package:kmstry_frontend/core/ui/branded_notice.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_detail_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_list_item.dart';
import 'package:kmstry_frontend/core/network/network_error.dart';
import 'package:kmstry_frontend/core/ui/empty_state_message.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';

enum _VenueSort { latest, earliest }

/// Sayfa `true` ile kapanırsa kullanıcı haritaya gitmek istemiştir. Bu sayfa
/// shell'in üstünde açıldığı için sekmeyi kendisi değil, açan sayfa değiştirir.
class FollowedVenuesPage extends StatefulWidget {
  const FollowedVenuesPage({super.key, this.repository});

  final VenueContextRepository? repository;

  @override
  State<FollowedVenuesPage> createState() => _FollowedVenuesPageState();
}

class _FollowedVenuesPageState extends State<FollowedVenuesPage> {
  late final VenueContextRepository _repository =
      widget.repository ?? VenueContextRepository();
  final TextEditingController _searchController = TextEditingController();

  List<Venue> _venues = const [];
  bool _loading = true;
  String? _error;
  bool _errorOffline = false;
  String _query = '';
  _VenueSort _sort = _VenueSort.latest;

  /// Bu oturumda takibi bırakılan mekanlar. Kart bir sonraki yüklemeye kadar
  /// listede kalır; yanlış dokunuş tek dokunuşla geri alınır, liste de kaymaz.
  final _unfollowedIds = <String>{};
  final _followRequests = <String>{};

  @override
  void initState() {
    super.initState();
    _loadVenues();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadVenues() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final venues = await _repository.getFollowedVenues();
      if (!mounted) return;
      setState(() {
        _venues = venues;
        // Liste artık sunucudan geldi; yalnız süren isteklerin durumu korunur.
        _unfollowedIds.removeWhere((id) => !_followRequests.contains(id));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final offline = isOfflineError(e);
      setState(() {
        _errorOffline = offline;
        _error = offline
            ? 'You\'re offline'
            : 'Followed venues could not be loaded.';
        _loading = false;
      });
    }
  }

  Future<void> _toggleFollow(Venue venue) async {
    final id = venue.id;
    if (!_followRequests.add(id)) return;
    final follow = _unfollowedIds.contains(id);
    setState(() {
      follow ? _unfollowedIds.remove(id) : _unfollowedIds.add(id);
    });
    try {
      follow
          ? await _repository.followVenue(id)
          : await _repository.unfollowVenue(id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        follow ? _unfollowedIds.add(id) : _unfollowedIds.remove(id);
      });
      showBrandedNotice(
        context,
        title: follow ? 'Could not follow venue' : 'Could not unfollow venue',
        message: 'Please try again.',
        tone: BrandedNoticeTone.error,
      );
    } finally {
      _followRequests.remove(id);
    }
  }

  List<Venue> get _visibleVenues {
    final normalized = _query.trim().toLowerCase();
    final filtered = normalized.isEmpty
        ? List<Venue>.from(_venues)
        : _venues.where((venue) {
            final haystack = [
              venue.name,
              venue.type,
              venue.city,
              venue.address,
            ].join(' ').toLowerCase();
            return haystack.contains(normalized);
          }).toList();

    switch (_sort) {
      case _VenueSort.latest:
        return filtered;
      case _VenueSort.earliest:
        return filtered.reversed.toList();
    }
  }

  String get _sortLabel {
    switch (_sort) {
      case _VenueSort.latest:
        return 'Latest';
      case _VenueSort.earliest:
        return 'Earliest';
    }
  }

  Future<void> _openSortSheet() async {
    final sort = await showAppSortSheet<_VenueSort>(
      context,
      selected: _sort,
      options: const [
        AppSortOption(
          value: _VenueSort.latest,
          label: 'Latest',
          subtitle: 'Newest follows first',
          icon: Icons.update_rounded,
        ),
        AppSortOption(
          value: _VenueSort.earliest,
          label: 'Earliest',
          subtitle: 'Oldest follows first',
          icon: Icons.history_rounded,
        ),
      ],
    );
    if (sort != null && mounted) setState(() => _sort = sort);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = isDark ? Colors.white : Colors.black;
    final visibleVenues = _visibleVenues;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        title: Text(
          'Venues',
          style: TextStyle(
            color: onSurface,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadVenues,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            // Liste boşken arama ve sıralamanın işlevi yok; CTA öne çıkar.
            if (_venues.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: _buildSearchField(isDark, onSurface),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
                child: Row(
                  children: [
                    Text(
                      'Sort by: ',
                      style: TextStyle(
                        color: onSurface.withValues(alpha: 0.6),
                        fontSize: 13.5,
                      ),
                    ),
                    Text(
                      _sortLabel,
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Sort',
                      icon: Icon(Icons.swap_vert_rounded, color: onSurface),
                      onPressed: _openSortSheet,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  '${visibleVenues.length} ${visibleVenues.length == 1 ? 'venue' : 'venues'}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
            if (_loading)
              Padding(
                padding: EdgeInsets.only(top: _venues.isEmpty ? 150 : 90),
                child: const Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _buildMessageState(
                icon: _errorOffline
                    ? Icons.wifi_off_rounded
                    : Icons.error_outline_rounded,
                title: _error!,
                subtitle: _errorOffline
                    ? 'Check your connection and pull to refresh.'
                    : 'Pull to refresh and try again.',
              )
            else if (_venues.isEmpty)
              _buildMessageState(
                icon: Icons.location_city_rounded,
                title: 'No followed venues yet',
                subtitle:
                    'Find venues on the map and follow them to see them here.',
                action: PrimaryButton(
                  label: 'Discover on map',
                  onPressed: () => Navigator.pop(context, true),
                ),
              )
            else if (visibleVenues.isEmpty)
              _buildMessageState(
                icon: Icons.search_off_rounded,
                title: 'No venues found',
                subtitle: 'Try another venue name.',
              )
            else
              for (final venue in visibleVenues)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: VenueListItem(
                    venue: venue,
                    showDescriptionInsteadOfCheckInPrompt: true,
                    headerAction: _FollowToggleButton(
                      venueName: venue.name,
                      following: !_unfollowedIds.contains(venue.id),
                      onTap: () => _toggleFollow(venue),
                    ),
                    onTap: (selectedVenue) async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VenueDetailPage(venue: selectedVenue),
                        ),
                      );
                      if (mounted) await _loadVenues();
                    },
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField(bool isDark, Color onSurface) {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value),
      textInputAction: TextInputAction.search,
      style: TextStyle(color: onSurface),
      decoration: InputDecoration(
        hintText: 'Search by name',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF1F3F5),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildMessageState({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: _venues.isEmpty ? 150 : 110, bottom: 32),
      child: EmptyStateMessage(
        icon: icon,
        title: title,
        subtitle: subtitle,
        action: action,
      ),
    );
  }
}

/// Takip ediliyorken sade, bırakılınca düz mavi. En az genişliği iki etiketi de
/// sığdırır, böylece normal yazı boyutunda durum değişince başlık kaymaz; büyük
/// yazı boyutunda ise genişliği sınırlıdır ve mekan adına yer bırakır.
class _FollowToggleButton extends StatelessWidget {
  const _FollowToggleButton({
    required this.venueName,
    required this.following,
    required this.onTap,
  });

  final String venueName;
  final bool following;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = !following || isDark
        ? Colors.white
        : AppColors.lightTextPrimary;
    final radius = BorderRadius.circular(12);
    return Semantics(
      button: true,
      label: following ? 'Unfollow $venueName' : 'Follow $venueName',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              color: following ? null : AppColors.blue,
              // İki durumda da kenarlık var; yoksa genişlik 2 piksel değişirdi.
              border: Border.all(
                color: !following
                    ? AppColors.blue
                    : isDark
                    ? Colors.white.withValues(alpha: 0.16)
                    : Colors.black.withValues(alpha: 0.12),
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 108,
                maxWidth: 134,
                minHeight: 36,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      following ? Icons.check_rounded : Icons.add_rounded,
                      size: 15,
                      color: foreground,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        following ? 'Following' : 'Follow',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
