import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/app_back_button.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_model.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_offer_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_offer_repository.dart';
import 'add_external_partnership_page.dart';
import 'add_venue_offer_page.dart';
import 'edit_external_partnership_page.dart';

class VenueOffersPage extends StatefulWidget {
  final String venueId;
  final String venueName;

  const VenueOffersPage({
    super.key,
    required this.venueId,
    required this.venueName,
  });

  @override
  State<VenueOffersPage> createState() => _VenueOffersPageState();
}

class _VenueOffersPageState extends State<VenueOffersPage> {
  final _partnershipRepo = ExternalPartnershipRepository();

  List<ExternalPartnershipModel> _partnerships = [];
  // ignore: unused_field
  final List<VenueOfferModel> _offers = [];
  bool _loading = true;
  String? _error;

  // Filters
  ExternalPartnershipPlatform? _filterPlatform;
  ExternalPartnershipOfferType? _filterOfferType;

  List<ExternalPartnershipModel> get _filteredPartnerships {
    return _partnerships.where((p) {
      if (_filterPlatform != null && p.platform != _filterPlatform) return false;
      if (_filterOfferType != null && p.offerType != _filterOfferType) return false;
      return true;
    }).toList();
  }

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
      final partnerships = await _partnershipRepo.getPartnerships(widget.venueId);
      if (!mounted) return;
      setState(() {
        _partnerships = partnerships;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kBg = isDark ? AppColors.darkBg : Colors.white;
    final kBorder = isDark
        ? const Color(0xFF162040)
        : Colors.black.withValues(alpha: 0.07);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 60,
        leading: const Padding(
          padding: EdgeInsets.only(left: 14),
          child: AppBackButton(),
        ),
        title: Text(
          'Offers & Benefits',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: colors.onSurface),
        ),
        actions: [
          if (_canManagePartnerships)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Material(
                color: AppColors.blue.withValues(alpha: isDark ? 0.16 : 0.10),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AddExternalPartnershipPage(venueId: widget.venueId),
                    ),
                  ).then((_) => _load()),
                  child: const SizedBox(
                    width: 38,
                    height: 38,
                    child: Icon(Icons.add_rounded,
                        size: 22, color: AppColors.blue),
                  ),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: kBorder),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.blue))
          : _error != null
              ? _buildError()
              : _buildPartnershipsTab(colors, isDark, kBorder),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text(_error ?? 'Something went wrong'),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  // ── External Partnerships Tab ────────────────────────────────────────────────

  Widget _buildPartnershipsTab(
      ColorScheme colors, bool isDark, Color kBorder) {
    final filtered = _filteredPartnerships;
    final hasFilters = _filterPlatform != null || _filterOfferType != null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _InfoBanner(
            isDark: isDark,
            text: 'Add your venue\'s external platform partnerships (e.g. The Entertainer, Cobone).',
          ),
        ),
        // ── Filter row ────────────────────────────────────────────────────────
        if (_partnerships.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: _FilterChip(
                    label: _filterPlatform != null
                        ? _platformLabel(_filterPlatform!)
                        : 'Platform',
                    active: _filterPlatform != null,
                    onTap: () => _showPlatformFilter(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FilterChip(
                    label: _filterOfferType != null
                        ? _offerTypeLabel(_filterOfferType!)
                        : 'Benefit type',
                    active: _filterOfferType != null,
                    onTap: () => _showOfferTypeFilter(),
                  ),
                ),
                if (hasFilters) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() {
                      _filterPlatform = null;
                      _filterOfferType = null;
                    }),
                    child: Icon(Icons.close,
                        size: 18,
                        color: colors.onSurface.withValues(alpha: 0.4)),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: _partnerships.isEmpty
              ? _buildEmpty(
                  icon: Icons.handshake_outlined,
                  title: 'No external partnerships yet',
                  subtitle: 'Add partnerships like The Entertainer or Cobone to show benefits on your venue profile.',
                )
              : filtered.isEmpty
                  ? _buildEmpty(
                      icon: Icons.filter_list_off,
                      title: 'No matches',
                      subtitle: 'No partnerships match the selected filters.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _PartnershipCard(
                          item: filtered[i],
                          venueId: widget.venueId,
                          canManage: _canManagePartnerships,
                          onDeleted: _load,
                          onEdited: _load,
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  bool get _canManagePartnerships =>
      VenueSession.instance.can(VenuePermission.partnershipManage);

  void _showPlatformFilter() {
    final options = ExternalPartnershipPlatform.values
        .where((p) => _partnerships.any((x) => x.platform == p))
        .toList();
    _openFilterSheet(
      title: 'Filter by Platform',
      dotColor: AppColors.blue,
      itemCount: options.length,
      isSelectedAt: (i) => _filterPlatform == options[i],
      labelAt: (i) => _platformLabel(options[i]),
      onToggle: (i) {
        setState(() =>
            _filterPlatform = _filterPlatform == options[i] ? null : options[i]);
        Navigator.pop(context);
      },
    );
  }

  void _showOfferTypeFilter() {
    final options = ExternalPartnershipOfferType.values
        .where((t) => _partnerships.any((x) => x.offerType == t))
        .toList();
    _openFilterSheet(
      title: 'Filter by Benefit Type',
      dotColor: AppColors.teal,
      itemCount: options.length,
      isSelectedAt: (i) => _filterOfferType == options[i],
      labelAt: (i) => _offerTypeLabel(options[i]),
      onToggle: (i) {
        setState(() => _filterOfferType =
            _filterOfferType == options[i] ? null : options[i]);
        Navigator.pop(context);
      },
    );
  }

  /// Map filtre sheet'leriyle aynı premium dil: yuvarlak koyu sheet, logo renkli
  /// nokta başlık ve tile'lar (mavi→turkuaz onay kutusu).
  void _openFilterSheet({
    required String title,
    required Color dotColor,
    required int itemCount,
    required bool Function(int) isSelectedAt,
    required String Function(int) labelAt,
    required void Function(int) onToggle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kSurface = isDark ? const Color(0xFF0D1525) : Colors.white;
    final kCard = isDark ? const Color(0xFF111C2B) : const Color(0xFFF7FAFD);
    final kBorder =
        isDark ? const Color(0xFF162040) : Colors.black.withValues(alpha: 0.08);
    final kText = isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        margin: EdgeInsets.fromLTRB(
            12, 0, 12, MediaQuery.of(ctx).padding.bottom + 12),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: kBorder),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [AppColors.blue, AppColors.teal]),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: dotColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: kText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (int i = 0; i < itemCount; i++) ...[
              _SheetTile(
                label: labelAt(i),
                selected: isSelectedAt(i),
                isDark: isDark,
                kCard: kCard,
                kBorder: kBorder,
                kText: kText,
                onTap: () => onToggle(i),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  String _platformLabel(ExternalPartnershipPlatform p) {
    switch (p) {
      case ExternalPartnershipPlatform.THE_ENTERTAINER: return 'The Entertainer';
      case ExternalPartnershipPlatform.COBONE: return 'Cobone';
      case ExternalPartnershipPlatform.GROUPON: return 'Groupon';
      case ExternalPartnershipPlatform.FAZAA: return 'Fazaa';
      case ExternalPartnershipPlatform.ESAAD: return 'Esaad';
      case ExternalPartnershipPlatform.OTHER: return 'Other';
    }
  }

  String _offerTypeLabel(ExternalPartnershipOfferType t) {
    switch (t) {
      case ExternalPartnershipOfferType.BOGO: return 'BOGO';
      case ExternalPartnershipOfferType.PERCENT_OFF: return 'Percent Off';
      case ExternalPartnershipOfferType.VOUCHER: return 'Voucher';
      case ExternalPartnershipOfferType.MEMBERSHIP: return 'Membership';
      case ExternalPartnershipOfferType.OTHER: return 'Other';
    }
  }

  // ── Kmstry Offers Tab (hidden in UI — kept for future use) ─────────────────
  // ignore: unused_element
  Widget _buildOffersTab(ColorScheme colors, bool isDark, Color kBorder) {
    return Column(
      children: [
        Expanded(
          child: _offers.isEmpty
              ? _buildEmpty(
                  icon: Icons.local_offer_outlined,
                  title: 'No offers yet',
                  subtitle:
                      'Create a native offer (BOGO, discount, free item) that users can redeem directly in the app.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
                    itemCount: _offers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) =>
                        _OfferCard(item: _offers[i], venueId: widget.venueId, onDeleted: _load),
                  ),
                ),
        ),
        _AddButton(
          label: 'Create Offer',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddVenueOfferPage(venueId: widget.venueId),
            ),
          ).then((_) => _load()),
        ),
      ],
    );
  }

  Widget _buildEmpty({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, size: 38, color: AppColors.blueDark),
            ),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurface.withValues(alpha: 0.6),
                    height: 1.5)),
          ],
        ),
      ),
    );
  }
}

// ── Cards ─────────────────────────────────────────────────────────────────────

class _PartnershipCard extends StatelessWidget {
  final ExternalPartnershipModel item;
  final String venueId;
  final bool canManage;
  final VoidCallback onDeleted;
  final VoidCallback onEdited;

  const _PartnershipCard({
    required this.item,
    required this.venueId,
    required this.canManage,
    required this.onDeleted,
    required this.onEdited,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = _statusColor(item.status, colors);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0D1525)
            : Colors.black.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? const Color(0xFF162040)
              : Colors.black.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        children: [
          _PlatformBadge(platform: item.platform),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.platformDisplayName,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface)),
                const SizedBox(height: 2),
                Text(item.offerLabel,
                    style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurface.withValues(alpha: 0.72))),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _statusLabel(item.status),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusColor),
                  ),
                ),
              ],
            ),
          ),
          if (canManage) ...[
            IconButton(
              icon: Icon(Icons.edit_outlined,
                  size: 18, color: colors.onSurface.withValues(alpha: 0.5)),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditExternalPartnershipPage(
                    venueId: venueId,
                    item: item,
                  ),
                ),
              ).then((saved) { if (saved == true) onEdited(); }),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  size: 18, color: colors.error.withValues(alpha: 0.7)),
              onPressed: () => _confirmDelete(context),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Partnership?'),
        content: Text(
            'Remove the ${item.platformDisplayName} partnership from your venue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Remove',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ExternalPartnershipRepository().delete(item.venueId, item.id);
      onDeleted();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    }
  }

  Color _statusColor(ExternalPartnershipStatus s, ColorScheme colors) {
    switch (s) {
      case ExternalPartnershipStatus.ACTIVE:
        return AppColors.teal;
      case ExternalPartnershipStatus.PENDING_REVIEW:
        return AppColors.orange;
      case ExternalPartnershipStatus.REJECTED:
        return colors.error;
      case ExternalPartnershipStatus.EXPIRED:
      case ExternalPartnershipStatus.HIDDEN:
        return colors.onSurface.withValues(alpha: 0.4);
    }
  }

  String _statusLabel(ExternalPartnershipStatus s) {
    switch (s) {
      case ExternalPartnershipStatus.ACTIVE:
        return 'Active';
      case ExternalPartnershipStatus.PENDING_REVIEW:
        return 'Pending Review';
      case ExternalPartnershipStatus.REJECTED:
        return 'Rejected';
      case ExternalPartnershipStatus.EXPIRED:
        return 'Expired';
      case ExternalPartnershipStatus.HIDDEN:
        return 'Hidden';
    }
  }
}

class _OfferCard extends StatelessWidget {
  final VenueOfferModel item;
  final String venueId;
  final VoidCallback onDeleted;

  const _OfferCard(
      {required this.item, required this.venueId, required this.onDeleted});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isInactive = !item.isActive || item.isExpired || item.isFullyRedeemed;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.local_offer_rounded,
                size: 22, color: colors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(item.title,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isInactive
                                  ? colors.onSurface.withValues(alpha: 0.4)
                                  : null)),
                    ),
                    if (isInactive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.onSurface.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.isExpired
                              ? 'Expired'
                              : item.isFullyRedeemed
                                  ? 'Limit reached'
                                  : 'Inactive',
                          style: TextStyle(
                              fontSize: 10,
                              color:
                                  colors.onSurface.withValues(alpha: 0.5)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(item.typeDisplayName,
                    style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurface.withValues(alpha: 0.55))),
                if (item.maxRedemptions != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${item.redemptionsUsed}/${item.maxRedemptions} redeemed',
                      style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurface.withValues(alpha: 0.4)),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 20, color: colors.error.withValues(alpha: 0.7)),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Offer?'),
        content: Text('Delete "${item.title}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await VenueOfferRepository().delete(venueId, item.id);
      onDeleted();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    }
  }
}

class _PlatformBadge extends StatelessWidget {
  final ExternalPartnershipPlatform platform;

  const _PlatformBadge({required this.platform});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.blue.withValues(alpha: 0.22),
            AppColors.teal.withValues(alpha: 0.18),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.28)),
      ),
      child: Center(
        child: Text(
          _initials,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.blueDark),
        ),
      ),
    );
  }

  String get _initials {
    switch (platform) {
      case ExternalPartnershipPlatform.THE_ENTERTAINER:
        return 'ENT';
      case ExternalPartnershipPlatform.COBONE:
        return 'COB';
      case ExternalPartnershipPlatform.GROUPON:
        return 'GRP';
      case ExternalPartnershipPlatform.FAZAA:
        return 'FAZ';
      case ExternalPartnershipPlatform.ESAAD:
        return 'ESA';
      case ExternalPartnershipPlatform.OTHER:
        return '•••';
    }
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: active
              ? AppColors.blue.withValues(alpha: isDark ? 0.16 : 0.10)
              : (isDark
                  ? const Color(0xFF0D1525)
                  : Colors.black.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? AppColors.blue.withValues(alpha: 0.55)
                : (isDark
                    ? const Color(0xFF162040)
                    : Colors.black.withValues(alpha: 0.08)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active
                      ? AppColors.blue
                      : colors.onSurface.withValues(alpha: 0.72),
                ),
              ),
            ),
            Icon(
              Icons.expand_more_rounded,
              size: 17,
              color: active
                  ? AppColors.blue
                  : colors.onSurface.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _AddButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottom),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(
                color: Colors.black.withValues(alpha: 0.07))),
      ),
      child: PrimaryButton(label: label, onPressed: onTap),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final bool isDark;
  final String text;

  const _InfoBanner({required this.isDark, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF3B82F6),
                  height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filtre sheet tile'ı — map/add-partnership ile aynı görünüm ──────────────────
class _SheetTile extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final Color kCard, kBorder, kText;
  final VoidCallback onTap;

  const _SheetTile({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.kCard,
    required this.kBorder,
    required this.kText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.blue.withValues(alpha: isDark ? 0.16 : 0.10)
                : kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.blue.withValues(alpha: 0.62) : kBorder,
              width: selected ? 1.2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: selected
                      ? const LinearGradient(
                          colors: [AppColors.blue, AppColors.teal],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  border: Border.all(
                    color: selected
                        ? Colors.transparent
                        : kText.withValues(alpha: isDark ? 0.42 : 0.28),
                    width: 1.6,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 17)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? kText
                        : kText.withValues(alpha: isDark ? 0.78 : 0.72),
                    fontSize: 14.5,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.done_rounded, color: AppColors.teal, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
