import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kmstry_frontend/core/checkin/checkin_ping_manager.dart';
import 'package:kmstry_frontend/core/ui/app_logo.dart';
import 'package:kmstry_frontend/core/user/user_session.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:kmstry_frontend/features/profile/presentation/settings_page.dart';
import 'package:kmstry_frontend/core/layout/app_shell.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_stats_model.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/name_dob_onboarding_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_context_onboarding_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_edit_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_team_page.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_viewer_page.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_model.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_repository.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_viewed_cache.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_gallery_section.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_menu_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_content_sections.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_model.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_feature_visibility.dart';
import 'package:kmstry_frontend/core/venue/plan_gate.dart';
import 'package:kmstry_frontend/core/venue/venue_plan.dart';
import 'package:kmstry_frontend/features/venue_stories/presentation/add_venue_story_page.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/add_venue_event_page.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/venue_events_list_page.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/venue_event_detail_page.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';

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
  String _personalLabel = 'Personal';
  bool _uploadingPhoto = false;
  bool _updatingType = false;
  bool _uploadingStory = false;
  List<VenueStoryItem> _avatarStories = [];
  final _venueStoryRepo = VenueStoryRepository();

  // Deals & discounts (salt-görüntü) — venue detay sayfasıyla aynı.
  final _partnershipRepo = ExternalPartnershipRepository();
  List<ExternalPartnershipModel> _partnerships = const [];

  @override
  void initState() {
    super.initState();
    _loadVenueProfile();
  }

  Future<void> _loadAvatarStories(String venueId) async {
    try {
      final stories = await _venueStoryRepo.getVenueStories(venueId);
      if (!mounted) return;
      // Backend "viewed_by_me" bu oturumda henüz güncellenmemiş olabilir; oturum-içi
      // izlenme cache'ini overlay ediyoruz ki sayfaya geri dönünce halka gri kalsın.
      final cache = VenueStoryViewedCache.instance;
      setState(() {
        _avatarStories = [
          for (final s in stories)
            (s.viewedByMe || cache.isViewed(s.id))
                ? s.copyWith(viewedByMe: true)
                : s,
        ];
      });
    } catch (_) {}
  }

  void _onStoryViewerClose(int lastIndex, bool allFinished) {
    if (!mounted) return;
    final justViewed = allFinished
        ? _avatarStories.map((s) => s.id).toSet()
        : {
            for (int i = 0; i <= lastIndex && i < _avatarStories.length; i++)
              _avatarStories[i].id,
          };
    final cache = VenueStoryViewedCache.instance;
    justViewed.forEach(cache.mark);
    setState(() {
      _avatarStories = [
        for (final s in _avatarStories)
          (s.viewedByMe || justViewed.contains(s.id))
              ? s.copyWith(viewedByMe: true)
              : s,
      ];
    });
  }

  void _onStoryDeleted(String storyId) {
    if (!mounted) return;
    VenueStoryViewedCache
        .instance; // cache'den çıkarmak gerekmez, sadece listeden sil
    setState(() {
      _avatarStories = _avatarStories.where((s) => s.id != storyId).toList();
    });
  }

  Future<void> _loadVenueProfile() async {
    setState(() => _loading = true);
    try {
      final me = await AuthRepository().getMe();
      final ctx = MeContextModel.fromMe(me);
      final username = me['username']?.toString();
      final fullName = (me['fullName'] ?? me['full_name'])?.toString();
      final personalLabel = (username != null && username.isNotEmpty)
          ? '@$username'
          : (fullName != null && fullName.isNotEmpty ? fullName : 'Personal');

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

        if (memberVenue?.isPendingOwnerClaim == true ||
            memberVenue?.isRejectedOwnerClaim == true) {
          if (!mounted) return;
          setState(() {
            _meContext = ctx;
            _venue = VenueOwnerStatsVenue(
              id: venueId!,
              name: memberVenue?.name ?? widget.activeVenueName ?? 'Venue',
              photo: memberVenue?.photoUrl,
              address: memberVenue?.address,
            );
            _venueRole = resolvedRole;
            _personalLabel = personalLabel;
            _loading = false;
          });
          return;
        }

        final response = await VenueOwnerRepository().getOwnerStats(venueId);
        if (!mounted) return;
        setState(() {
          _meContext = ctx;
          _venue = response.venue;
          _venueRole = resolvedRole;
          _personalLabel = personalLabel;
          _loading = false;
        });
        // Permission'ları yükle (async, UI'ı bloklamaz)
        VenueSession.instance.load(venueId, resolvedRole);
        // Story state'i sadece boşsa yükle — viewer kapanınca optimistic update korunur
        if (_avatarStories.isEmpty) _loadAvatarStories(venueId);
        // Deals & discounts (best-effort, UI'ı bloklamaz).
        _loadPartnerships(venueId);
      } else {
        if (!mounted) return;
        setState(() {
          _meContext = ctx;
          _personalLabel = personalLabel;
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadPartnerships(String venueId) async {
    try {
      final partnerships = await _partnershipRepo.getActivePartnerships(
        venueId,
      );
      if (mounted) setState(() => _partnerships = partnerships);
    } catch (_) {
      /* best-effort — sessiz geç */
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

  Widget _buildAbout(VenueOwnerStatsVenue venue, bool canEdit) {
    final colors = Theme.of(context).colorScheme;
    final kText = colors.onSurface;
    final kDim = kText.withValues(alpha: 0.55);
    final desc = venue.description?.trim() ?? '';
    final hasDesc = desc.isNotEmpty;

    // Açıklama yoksa ve düzenleme yetkisi de yoksa hiç gösterme (detay sayfasıyla tutarlı).
    if (!hasDesc && !canEdit) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          venueSectionTitle(
            context,
            AppColors.magenta,
            'About',
            trailing: canEdit
                ? GestureDetector(
                    onTap: () => _editAbout(venue),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasDesc ? Icons.edit_outlined : Icons.add,
                            size: 14,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            hasDesc ? 'Edit' : 'Add',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 6),
          Text(
            hasDesc
                ? desc
                : 'Tell customers about your venue — vibe, music, what makes it special.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: hasDesc ? kText.withValues(alpha: 0.75) : kDim,
              fontStyle: hasDesc ? FontStyle.normal : FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockedProfileSection({
    required String title,
    required IconData icon,
    required String message,
    Color dotColor = AppColors.magenta,
  }) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          venueSectionTitle(context, dotColor, title),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.035)
                  : Colors.black.withValues(alpha: 0.035),
              border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 17, color: colors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: colors.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editAbout(VenueOwnerStatsVenue venue) async {
    final controller = TextEditingController(text: venue.description ?? '');
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final kCard = isDark ? const Color(0xFF0B1322) : Colors.white;
        final kText = isDark
            ? const Color(0xFFEEF2FF)
            : const Color(0xFF111827);
        final kDim = isDark ? const Color(0xFFB1B4BB) : const Color(0xFF5D6B7B);
        bool saving = false;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: kDim.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'About',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: kText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Shown on your public venue page.',
                      style: TextStyle(fontSize: 12, color: kDim),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: controller,
                      maxLength: 1000,
                      maxLines: 6,
                      minLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(fontSize: 14, height: 1.5, color: kText),
                      decoration: InputDecoration(
                        hintText: 'Tell customers about your venue…',
                        hintStyle: TextStyle(
                          color: kDim.withValues(alpha: 0.7),
                        ),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF0D1525)
                            : const Color(0xFFF3F6FA),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: PrimaryButton(
                        label: 'Save',
                        loading: saving,
                        onPressed: saving
                            ? null
                            : () {
                                setSheet(() => saving = true);
                                Navigator.pop(ctx, controller.text.trim());
                              },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (saved == null || !mounted) return;
    try {
      final updated = await VenueOwnerRepository().updateVenue(
        venue.id,
        description: saved,
      );
      if (mounted) setState(() => _venue = updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
                  color: isSelected
                      ? colors.primary
                      : colors.onSurface.withValues(alpha: 0.7),
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
      MaterialPageRoute(builder: (_) => const SettingsPage()),
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

    // Plan kilidi: Free venue story paylaşamaz. Kamerayı hiç açmadan,
    // baştan etkileyici bir upsell göster.
    if (!PlanGate.allows(VenueFeature.stories)) {
      await PlanGate.ensureWithUpsell(
        context,
        VenueFeature.stories,
        icon: Icons.amp_stories_rounded,
        title: 'Share Stories with your guests',
        message:
            'Post 24-hour photo & video moments that pull people in and drive foot traffic. '
            'Stories are part of the Social plan — upgrade to start engaging your audience.',
        onAllowed: () {},
      );
      return;
    }

    setState(() => _uploadingStory = true);
    try {
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => AddVenueStoryPage(venueId: venueId)),
      );
    } finally {
      if (mounted) {
        setState(() => _uploadingStory = false);
        final venueId = _venue?.id;
        if (venueId != null) _loadAvatarStories(venueId);
      }
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
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    try {
      CheckinPingManager.I.stop();
      ActiveCheckinService().clear();
      UserSession.instance.clear();
      await AuthRepository().logout();
      if (!context.mounted) return;

      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AuthRoutes.login, (route) => false);
    } catch (_) {}
  }

  void _showAccountPicker(BuildContext context) {
    final meCtx = _meContext;
    if (meCtx == null) return;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accountVenues = meCtx.memberVenues
        .where((v) => v.isActive || v.isPendingOwnerClaim)
        .toList();
    final isPersonalActive =
        !(meCtx.lastActiveContext?.toUpperCase().contains('VENUE') ?? false);

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      // isScrollControlled: varsayılan ~9/16 ekran sınırı, sabit footer + venue
      // listesiyle birkaç px aşılıp "bottom overflow" veriyordu. Bu bayrak sheet'i
      // içeriğe göre boyutlar; venue listesi zaten iç ConstrainedBox ile sınırlı.
      isScrollControlled: true,
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
                        child: Icon(
                          Icons.person_outline,
                          color: colors.primary,
                        ),
                      ),
                      title: Text(
                        _personalLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        'Personal',
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
                          : () {
                              // Smooth in-place switch → lands on personal Profile.
                              Navigator.pop(sheetCtx);
                              AppShellNav.of(
                                context,
                              )?.switchToPersonalProfile();
                            },
                    ),
                  ...accountVenues.map((venue) {
                    final isActive =
                        !isPersonalActive && (meCtx.activeVenueId == venue.id);
                    final isPending = venue.isPendingOwnerClaim;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isPending
                            ? colors.onSurface.withValues(alpha: 0.08)
                            : colors.primary.withValues(alpha: 0.12),
                        child: Icon(
                          isPending
                              ? Icons.hourglass_top_rounded
                              : Icons.storefront,
                          color: isPending
                              ? colors.onSurface.withValues(alpha: 0.45)
                              : colors.primary,
                        ),
                      ),
                      title: Text(
                        venue.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        isPending ? 'Pending review' : (venue.role ?? 'Venue'),
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                      trailing: isPending
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Pending',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange,
                                ),
                              ),
                            )
                          : isActive
                          ? Icon(Icons.check_circle, color: colors.primary)
                          : null,
                      onTap: isActive
                          ? null
                          : () {
                              // Smooth in-place switch → lands on the venue's
                              // Profile tab (no full shell rebuild → no dashboard).
                              Navigator.pop(sheetCtx);
                              AppShellNav.of(
                                context,
                              )?.switchToVenueProfile(venue);
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
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const VenueContextOnboardingPage(fromAppShell: true),
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
                  child: Icon(
                    Icons.person_add_outlined,
                    color: colors.primary,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Add Personal Account',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NameDobOnboardingPage(),
                    ),
                  );
                },
              ),
            ListTile(
              leading: Icon(
                Icons.manage_accounts_outlined,
                color: colors.onSurface,
              ),
              title: Text(
                'Go to Settings',
                style: TextStyle(color: colors.onSurface),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.logout, color: colors.error),
              title: Text(
                'Log out',
                style: TextStyle(
                  color: colors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () async {
                final rootContext = context;
                Navigator.pop(sheetCtx);
                await _logout(rootContext);
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
    return ListenableBuilder(
      listenable: VenueSession.instance,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
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
    final session = VenueSession.instance;
    final hasPhoto = venue?.photo != null && venue!.photo!.isNotEmpty;
    final activeMemberVenue = _meContext?.memberVenues
        .where((v) => v.id == (venue?.id ?? widget.venueId))
        .firstOrNull;
    final isPendingClaim = activeMemberVenue?.isPendingOwnerClaim ?? false;
    final isRejectedClaim = activeMemberVenue?.isRejectedOwnerClaim ?? false;
    final isClaimLocked = isPendingClaim || isRejectedClaim;

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
            icon: Icon(Icons.menu, color: isDark ? Colors.white : Colors.black),
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
                          // Kalem ikonu — sağ üst köşe (sadece VENUE_EDIT yetkisi varsa)
                          if (!isClaimLocked &&
                              session.can(VenuePermission.venueEdit))
                            Positioned(
                              top: 10,
                              right: 10,
                              child: GestureDetector(
                                onTap: _uploadingPhoto
                                    ? null
                                    : _pickAndUploadPhoto,
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
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (venue != null) ...[
                                _VenueSquareAvatar(
                                  venue: venue,
                                  isUploading: _uploadingStory,
                                  canAddStory:
                                      !isClaimLocked &&
                                      session.can(VenuePermission.storyManage),
                                  canViewStats:
                                      !isClaimLocked &&
                                      (session.isOwner ||
                                          session.can(
                                            VenuePermission.storyViewStats,
                                          )),
                                  canDeleteStory:
                                      !isClaimLocked &&
                                      (session.isOwner ||
                                          session.can(
                                            VenuePermission.storyManage,
                                          )),
                                  onAddStory: _openAddStory,
                                  stories: _avatarStories,
                                  onStoryClose: _onStoryViewerClose,
                                  onStoryDeleted: _onStoryDeleted,
                                ),
                                const SizedBox(width: 14),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      venue?.name ??
                                          widget.activeVenueName ??
                                          'Venue',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: colors.onSurface,
                                        letterSpacing: -0.3,
                                        height: 1.2,
                                      ),
                                    ),
                                    if (venue?.address != null &&
                                        venue!.address!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.location_on_outlined,
                                            size: 12,
                                            color: colors.onSurface.withValues(
                                              alpha: 0.45,
                                            ),
                                          ),
                                          const SizedBox(width: 3),
                                          Expanded(
                                            child: Text(
                                              venue.address!,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: colors.onSurface
                                                    .withValues(alpha: 0.55),
                                                height: 1.4,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
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
                          Builder(
                            builder: (_) {
                              final canEditType =
                                  !isClaimLocked &&
                                  (session.isOwner ||
                                      session.can(VenuePermission.venueEdit));
                              return GestureDetector(
                                onTap: canEditType ? _showTypePicker : null,
                                child: _TypeBadge(
                                  type: venue?.type,
                                  updating: _updatingType,
                                  editable: canEditType,
                                  colors: colors,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    // NOT: Yönetim aksiyonları (Events, Offers, Team, Push)
                    // artık "Manage" sekmesinde. Profil = kimlik + stories + edit.

                    // ── About ─────────────────────────────────────────
                    if (isClaimLocked)
                      _buildLockedProfileSection(
                        title: 'About',
                        icon: Icons.info_outline_rounded,
                        message: isPendingClaim
                            ? 'Once your claim is approved, you will be able to add your venue description and introduce your vibe to guests.'
                            : 'This claim was not approved. About details are locked for this venue account.',
                      )
                    else if (venue != null)
                      _buildAbout(
                        venue,
                        session.isOwner ||
                            session.can(VenuePermission.venueEdit),
                      ),

                    // ── Deals & discounts (salt-görüntü) ──────────────
                    // Venue detay sayfasıyla aynı: About altında, tek satır
                    // kaydırılabilir chip'ler. Chip'e basınca detay açılır.
                    if (!isClaimLocked &&
                        venue != null &&
                        _partnerships.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: VenueDealsChipRow(
                          partnerships: _partnerships,
                          venueName: venue.name,
                        ),
                      ),
                    ],

                    // ── Menu ──────────────────────────────────────────
                    // About'un hemen ardından gelir; MENU_MANAGE iznine bağlıdır.
                    if (VenueFeatureVisibility.menu &&
                        !isClaimLocked &&
                        venue != null &&
                        (session.isOwner ||
                            session.can(VenuePermission.menuManage))) ...[
                      const SizedBox(height: 14),
                      VenueMenuProfileSection(
                        venueId: venue.id,
                        venueName: venue.name,
                      ),
                    ],

                    // ── Gallery ───────────────────────────────────────
                    if (isClaimLocked) ...[
                      const SizedBox(height: 18),
                      _buildLockedProfileSection(
                        title: 'Photos & Videos',
                        icon: Icons.photo_library_outlined,
                        dotColor: AppColors.teal,
                        message: isPendingClaim
                            ? 'After approval, you can upload venue photos and show guests what the place feels like.'
                            : 'Gallery management is locked because this claim was not approved.',
                      ),
                    ] else if (venue != null) ...[
                      const SizedBox(height: 18),
                      VenueGallerySection(
                        venueId: venue.id,
                        // Galeri ekleme/silme POST_CREATE iznine bağlı.
                        canEdit:
                            session.isOwner ||
                            session.can(VenuePermission.postCreate),
                      ),
                    ],

                    // ── Upcoming Events (salt-görüntü) ────────────────
                    // Venue detay sayfasıyla aynı kart tasarımı.
                    if (!isClaimLocked &&
                        venue != null &&
                        VenueUpcomingEventsSection.hasUpcoming(
                          venue.upcomingEvents,
                        )) ...[
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: VenueUpcomingEventsSection(
                          events: venue.upcomingEvents,
                          venueId: venue.id,
                          venueName: venue.name,
                          venueAddress: venue.address,
                          venuePhotoUrl: venue.photo,
                        ),
                      ),
                    ],

                    SizedBox(
                      height:
                          MediaQuery.of(context).padding.bottom +
                          kBottomNavigationBarHeight +
                          16,
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

// ─── Venue square avatar (with story ring) ────────────────────────────────────

class _VenueSquareAvatar extends StatefulWidget {
  final VenueOwnerStatsVenue venue;
  final bool isUploading;
  final bool canAddStory;
  final bool canViewStats;
  final bool canDeleteStory;
  final VoidCallback onAddStory;
  final List<VenueStoryItem> stories;
  final void Function(int lastIndex, bool allFinished) onStoryClose;
  final void Function(String storyId)? onStoryDeleted;

  const _VenueSquareAvatar({
    required this.venue,
    required this.isUploading,
    required this.canAddStory,
    required this.canViewStats,
    required this.canDeleteStory,
    required this.onAddStory,
    required this.stories,
    required this.onStoryClose,
    this.onStoryDeleted,
  });

  @override
  State<_VenueSquareAvatar> createState() => _VenueSquareAvatarState();
}

class _VenueSquareAvatarState extends State<_VenueSquareAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void didUpdateWidget(covariant _VenueSquareAvatar old) {
    super.didUpdateWidget(old);
    if (widget.isUploading && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.isUploading && _spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _openViewer() {
    final stories = widget.stories;
    if (stories.isEmpty && !widget.isUploading) return;
    final venueId = widget.venue.id;

    final startIndex = stories.indexWhere((s) => !s.viewedByMe);
    final initialIndex = startIndex == -1 ? 0 : startIndex;

    final storyItems = stories
        .map(
          (s) => StoryItem(
            id: s.id,
            mediaUrl: s.mediaUrl,
            mediaType: s.mediaType,
            thumbnailUrl: s.thumbnailUrl,
            durationSecs: s.durationSecs,
            expiresAt: s.expiresAt,
            createdAt: s.createdAt,
            viewCount: s.viewCount,
          ),
        )
        .toList();
    if (widget.isUploading) storyItems.add(StoryItem.uploadingPlaceholder());
    final group = StoryGroup(
      user: StoryUser(
        id: 'venue_$venueId',
        fullName: widget.venue.name,
        photo: widget.venue.photo,
      ),
      stories: storyItems,
    );
    Navigator.push<StoryViewerResult>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryViewerPage(
          groups: [group],
          venueId: venueId,
          showViewers: widget.canViewStats,
          canDelete: widget.canDeleteStory,
          initialStoryIndex: initialIndex,
          onClose: widget.onStoryClose,
          onStoryDeleted: widget.onStoryDeleted,
        ),
      ),
    );
  }

  Future<void> _showViewers() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StoryViewersSheet(venueId: widget.venue.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    final initial = widget.venue.name.isNotEmpty
        ? widget.venue.name[0].toUpperCase()
        : 'V';
    final hasPhoto =
        widget.venue.photo != null && widget.venue.photo!.isNotEmpty;
    final hasStories = widget.stories.isNotEmpty || widget.isUploading;
    final allSeen =
        widget.stories.isNotEmpty && widget.stories.every((s) => s.viewedByMe);

    // Logo brand gradient colors
    const logoColors = [
      Color(0xFF1A9FE8), // mavi
      Color(0xFF1FD9A8), // turkuaz
      Color(0xFFF08838), // turuncu
      Color(0xFFE020D8), // magenta
    ];

    const ringWidth = 3.0;
    const gap = 2.5;
    const avatarSize = 58.0;
    const totalSize = avatarSize + (ringWidth + gap) * 2;

    Widget avatar = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: hasPhoto
          ? Image.network(
              widget.venue.photo!,
              width: avatarSize,
              height: avatarSize,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  _InitialBox(initial: initial, colors: colors, isDark: isDark),
            )
          : _InitialBox(initial: initial, colors: colors, isDark: isDark),
    );

    Widget ring;
    if (hasStories) {
      if (widget.isUploading) {
        ring = SizedBox(
          width: totalSize,
          height: totalSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: ringWidth + gap,
                top: ringWidth + gap,
                child: avatar,
              ),
              Positioned.fill(
                child: RotationTransition(
                  turns: _spin..repeat(),
                  child: CustomPaint(
                    painter: _SquareRingPainter(
                      colors: logoColors,
                      strokeWidth: ringWidth,
                      radius: 16,
                      allSeen: false,
                      loading: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      } else {
        ring = SizedBox(
          width: totalSize,
          height: totalSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: ringWidth + gap,
                top: ringWidth + gap,
                child: avatar,
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _SquareRingPainter(
                    colors: allSeen
                        ? [Colors.grey.shade400, Colors.grey.shade500]
                        : logoColors,
                    strokeWidth: ringWidth,
                    radius: 16,
                    allSeen: allSeen,
                    loading: false,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    } else {
      ring = SizedBox(
        width: totalSize,
        height: totalSize,
        child: Center(child: avatar),
      );
    }

    return GestureDetector(
      onTap: hasStories
          ? _openViewer
          : (widget.canAddStory && !widget.isUploading
                ? widget.onAddStory
                : null),
      onLongPress: hasStories ? _showViewers : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ring,
          if (widget.canAddStory)
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: widget.isUploading ? null : widget.onAddStory,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _Brand.turkuaz,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? const Color(0xFF06091A) : Colors.white,
                      width: 2,
                    ),
                  ),
                  child: widget.isUploading
                      ? const Padding(
                          padding: EdgeInsets.all(3),
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add, size: 12, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Square gradient ring painter ─────────────────────────────────────────────

class _SquareRingPainter extends CustomPainter {
  final List<Color> colors;
  final double strokeWidth;
  final double radius;
  final bool allSeen;
  final bool loading;

  const _SquareRingPainter({
    required this.colors,
    required this.strokeWidth,
    required this.radius,
    required this.allSeen,
    required this.loading,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(radius),
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (loading) {
      // Arc segment only (rotated externally)
      paint.shader = SweepGradient(
        colors: [colors.first.withValues(alpha: 0), ...colors],
        stops: [0.0, 0.4, 0.7, 1.0],
      ).createShader(rect);
      final path = Path()..addRRect(rrect);
      final pathMetric = path.computeMetrics().first;
      final segment = pathMetric.extractPath(0, pathMetric.length * 0.6);
      canvas.drawPath(segment, paint);
    } else {
      paint.shader = SweepGradient(
        colors: [...colors, colors.first],
      ).createShader(rect);
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SquareRingPainter old) =>
      old.allSeen != allSeen || old.loading != loading;
}

class _InitialBox extends StatelessWidget {
  final String initial;
  final ColorScheme colors;
  final bool isDark;

  const _InitialBox({
    required this.initial,
    required this.colors,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A2A50)
            : colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: _Brand.turkuaz,
          ),
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
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 36,
            color: colors.onSurface.withValues(alpha: 0.35),
          ),
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
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 18,
                    ),
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

// ─── Brand colors ─────────────────────────────────────────────────────────────

class _Brand {
  static const magenta = Color(0xFFE020D8);
  static const turkuaz = Color(0xFF1FD9A8);
  static const mavi = Color(0xFF1A9FE8);
  static const turuncu = Color(0xFFF08838);
  static const koruMor = Color(0xFF3D1F8C);
}

// ─── Type badge ───────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final String? type;
  final bool updating;
  final bool editable;
  final ColorScheme colors;
  const _TypeBadge({
    required this.type,
    required this.updating,
    required this.editable,
    required this.colors,
  });

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
        color: _Brand.turkuaz.withValues(alpha: 0.12),
        border: Border.all(color: _Brand.turkuaz.withValues(alpha: 0.40)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (updating)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: _Brand.turkuaz,
              ),
            )
          else
            Icon(icon, size: 13, color: _Brand.turkuaz),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _Brand.turkuaz,
            ),
          ),
          if (editable) ...[
            const SizedBox(width: 4),
            const Icon(Icons.edit_outlined, size: 11, color: _Brand.turkuaz),
          ],
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

  Color get _color {
    switch (role) {
      case VenueMemberRole.owner:
        return _Brand.magenta;
      case VenueMemberRole.admin:
        return _Brand.mavi;
      default:
        return _Brand.turuncu;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        border: Border.all(color: c.withValues(alpha: 0.40)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.badge_outlined, size: 13, color: c),
          const SizedBox(width: 6),
          Text(
            _label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quick content actions bar ────────────────────────────────────────────────

class _QuickActionsBar extends StatelessWidget {
  final VoidCallback? onEvent;
  final VoidCallback? onPush;
  final VoidCallback? onStory;
  final ColorScheme colors;

  const _QuickActionsBar({
    required this.onEvent,
    required this.onPush,
    required this.onStory,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      if (onEvent != null)
        _QuickTile(icon: Icons.event_outlined, label: 'Event', onTap: onEvent!),
      if (onPush != null)
        _QuickTile(
          icon: Icons.campaign_outlined,
          label: 'Push',
          onTap: onPush!,
        ),
      if (onStory != null)
        _QuickTile(
          icon: Icons.add_photo_alternate_outlined,
          label: 'Story',
          onTap: onStory!,
        ),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Row(
      children: tiles.expand((t) => [t, const SizedBox(width: 9)]).toList()
        ..removeLast(),
    );
  }
}

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF131929) : const Color(0xFFF0F2F8);
    final iconColor = isDark
        ? Colors.white.withValues(alpha: 0.85)
        : const Color(0xFF1A1F36);
    final textColor = isDark
        ? Colors.white.withValues(alpha: 0.75)
        : const Color(0xFF1A1F36);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(height: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: textColor,
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
  final VoidCallback? onAdd;
  final VoidCallback onGoToList;
  final VoidCallback? onEventChanged;
  final ColorScheme colors;

  const _EventsSection({
    required this.events,
    required this.venueId,
    required this.onAdd,
    required this.onGoToList,
    required this.colors,
    this.onEventChanged,
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
                  child: const Text(
                    'All events',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _Brand.magenta,
                    ),
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
                    child: Icon(
                      Icons.event_outlined,
                      size: 18,
                      color: colors.onSurface.withValues(alpha: 0.28),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No events today',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: colors.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (onAdd != null)
                        GestureDetector(
                          onTap: onAdd,
                          child: const Text(
                            'Publish your first event →',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _Brand.magenta,
                            ),
                          ),
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
                      children: todayEvents
                          .map(
                            (e) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _EventCard(
                                event: e,
                                venueId: venueId,
                                colors: colors,
                                onAdd: onAdd,
                                onChanged: onEventChanged,
                              ),
                            ),
                          )
                          .toList(),
                    )
                  : SizedBox(
                      height: 300,
                      child: ListView.builder(
                        physics: const ClampingScrollPhysics(),
                        itemCount: todayEvents.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _EventCard(
                            event: todayEvents[i],
                            venueId: venueId,
                            colors: colors,
                            onAdd: onAdd,
                            onChanged: onEventChanged,
                          ),
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
  final VoidCallback? onAdd;
  final VoidCallback? onChanged;

  const _EventCard({
    required this.event,
    required this.venueId,
    required this.colors,
    required this.onAdd,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final photos = event.photos.isNotEmpty
        ? event.photos
        : (event.photo != null ? [event.photo!] : <String>[]);

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => VenueEventDetailPage(
              event: event,
              venueId: venueId,
              onChanged: onChanged,
            ),
          ),
        );
        if (result == true) onChanged?.call();
      },
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? colors.surfaceContainerHighest
              : const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colors.outline.withValues(alpha: isDark ? 0.12 : 0.09),
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title + date ────────────────────────────────────────────
            Text(
              event.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 11,
                  color: colors.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  event.formattedDate,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                if (event.priceAed != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
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
                        color: event.priceAed == 0
                            ? const Color(0xFF22C55E)
                            : colors.primary,
                      ),
                    ),
                  ),
                ],
                if (event.capacity != null || event.rsvpCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A9FE8).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      event.capacity != null
                          ? '${event.rsvpCount}/${event.capacity}'
                          : '${event.rsvpCount} attending',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A9FE8),
                      ),
                    ),
                  ),
                ],
              ],
            ),

            // ── Description ─────────────────────────────────────────────
            if (event.description != null && event.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                event.description!,
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.onSurface.withValues(alpha: 0.6),
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // ── Offers & Partner Benefits badges ────────────────────────
            if (event.hasOffer || event.partnershipCount > 0) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (event.hasOffer)
                    _BenefitBadge(
                      icon: Icons.local_offer_outlined,
                      label: event.offerTypeLabel!,
                      color: const Color(0xFFF08838),
                    ),
                  if (event.partnershipCount > 0)
                    _BenefitBadge(
                      icon: Icons.handshake_outlined,
                      label:
                          '${event.partnershipCount} partner benefit${event.partnershipCount > 1 ? 's' : ''}',
                      color: const Color(0xFF1A9FE8),
                    ),
                ],
              ),
            ],

            // ── Photos ──────────────────────────────────────────────────
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: photos
                    .map(
                      (url) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            url,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BenefitBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _BenefitBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
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
                child: const Text(
                  '+ Send',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _Brand.magenta,
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
        border: Border.all(color: colors.outline.withValues(alpha: 0.15)),
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
                color: _Brand.mavi.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: _Brand.mavi),
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

// ─── Story viewers bottom sheet ───────────────────────────────────────────────

class _StoryViewersSheet extends StatefulWidget {
  final String venueId;
  const _StoryViewersSheet({required this.venueId});

  @override
  State<_StoryViewersSheet> createState() => _StoryViewersSheetState();
}

class _StoryViewersSheetState extends State<_StoryViewersSheet> {
  final _repo = VenueStoryRepository();
  List<Map<String, dynamic>> _data = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _repo.getViewers(widget.venueId);
      if (mounted)
        setState(() {
          _data = data;
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kBg = isDark ? const Color(0xFF0D1525) : Colors.white;
    final kText = isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827);
    final kDim = isDark ? const Color(0xFF3A5070) : const Color(0xFF9CA3AF);

    // Flatten all viewers across stories, deduplicated by userId, most recent first
    final Map<String, Map<String, dynamic>> byUser = {};
    for (final story in _data) {
      for (final v in (story['viewers'] as List? ?? [])) {
        final user = v['user'] as Map<String, dynamic>;
        final uid = user['id'] as String;
        if (!byUser.containsKey(uid)) {
          byUser[uid] = {'user': user, 'viewed_at': v['viewed_at']};
        }
      }
    }
    final viewers = byUser.values.toList();

    final totalViews = _data.fold<int>(
      0,
      (sum, s) => sum + ((s['view_count'] as num?)?.toInt() ?? 0),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: kDim.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(
                  Icons.remove_red_eye_outlined,
                  size: 18,
                  color: _Brand.turkuaz,
                ),
                const SizedBox(width: 8),
                Text(
                  'Story Viewers',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: kText,
                  ),
                ),
                const Spacer(),
                if (!_loading)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _Brand.turkuaz.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$totalViews views',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _Brand.turkuaz,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _Brand.turkuaz,
              ),
            )
          else if (viewers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No views yet',
                style: TextStyle(color: kDim, fontSize: 14),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: viewers.length,
                itemBuilder: (_, i) {
                  final user = viewers[i]['user'] as Map<String, dynamic>;
                  final photo = user['photo'] as String?;
                  final name =
                      (user['full_name'] ?? user['username'] ?? 'User')
                          as String;
                  final viewedAt = viewers[i]['viewed_at'] as String?;
                  final dt = viewedAt != null
                      ? DateTime.tryParse(viewedAt)?.toLocal()
                      : null;
                  final timeLabel = dt != null
                      ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
                      : '';

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: _Brand.turkuaz.withValues(alpha: 0.12),
                      backgroundImage: photo != null && photo.isNotEmpty
                          ? NetworkImage(photo)
                          : null,
                      child: photo == null || photo.isEmpty
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _Brand.turkuaz,
                              ),
                            )
                          : null,
                    ),
                    title: Text(
                      name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kText,
                      ),
                    ),
                    trailing: Text(
                      timeLabel,
                      style: TextStyle(fontSize: 12, color: kDim),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
