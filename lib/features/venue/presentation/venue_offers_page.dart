import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_model.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_repository.dart';
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
    final kBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.07);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Offers & Benefits',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: colors.onSurface),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _PartnershipCard(
                          item: filtered[i],
                          venueId: widget.venueId,
                          onDeleted: _load,
                          onEdited: _load,
                        ),
                      ),
                    ),
        ),
        _AddButton(
          label: 'Add Partnership',
          icon: Icons.add,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddExternalPartnershipPage(venueId: widget.venueId),
            ),
          ).then((_) => _load()),
        ),
      ],
    );
  }

  void _showPlatformFilter() {
    final options = ExternalPartnershipPlatform.values
        .where((p) => _partnerships.any((x) => x.platform == p))
        .toList();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text('Filter by Platform',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...options.map((p) => ListTile(
                  title: Text(_platformLabel(p)),
                  trailing: _filterPlatform == p
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () {
                    setState(() => _filterPlatform =
                        _filterPlatform == p ? null : p);
                    Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showOfferTypeFilter() {
    final options = ExternalPartnershipOfferType.values
        .where((t) => _partnerships.any((x) => x.offerType == t))
        .toList();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text('Filter by Benefit Type',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...options.map((t) => ListTile(
                  title: Text(_offerTypeLabel(t)),
                  trailing: _filterOfferType == t
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () {
                    setState(() => _filterOfferType =
                        _filterOfferType == t ? null : t);
                    Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 8),
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
          icon: Icons.add,
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
            Icon(icon, size: 56, color: colors.onSurface.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurface.withValues(alpha: 0.5),
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
  final VoidCallback onDeleted;
  final VoidCallback onEdited;

  const _PartnershipCard({
    required this.item,
    required this.venueId,
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
          _PlatformBadge(platform: item.platform),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.platformDisplayName,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(item.offerLabel,
                    style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurface.withValues(alpha: 0.6))),
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
        return const Color(0xFF00A89E);
      case ExternalPartnershipStatus.PENDING_REVIEW:
        return const Color(0xFFF59E0B);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          _initials,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? colors.primary.withValues(alpha: 0.12)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? colors.primary.withValues(alpha: 0.4)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
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
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active
                      ? colors.primary
                      : colors.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            Icon(
              Icons.expand_more,
              size: 16,
              color: active
                  ? colors.primary
                  : colors.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _AddButton(
      {required this.label, required this.icon, required this.onTap});

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
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
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
        color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline,
              size: 16, color: Color(0xFF3B82F6)),
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
