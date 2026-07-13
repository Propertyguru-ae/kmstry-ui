import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/core/user/user_session.dart';
import 'package:kmstry_frontend/core/user/premium_feature.dart';
import 'package:kmstry_frontend/core/user/premium_gate.dart';

// ─── Brand palette ────────────────────────────────────────────────────────────
const _kMagenta = Color(0xFFE020D8);
const _kTurkuaz = Color(0xFF1FD9A8);
const _kMavi    = Color(0xFF1A9FE8);
const _kTuruncu = Color(0xFFF08838);
const _kRed     = Color(0xFFEF4444);

// ─── Page ─────────────────────────────────────────────────────────────────────

class PersonalEventDetailPage extends StatefulWidget {
  final VenueUpcomingEvent event;
  final String venueId;

  const PersonalEventDetailPage({
    super.key,
    required this.event,
    required this.venueId,
  });

  @override
  State<PersonalEventDetailPage> createState() => _PersonalEventDetailPageState();
}

class _PersonalEventDetailPageState extends State<PersonalEventDetailPage> {
  final _api = ApiClient();

  bool _loading = true;
  bool _rsvping = false;
  String? _error;

  late int _rsvpCount;
  int? _capacity;
  bool _userHasRsvp = false;
  DateTime? _rsvpOpensAt; // T46: general RSVP open time (publish + 24h)
  late VenueUpcomingEvent _event;

  @override
  void initState() {
    super.initState();
    _event     = widget.event;
    _rsvpCount = widget.event.rsvpCount;
    _capacity  = widget.event.capacity;
    _loadDetail();
    // Premium status drives the early-access gate; refresh once loaded.
    UserSession.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// True when the free user must still wait for general RSVP to open.
  bool get _earlyAccessLocked =>
      !UserSession.instance.isPremium &&
      _rsvpOpensAt != null &&
      DateTime.now().isBefore(_rsvpOpensAt!) &&
      !_userHasRsvp;

  String get _opensInLabel {
    final opensAt = _rsvpOpensAt;
    if (opensAt == null) return 'Opens soon';
    final d = opensAt.difference(DateTime.now());
    if (d.inHours >= 1) return 'Opens in ${d.inHours}h';
    if (d.inMinutes >= 1) return 'Opens in ${d.inMinutes}m';
    return 'Opens soon';
  }

  Future<void> _openEarlyAccessUpsell() async {
    await PremiumGate.ensure(
      context,
      PremiumFeature.priorityEventAccess,
      title: 'RSVP opens 24h early with KMSTRY+',
      message:
          'KMSTRY+ members can RSVP to events 24 hours before everyone else.',
      icon: Icons.event_available_rounded,
    );
  }

  Future<void> _loadDetail() async {
    try {
      final token = await SecureStorage.getAccessToken();
      final data = await _api.get(
        '/venues/${widget.venueId}/events/${widget.event.id}',
        headers: {'Authorization': 'Bearer $token'},
      );
      final map = Map<String, dynamic>.from(data as Map);
      if (mounted) {
        setState(() {
          _event = VenueUpcomingEvent.fromJson(map);
          _rsvpCount  = map['rsvpCount'] is num ? (map['rsvpCount'] as num).toInt() : 0;
          _capacity   = map['capacity'] is num ? (map['capacity'] as num).toInt() : null;
          _userHasRsvp = map['userHasRsvp'] == true;
          _rsvpOpensAt = DateTime.tryParse(
            map['rsvpOpensAt']?.toString() ?? '',
          );
          _loading    = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _toggleRsvp() async {
    setState(() => _rsvping = true);
    try {
      final token = await SecureStorage.getAccessToken();
      if (_userHasRsvp) {
        await _api.delete(
          '/venues/${widget.venueId}/events/${widget.event.id}/rsvp',
          headers: {'Authorization': 'Bearer $token'},
        );
        if (mounted) setState(() { _userHasRsvp = false; _rsvpCount = (_rsvpCount - 1).clamp(0, 999999); });
      } else {
        await _api.post(
          '/venues/${widget.venueId}/events/${widget.event.id}/rsvp',
          headers: {'Authorization': 'Bearer $token'},
          body: {},
        );
        if (mounted) {
          setState(() { _userHasRsvp = true; _rsvpCount++; });
          _showRsvpSuccess();
        }
      }
    } catch (e) {
      if (mounted) {
        // T46: server rejected because general RSVP hasn't opened yet.
        if (e.toString().contains('EARLY_ACCESS_LOCKED')) {
          _openEarlyAccessUpsell();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()), backgroundColor: _kRed),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _rsvping = false);
    }
  }

  void _showRsvpSuccess() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kBg    = isDark ? const Color(0xFF0D1525) : Colors.white;
    final kText  = isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827);
    final kDim   = isDark ? const Color(0xFF9AA8C2) : const Color(0xFF5D6B7B);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RsvpSuccessSheet(
        eventTitle: _event.title,
        isDark: isDark,
        kBg: kBg,
        kText: kText,
        kDim: kDim,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final kBg     = isDark ? const Color(0xFF06091A) : Colors.white;
    final kCard   = isDark ? const Color(0xFF0D1525) : const Color(0xFFF3F6FA);
    final kBorder = isDark ? const Color(0xFF162040) : const Color(0xFFD9E1EA);
    final kText   = isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827);
    final kDim    = isDark ? const Color(0xFF9AA8C2) : const Color(0xFF5D6B7B);

    final event  = _event;
    final photos = event.photos.isNotEmpty
        ? event.photos
        : (event.photo != null ? [event.photo!] : <String>[]);
    final isFree = event.priceAed == null || event.priceAed == 0;
    final isFull = _capacity != null && _rsvpCount >= _capacity!;
    final earlyLocked = _earlyAccessLocked; // T46: general RSVP not open yet

    return Scaffold(
      backgroundColor: kBg,
      body: CustomScrollView(
        slivers: [
          // ── App bar ────────────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: kBg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            pinned: true,
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: kCard,
                      shape: BoxShape.circle,
                      border: Border.all(color: kBorder),
                    ),
                    child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: kText),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),

          // ── Content ────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20).copyWith(bottom: 120),
              child: _loading
                  ? const Center(child: Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: CircularProgressIndicator(color: _kMagenta),
                    ))
                  : _error != null
                      ? Center(child: Padding(
                          padding: const EdgeInsets.only(top: 60),
                          child: Text(_error!, style: TextStyle(color: kDim)),
                        ))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Photo gallery ────────────────────────────────
                            if (photos.isNotEmpty) ...[
                              _Gallery(photos: photos),
                              const SizedBox(height: 20),
                            ],

                            // ── Title ────────────────────────────────────────
                            Text(
                              event.title,
                              style: TextStyle(
                                fontSize: 24, fontWeight: FontWeight.w800,
                                letterSpacing: -0.5, color: kText, height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Chips ────────────────────────────────────────
                            Wrap(
                              spacing: 8, runSpacing: 8,
                              children: [
                                _Chip(
                                  icon: Icons.calendar_today_outlined,
                                  label: event.formattedDate,
                                  color: _kTurkuaz, isDark: isDark,
                                ),
                                _Chip(
                                  icon: isFree
                                      ? Icons.card_giftcard_outlined
                                      : Icons.confirmation_num_outlined,
                                  label: isFree
                                      ? 'Free entry'
                                      : '${event.currency} ${event.priceAed} min.',
                                  color: isFree ? _kTurkuaz : _kTuruncu, isDark: isDark,
                                ),
                                if (event.isRecurring)
                                  _Chip(
                                    icon: Icons.repeat_rounded,
                                    label: 'Recurring',
                                    color: _kMagenta, isDark: isDark,
                                  ),
                                _Chip(
                                  icon: Icons.people_outline_rounded,
                                  label: _capacity != null
                                      ? '$_rsvpCount / $_capacity attending'
                                      : '$_rsvpCount attending',
                                  color: isFull ? _kRed : _kMavi, isDark: isDark,
                                ),
                              ],
                            ),

                            // ── Description ──────────────────────────────────
                            if (event.description != null && event.description!.isNotEmpty) ...[
                              _divider(isDark),
                              _SectionLabel(icon: Icons.notes_rounded, label: 'About', color: _kMavi, kText: kText),
                              const SizedBox(height: 10),
                              Text(
                                event.description!,
                                style: TextStyle(fontSize: 14, color: kDim, height: 1.7),
                              ),
                            ],

                            // ── Kmstry Offer ──────────────────────────────────
                            if (event.offerType != null) ...[
                              _divider(isDark),
                              _SectionLabel(icon: Icons.local_offer_outlined, label: 'Kmstry Offer', color: _kTuruncu, kText: kText),
                              const SizedBox(height: 10),
                              _OfferCard(
                                conditions: event.offerTitle,
                                type: event.offerType,
                                price: event.offerPrice,
                                isDark: isDark, kCard: kCard, kBorder: kBorder, kText: kText, kDim: kDim,
                              ),
                            ],

                            // ── Partner Benefits ─────────────────────────────
                            if (event.partnershipBenefits.isNotEmpty) ...[
                              _divider(isDark),
                              _SectionLabel(icon: Icons.handshake_outlined, label: 'Partner Benefits', color: _kMavi, kText: kText),
                              const SizedBox(height: 10),
                              ...event.partnershipBenefits.map(
                                (b) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: kCard,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: kBorder),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 32, height: 32,
                                          decoration: BoxDecoration(
                                            color: _kMavi.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(Icons.handshake_outlined, size: 16, color: _kMavi),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(b.platformLabel ?? b.platform,
                                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText)),
                                              Text(b.offerLabel,
                                                  style: TextStyle(fontSize: 12, color: kDim)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
            ),
          ),
        ],
      ),

      // ── RSVP button ─────────────────────────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: _loading
              ? const SizedBox.shrink()
              : SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _rsvping
                        ? null
                        : earlyLocked
                            ? _openEarlyAccessUpsell
                            : (isFull && !_userHasRsvp)
                                ? null
                                : _toggleRsvp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: earlyLocked
                          ? _kMagenta
                          : _userHasRsvp
                              ? (isDark ? const Color(0xFF162040) : const Color(0xFFD9E1EA))
                              : isFull
                                  ? kCard
                                  : _kMagenta,
                      foregroundColor: earlyLocked
                          ? Colors.white
                          : _userHasRsvp
                              ? kDim
                              : isFull
                                  ? kDim
                                  : Colors.white,
                      disabledBackgroundColor: kCard,
                      disabledForegroundColor: kDim,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: _userHasRsvp || isFull
                            ? BorderSide(color: kBorder)
                            : BorderSide.none,
                      ),
                    ),
                    child: _rsvping
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                earlyLocked
                                    ? Icons.lock_clock_rounded
                                    : _userHasRsvp
                                        ? Icons.check_circle_outline_rounded
                                        : isFull
                                            ? Icons.block_rounded
                                            : Icons.how_to_reg_outlined,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                earlyLocked
                                    ? '$_opensInLabel · KMSTRY+ early'
                                    : _userHasRsvp
                                        ? 'You\'re attending — Cancel'
                                        : isFull
                                            ? 'Event is full'
                                            : 'Attend',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                  ),
                ),
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

Widget _divider(bool isDark) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Divider(
        height: 1,
        color: isDark ? const Color(0xFF162040) : const Color(0xFFD9E1EA),
      ),
    );

// ─── Chip ─────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;

  const _Chip({required this.icon, required this.label, required this.color, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color kText;

  const _SectionLabel({required this.icon, required this.label, required this.color, required this.kText});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kText)),
      ],
    );
  }
}

// ─── Offer card ───────────────────────────────────────────────────────────────

class _OfferCard extends StatelessWidget {
  final String? conditions;
  final String? type;
  final double? price;
  final bool isDark;
  final Color kCard, kBorder, kText, kDim;

  const _OfferCard({
    required this.conditions,
    required this.type,
    required this.price,
    required this.isDark,
    required this.kCard,
    required this.kBorder,
    required this.kText,
    required this.kDim,
  });

  String _typeLabel() {
    switch (type) {
      case 'BUFFET':     return 'Buffet';
      case 'SET_MENU':   return 'Set Menu';
      case 'OPEN_DRINK': return 'Open Drink';
      case 'OPEN_FOOD':  return 'Open Food';
      case 'PERCENT_OFF':    return 'Percent off';
      case 'FIXED_DISCOUNT': return 'Fixed discount';
      case 'FREE_ITEM':      return 'Free item';
      case 'BUNDLE':         return 'Bundle deal';
      case 'BOGO':           return 'Buy one get one';
      default:               return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _kTuruncu.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kTuruncu.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: _kTuruncu.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.local_offer_outlined, size: 16, color: _kTuruncu),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_typeLabel().isNotEmpty ? _typeLabel() : 'Offer',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText)),
                if (conditions != null && conditions!.trim().isNotEmpty)
                  Text(conditions!, style: TextStyle(fontSize: 12, color: kDim)),
              ],
            ),
          ),
          if (price != null)
            Text(price!.toStringAsFixed(0),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _kTuruncu)),
        ],
      ),
    );
  }
}

// ─── Gallery ──────────────────────────────────────────────────────────────────

class _Gallery extends StatelessWidget {
  final List<String> photos;
  const _Gallery({required this.photos});

  @override
  Widget build(BuildContext context) {
    if (photos.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          photos.first,
          width: double.infinity,
          height: 220,
          fit: BoxFit.cover,
        ),
      );
    }
    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            photos[i],
            width: 280,
            height: 180,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

// ─── RSVP success sheet ───────────────────────────────────────────────────────

class _RsvpSuccessSheet extends StatelessWidget {
  final String eventTitle;
  final bool isDark;
  final Color kBg, kText, kDim;

  const _RsvpSuccessSheet({
    required this.eventTitle,
    required this.isDark,
    required this.kBg,
    required this.kText,
    required this.kDim,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: _kMagenta.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "You're In! 🎉",
              style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800,
                color: kText, letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),

            Text(
              'Your spot is confirmed for "$eventTitle". '
              "We can't wait to see you there. Get ready for a night to remember! ✨",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: kText.withValues(alpha: 0.75), height: 1.65),
            ),
            const SizedBox(height: 6),
            Text(
              'Good vibes only. Make it count. ✨',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: _kTurkuaz,
              ),
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kMagenta,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text(
                  "Let's go! 🚀",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
