import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kmstry_frontend/core/ui/app_logo.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/profile/presentation/account_settings_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/settings_activity_page.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_stats_model.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/name_dob_onboarding_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_context_onboarding_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_edit_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_team_page.dart';
import 'package:kmstry_frontend/features/venue_stories/presentation/add_venue_story_page.dart';
import 'package:kmstry_frontend/features/venue_stories/presentation/venue_story_tray.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/add_venue_event_page.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/venue_events_list_page.dart';

class VenueProfilePage extends StatefulWidget {
  final String? activeVenueName;
  final List<String>? venueNames;
  final String? venueId;

  const VenueProfilePage({
    super.key,
    this.activeVenueName,
    this.venueNames,
    this.venueId,
  });

  @override
  State<VenueProfilePage> createState() => _VenueProfilePageState();
}

class _VenueProfilePageState extends State<VenueProfilePage> {
  bool _loading = true;
  VenueOwnerStatsVenue? _venue;
  VenueMemberRole _venueRole = VenueMemberRole.staff;
  MeContextModel? _meContext;
  bool _uploadingPhoto = false;
  bool _updatingType = false;
  bool _uploadingStory = false;

  @override
  void initState() {
    super.initState();
    _loadVenueProfile();
  }

  Future<void> _loadVenueProfile() async {
    setState(() => _loading = true);
    try {
      final me = await AuthRepository().getMe();
      final ctx = MeContextModel.fromMe(me);

      String? venueId = widget.venueId;
      if (venueId == null || venueId.isEmpty) {
        venueId = ctx.activeVenueId;
        if ((venueId == null || venueId.isEmpty) &&
            ctx.memberVenues.isNotEmpty) {
          venueId = ctx.memberVenues.first.id;
        }
      }

      if (venueId != null && venueId.isNotEmpty) {
        final memberVenue = ctx.memberVenues
            .where((v) => v.id == venueId)
            .firstOrNull;
        final resolvedRole = VenueMemberRoleExt.fromApi(
          memberVenue?.role ?? 'STAFF',
        );

        final response = await VenueOwnerRepository().getOwnerStats(venueId);
        if (!mounted) return;
        setState(() {
          _meContext = ctx;
          _venue = response.venue;
          _venueRole = resolvedRole;
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _meContext = ctx;
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    final venueId = _venue?.id;
    if (venueId == null || _uploadingPhoto) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingPhoto = true);
    try {
      final updated = await VenueOwnerRepository().uploadVenuePhoto(
        venueId,
        File(picked.path),
      );
      if (mounted) setState(() => _venue = updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Photo upload failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  static const _venueTypes = ['bar', 'club', 'cafe', 'lounge', 'restaurant'];

  static const _typeLabels = {
    'bar': 'Bar',
    'club': 'Club',
    'cafe': 'Café',
    'lounge': 'Lounge',
    'restaurant': 'Restaurant',
  };

  static const _typeIcons = {
    'bar': Icons.local_bar_outlined,
    'club': Icons.nightlife_outlined,
    'cafe': Icons.local_cafe_outlined,
    'lounge': Icons.weekend_outlined,
    'restaurant': Icons.restaurant_outlined,
  };

  Future<void> _showTypePicker() async {
    final venueId = _venue?.id;
    if (venueId == null || _updatingType) return;

    final colors = Theme.of(context).colorScheme;
    final current = _venue?.type?.toLowerCase();

    await showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 16, bottom: 12),
              decoration: BoxDecoration(
                color: colors.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                'Venue Type',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ),
            ..._venueTypes.map((t) {
              final isSelected = t == current;
              return ListTile(
                leading: Icon(
                  _typeIcons[t],
                  color: isSelected ? colors.primary : colors.onSurface.withValues(alpha: 0.7),
                ),
                title: Text(
                  _typeLabels[t]!,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? colors.primary : colors.onSurface,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Icons.check_circle, color: colors.primary)
                    : null,
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  if (isSelected) return;
                  setState(() => _updatingType = true);
                  try {
                    final updated = await VenueOwnerRepository().updateVenue(
                      venueId,
                      type: t,
                    );
                    if (mounted) setState(() => _venue = updated);
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not update venue type.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _updatingType = false);
                  }
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openEdit() async {
    final venue = _venue;
    if (venue == null) return;
    final updated = await Navigator.push<VenueOwnerStatsVenue>(
      context,
      MaterialPageRoute(builder: (_) => VenueEditPage(venue: venue)),
    );
    if (updated != null && mounted) setState(() => _venue = updated);
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsActivityPage()),
    );
  }

  Future<void> _openTeam() async {
    final venueId = _venue?.id;
    if (venueId == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VenueTeamPage(venueId: venueId, callerRole: _venueRole),
      ),
    );
  }

  void _showPhotoViewer(String url) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => _PhotoViewer(url: url),
      ),
    );
  }

  Future<void> _openEventsList() async {
    final venueId = _venue?.id;
    if (venueId == null) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VenueEventsListPage(
          venueId: venueId,
          events: _venue?.upcomingEvents ?? const [],
          onRefresh: _loadVenueProfile,
        ),
      ),
    );
    if (result == true && mounted) _loadVenueProfile();
  }

  Future<void> _openAddEvent() async {
    final venueId = _venue?.id;
    if (venueId == null) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddVenueEventPage(venueId: venueId)),
    );
    if (result == true && mounted) _loadVenueProfile();
  }

  Future<void> _openAddStory() async {
    final venueId = _venue?.id;
    if (venueId == null || _uploadingStory) return;
    setState(() => _uploadingStory = true);
    try {
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => AddVenueStoryPage(venueId: venueId),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingStory = false);
    }
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature coming soon'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String get _venueLabel {
    final name = _venue?.name ?? widget.activeVenueName ?? '';
    const maxLen = 22;
    return name.length > maxLen ? '${name.substring(0, maxLen)}...' : name;
  }

  bool get _hasMultipleAccounts {
    final ctx = _meContext;
    if (ctx == null) return false;
    final venueCount = ctx.memberVenues.where((v) => v.isActive).length;
    return (ctx.hasPersonalProfile ? 1 : 0) + venueCount > 1;
  }

  Widget _buildAppBarTitle(ThemeData theme, bool isDark) {
    return GestureDetector(
      onTap: () => _showAccountPicker(context),
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _venueLabel,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 22,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ],
      ),
    );
  }

  void _showAccountPicker(BuildContext context) {
    final meCtx = _meContext;
    if (meCtx == null) return;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final activeVenues = meCtx.memberVenues.where((v) => v.isActive).toList();
    final isPersonalActive =
        !(meCtx.lastActiveContext?.toUpperCase().contains('VENUE') ?? false);

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 16, bottom: 8),
              decoration: BoxDecoration(
                color: colors.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetCtx).size.height * 0.35,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  if (meCtx.hasPersonalProfile)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colors.primary.withValues(alpha: 0.12),
                        child: Icon(Icons.person_outline, color: colors.primary),
                      ),
                      title: Text(
                        'Personal',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        'Personal account',
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                      trailing: isPersonalActive
                          ? Icon(Icons.check_circle, color: colors.primary)
                          : null,
                      onTap: isPersonalActive
                          ? null
                          : () async {
                              Navigator.pop(sheetCtx);
                              try {
                                await AuthRepository().switchContext(
                                  lastActiveContext: 'PERSONAL',
                                );
                                if (!context.mounted) return;
                                Navigator.of(context).pushNamedAndRemoveUntil(
                                  AuthRoutes.authGate,
                                  (r) => false,
                                );
                              } catch (_) {}
                            },
                    ),
                  ...activeVenues.map((venue) {
                    final isActive =
                        !isPersonalActive && (meCtx.activeVenueId == venue.id);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colors.primary.withValues(alpha: 0.12),
                        child: Icon(Icons.storefront, color: colors.primary),
                      ),
                      title: Text(
                        venue.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        venue.role ?? 'Venue',
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                      trailing: isActive
                          ? Icon(Icons.check_circle, color: colors.primary)
                          : null,
                      onTap: isActive
                          ? null
                          : () async {
                              Navigator.pop(sheetCtx);
                              try {
                                await AuthRepository().switchContext(
                                  lastActiveContext: 'VENUE',
                                  activeVenueId: venue.id,
                                );
                                if (!context.mounted) return;
                                Navigator.of(context).pushNamedAndRemoveUntil(
                                  AuthRoutes.authGate,
                                  (r) => false,
                                );
                              } catch (_) {}
                            },
                    );
                  }),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add, color: colors.primary, size: 22),
              ),
              title: Text(
                'Add Venue Account',
                style: TextStyle(fontWeight: FontWeight.w600, color: colors.primary),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const VenueContextOnboardingPage(fromAppShell: true),
                  ),
                );
              },
            ),
            if (!meCtx.hasPersonalProfile)
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.person_add_outlined, color: colors.primary, size: 22),
                ),
                title: Text(
                  'Add Personal Account',
                  style: TextStyle(fontWeight: FontWeight.w600, color: colors.primary),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NameDobOnboardingPage()),
                  );
                },
              ),
            ListTile(
              leading: Icon(Icons.manage_accounts_outlined, color: colors.onSurface),
              title: Text('Go to Accounts Center', style: TextStyle(color: colors.onSurface)),
              onTap: () {
                Navigator.pop(sheetCtx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountSettingsPage()),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_loading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    final venue = _venue;
    final colors = theme.colorScheme;
    final isOwner = _venueRole == VenueMemberRole.owner;
    final hasPhoto = venue?.photo != null && venue!.photo!.isNotEmpty;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        leading: const AppLogo(),
        title: _buildAppBarTitle(theme, isDark),
        actions: [
          IconButton(
            onPressed: _openSettings,
            icon: Icon(
              Icons.menu,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.grey[200],
            height: 1,
          ),
        ),
      ),
      body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Venue fotoğrafı ───────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                          child: Stack(
                            children: [
                              GestureDetector(
                                onTap: hasPhoto
                                    ? () => _showPhotoViewer(venue!.photo!)
                                    : null,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: hasPhoto
                                      ? Image.network(
                                          venue!.photo!,
                                          height: 140,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              _PhotoPlaceholder(colors: colors),
                                        )
                                      : _PhotoPlaceholder(colors: colors),
                                ),
                              ),
                              // Kalem ikonu — sağ üst köşe
                              Positioned(
                                top: 10,
                                right: 10,
                                child: GestureDetector(
                                  onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
                                  child: Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.55),
                                      shape: BoxShape.circle,
                                    ),
                                    child: _uploadingPhoto
                                        ? const Padding(
                                            padding: EdgeInsets.all(8),
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.edit_outlined,
                                            size: 17,
                                            color: Colors.white,
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ── Venue adı + bilgiler ──────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (venue != null) ...[
                                    VenueStoryBubble(
                                      venueId: venue.id,
                                      venueName: venue.name,
                                      venuePhotoUrl: venue.photo,
                                      isUploading: _uploadingStory,
                                      onAddStory: _openAddStory,
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  Expanded(
                                    child: Text(
                                      venue?.name ?? widget.activeVenueName ?? 'Venue',
                                      style: TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w800,
                                        color: colors.onSurface,
                                        letterSpacing: -0.4,
                                        height: 1.18,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (venue?.address != null &&
                                  venue!.address!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.location_on_outlined,
                                      size: 13,
                                      color: colors.onSurface.withValues(alpha: 0.45),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        venue.address!,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: colors.onSurface.withValues(alpha: 0.55),
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),

                        // ── Badges ────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                          child: Row(
                            children: [
                              _RoleBadge(role: _venueRole, colors: colors),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _showTypePicker,
                                child: _TypeBadge(
                                  type: venue?.type,
                                  updating: _updatingType,
                                  colors: colors,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── Quick content actions ─────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _QuickActionsBar(
                            onEvent: _openAddEvent,
                            onPush: () => _comingSoon('Push Notification'),
                            onStory: _openAddStory,
                            colors: colors,
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── Team management ───────────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _SectionCard(
                            child: _ActionRow(
                              icon: Icons.group_outlined,
                              label: 'Team Management',
                              subtitle: isOwner
                                  ? 'Manage members & roles'
                                  : 'View team',
                              onTap: venue != null ? _openTeam : null,
                              colors: colors,
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // ── Events ────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _EventsSection(
                            events: venue?.upcomingEvents ?? const [],
                            venueId: venue?.id ?? '',
                            onAdd: _openAddEvent,
                            onGoToList: _openEventsList,
                            colors: colors,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // ── Push notifications ────────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _PostsSection(
                            onAdd: () => _comingSoon('Posts'),
                            colors: colors,
                          ),
                        ),

                        SizedBox(
                          height: MediaQuery.of(context).padding.bottom +
                              kBottomNavigationBarHeight + 16,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
    );
  }
}

// ─── Photo placeholder ────────────────────────────────────────────────────────

class _PhotoPlaceholder extends StatelessWidget {
  final ColorScheme colors;
  const _PhotoPlaceholder({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined,
              size: 36, color: colors.onSurface.withValues(alpha: 0.35)),
          const SizedBox(height: 6),
          Text(
            'Add cover photo',
            style: TextStyle(
              fontSize: 12,
              color: colors.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Photo viewer ────────────────────────────────────────────────────────────

class _PhotoViewer extends StatelessWidget {
  final String url;
  const _PhotoViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              ),
              Positioned(
                top: 12,
                right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
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

// ─── Type badge ───────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final String? type;
  final bool updating;
  final ColorScheme colors;
  const _TypeBadge({required this.type, required this.updating, required this.colors});

  static const _labels = {
    'bar': 'Bar',
    'club': 'Club',
    'cafe': 'Café',
    'lounge': 'Lounge',
    'restaurant': 'Restaurant',
  };

  static const _icons = {
    'bar': Icons.local_bar_outlined,
    'club': Icons.nightlife_outlined,
    'cafe': Icons.local_cafe_outlined,
    'lounge': Icons.weekend_outlined,
    'restaurant': Icons.restaurant_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final t = type?.toLowerCase();
    final label = _labels[t] ?? 'Set type';
    final icon = _icons[t] ?? Icons.category_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outline.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (updating)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: colors.onSurface.withValues(alpha: 0.5),
              ),
            )
          else
            Icon(icon, size: 13, color: colors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.edit_outlined, size: 11, color: colors.primary),
        ],
      ),
    );
  }
}

// ─── Role badge ───────────────────────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  final VenueMemberRole role;
  final ColorScheme colors;
  const _RoleBadge({required this.role, required this.colors});

  String get _label {
    switch (role) {
      case VenueMemberRole.owner:
        return 'Owner';
      case VenueMemberRole.admin:
        return 'Admin';
      default:
        return 'Staff';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outline.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.badge_outlined, size: 13, color: colors.primary),
          const SizedBox(width: 6),
          Text(
            _label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quick content actions bar ────────────────────────────────────────────────

class _QuickActionsBar extends StatelessWidget {
  final VoidCallback onEvent;
  final VoidCallback onPush;
  final VoidCallback onStory;
  final ColorScheme colors;

  const _QuickActionsBar({
    required this.onEvent,
    required this.onPush,
    required this.onStory,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
        children: [
          _QuickTile(
            icon: Icons.event_outlined,
            label: 'Event',
            onTap: onEvent,
            colors: colors,
          ),
          const SizedBox(width: 9),
          _QuickTile(
            icon: Icons.campaign_outlined,
            label: 'Push',
            onTap: onPush,
            colors: colors,
          ),
          const SizedBox(width: 9),
          _QuickTile(
            icon: Icons.add_photo_alternate_outlined,
            label: 'Story',
            onTap: onStory,
            colors: colors,
          ),
        ],
      );
  }
}

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ColorScheme colors;

  const _QuickTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Events section ───────────────────────────────────────────────────────────

class _EventsSection extends StatelessWidget {
  final List<VenueUpcomingEvent> events;
  final String venueId;
  final VoidCallback onAdd;
  final VoidCallback onGoToList;
  final ColorScheme colors;

  const _EventsSection({
    required this.events,
    required this.venueId,
    required this.onAdd,
    required this.onGoToList,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayEvents = events.where((e) {
      final d = e.startAt.toLocal();
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                _SectionHeader(label: 'Today\'s Events', colors: colors),
                const Spacer(),
                GestureDetector(
                  onTap: onGoToList,
                  child: Text(
                    'All events',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colors.primary),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Empty state ──────────────────────────────────────────────────
          if (todayEvents.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.event_outlined, size: 18,
                        color: colors.onSurface.withValues(alpha: 0.28)),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No events today',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                              color: colors.onSurface.withValues(alpha: 0.45))),
                      const SizedBox(height: 2),
                      GestureDetector(
                        onTap: onAdd,
                        child: Text('Publish your first event',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                color: colors.primary)),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else ...[
            // ── Vertical card list (2 visible, rest scrollable) ───────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: todayEvents.length <= 2
                  ? Column(
                      children: todayEvents.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _EventCard(event: e, venueId: venueId, colors: colors, onAdd: onAdd),
                      )).toList(),
                    )
                  : SizedBox(
                      height: 300,
                      child: ListView.builder(
                        physics: const ClampingScrollPhysics(),
                        itemCount: todayEvents.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _EventCard(event: todayEvents[i], venueId: venueId, colors: colors, onAdd: onAdd),
                        ),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final VenueUpcomingEvent event;
  final String venueId;
  final ColorScheme colors;
  final VoidCallback onAdd;

  const _EventCard({required this.event, required this.venueId, required this.colors, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final photos = event.photos.isNotEmpty
        ? event.photos
        : (event.photo != null ? [event.photo!] : <String>[]);

    return Container(
        decoration: BoxDecoration(
          color: isDark ? colors.surfaceContainerHighest : const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.outline.withValues(alpha: isDark ? 0.12 : 0.09)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title + date ────────────────────────────────────────────
            Text(
              event.title,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.onSurface),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.calendar_today_outlined, size: 11, color: colors.primary),
              const SizedBox(width: 4),
              Text(event.formattedDate,
                  style: TextStyle(fontSize: 11.5, color: colors.onSurface.withValues(alpha: 0.55))),
              if (event.priceAed != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: event.priceAed == 0
                        ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                        : colors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    event.priceAed == 0 ? 'Free' : 'AED ${event.priceAed}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: event.priceAed == 0 ? const Color(0xFF22C55E) : colors.primary,
                    ),
                  ),
                ),
              ],
            ]),

            // ── Description ─────────────────────────────────────────────
            if (event.description != null && event.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                event.description!,
                style: TextStyle(fontSize: 12.5, color: colors.onSurface.withValues(alpha: 0.6), height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // ── Photos ──────────────────────────────────────────────────
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: photos.map((url) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(url, width: 64, height: 64, fit: BoxFit.cover),
                  ),
                )).toList(),
              ),
            ],
          ],
        ),
    );
  }
}

// ─── Posts grid section ───────────────────────────────────────────────────────

class _PostsSection extends StatelessWidget {
  final VoidCallback onAdd;
  final ColorScheme colors;

  const _PostsSection({required this.onAdd, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SectionHeader(label: 'Push Notifications', colors: colors),
              GestureDetector(
                onTap: onAdd,
                child: Text(
                  '+ Send',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colors.outline.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.campaign_outlined,
                    size: 20,
                    color: colors.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Send a notification to nearby guests…',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurface.withValues(alpha: 0.35),
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

// ─── Section card wrapper ─────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.outline.withValues(alpha: 0.15),
        ),
      ),
      child: child,
    );
  }
}

// ─── Section header label ─────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final ColorScheme colors;
  const _SectionHeader({required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: colors.onSurface,
        letterSpacing: 0.1,
      ),
    );
  }
}

// ─── Action row ───────────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final ColorScheme colors;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.colors,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: colors.onPrimaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: colors.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

