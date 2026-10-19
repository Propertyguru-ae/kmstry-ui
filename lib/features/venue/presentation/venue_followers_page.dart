import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/performance/performance_diagnostics.dart';
import 'package:kmstry_frontend/core/venue/visible_venue_read.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/core/ui/app_back_button.dart';
import 'package:kmstry_frontend/features/venue/data/venue_follower_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';

/// Venue home'daki "Followers" KPI'ına basınca açılan liste.
/// Friends sayfasıyla aynı düzen: isimle arama + seçilebilir sıralama.
/// Read-only: venue accounts must not enter personal profile actions here.
class VenueFollowersPage extends StatefulWidget {
  final String venueId;
  const VenueFollowersPage({super.key, required this.venueId, this.repository});
  final VenueOwnerRepository? repository;

  @override
  State<VenueFollowersPage> createState() => _VenueFollowersPageState();
}

class _VenueFollowersPageState extends State<VenueFollowersPage> {
  late final _repo = widget.repository ?? VenueOwnerRepository();
  int _revision = 0;
  bool _hasData = false;
  late final _read = VisibleVenueRead(
    isVisible: () => mounted,
    read: () => PerformanceDiagnostics.pageLoad(
      PerformancePage.followers,
      _readFollowers,
      isMounted: () => mounted,
    ),
  );
  final _searchController = TextEditingController();

  List<VenueFollower> _all = [];
  bool _loading = true;
  String? _error;
  String _query = '';

  /// 'latest' | 'earliest' | 'name'
  String _sort = 'latest';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _revision++;
    _read.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VenueFollowersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.venueId != oldWidget.venueId) {
      _revision++;
      _hasData = false;
      _all = [];
      _read.reset();
      _load();
    }
  }

  Future<void> _load() => _read.invalidate();

  Future<bool> _readFollowers() async {
    final revision = ++_revision;
    final venueId = widget.venueId;
    final session = PendingPublicMediaService.instance.sessionGeneration;
    bool current() =>
        mounted &&
        revision == _revision &&
        venueId == widget.venueId &&
        PendingPublicMediaService.instance.isCurrentSession(session);
    setState(() {
      _loading = !_hasData;
      _error = null;
    });
    try {
      final followers = await _repo.getFollowers(venueId);
      if (!current()) return false;
      setState(() {
        _all = followers;
        _hasData = true;
        _loading = false;
      });
      return true;
    } catch (error) {
      if (!current()) return false;
      setState(() {
        final denied =
            error is ApiException && [401, 403, 404].contains(error.statusCode);
        if (denied) {
          _all = [];
          _hasData = false;
        }
        if (!_hasData) _error = 'Could not load followers.';
        _loading = false;
      });
      return false;
    }
  }

  List<VenueFollower> get _filtered {
    final q = _query.trim().toLowerCase();
    var list = q.isEmpty
        ? List<VenueFollower>.from(_all)
        : _all
              .where(
                (f) =>
                    f.fullName.toLowerCase().contains(q) ||
                    (f.username ?? '').toLowerCase().contains(q),
              )
              .toList();
    switch (_sort) {
      case 'earliest':
        // Backend 'latest' (created_at DESC) döner → tersi 'earliest'.
        list = list.reversed.toList();
        break;
      case 'name':
        list.sort(
          (a, b) =>
              a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
        );
        break;
      case 'latest':
      default:
        break;
    }
    return list;
  }

  String get _sortLabel => switch (_sort) {
    'earliest' => 'Earliest',
    'name' => 'Name (A–Z)',
    _ => 'Latest',
  };

  Future<void> _openSortSheet() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark
          ? const Color(0xFF161C28)
          : theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        Widget option(String key, String label) {
          final selected = _sort == key;
          return ListTile(
            title: Text(label),
            trailing: selected
                ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
                : null,
            onTap: () {
              setState(() => _sort = key);
              Navigator.pop(ctx);
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Sort by',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              option('latest', 'Latest'),
              option('earliest', 'Earliest'),
              option('name', 'Name (A–Z)'),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        // Uygulama genelindeki geri butonu (Analytics vb. ile aynı).
        leadingWidth: 60,
        leading: const Padding(
          padding: EdgeInsets.only(left: 14),
          child: AppBackButton(),
        ),
        title: Text(
          'Followers',
          style: TextStyle(
            color: onSurface,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(color: onSurface),
              decoration: InputDecoration(
                hintText: 'Search by name',
                prefixIcon: const Icon(Icons.search_rounded),
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
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
            ),
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
          Expanded(child: _buildBody(theme, isDark, onSurface)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, bool isDark, Color onSurface) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: theme.colorScheme.primary),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: onSurface)),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty
              ? 'No followers yet.'
              : 'No followers match "$_query".',
          style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: theme.colorScheme.primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: items.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: onSurface.withValues(alpha: 0.06)),
        itemBuilder: (context, index) {
          final f = items[index];
          final name = f.fullName.isNotEmpty ? f.fullName : (f.username ?? '');
          final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
          final avatarUrl = f.photo;
          final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: theme.colorScheme.primary.withValues(
                alpha: 0.12,
              ),
              foregroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
              child: hasAvatar
                  ? null
                  : Text(
                      initial,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ),
            ),
            title: Text(
              name.isEmpty ? 'Unknown' : name,
              style: TextStyle(
                color: onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            subtitle: (f.username != null && f.username!.isNotEmpty)
                ? Text(
                    '@${f.username}',
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.55),
                      fontSize: 12.5,
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }
}
