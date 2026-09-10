import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/data/venue_follower_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';

/// Venue home'daki "Followers" KPI'ına basınca açılan liste.
/// Friends sayfasıyla aynı düzen: isimle arama + seçilebilir sıralama.
class VenueFollowersPage extends StatefulWidget {
  final String venueId;
  const VenueFollowersPage({super.key, required this.venueId});

  @override
  State<VenueFollowersPage> createState() => _VenueFollowersPageState();
}

class _VenueFollowersPageState extends State<VenueFollowersPage> {
  final _repo = VenueOwnerRepository();
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
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final followers = await _repo.getFollowers(widget.venueId);
      if (!mounted) return;
      setState(() {
        _all = followers;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load followers.';
        _loading = false;
      });
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

  void _openProfile(VenueFollower f) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfilePreviewPage(
          userId: f.userId,
          userName: f.fullName,
          userUsername: f.username,
          fallbackBio: (f.bio != null && f.bio!.trim().isNotEmpty)
              ? f.bio
              : null,
        ),
      ),
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
            onTap: () => _openProfile(f),
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
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: onSurface.withValues(alpha: 0.3),
            ),
          );
        },
      ),
    );
  }
}
