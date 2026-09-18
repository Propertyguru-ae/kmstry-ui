import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/app_back_button.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/core/user/user_session.dart';
import 'package:kmstry_frontend/core/user/premium_feature.dart';
import 'package:kmstry_frontend/core/user/premium_gate.dart';
import 'package:kmstry_frontend/features/reports/presentation/report_user_sheet.dart';

// ─── Brand palette ────────────────────────────────────────────────────────────
const _kMagenta = Color(0xFFE020D8);
const _kTurkuaz = Color(0xFF1FD9A8);
const _kMavi = Color(0xFF1A9FE8);
const _kTuruncu = Color(0xFFF08838);
const _kRed = Color(0xFFEF4444);

// ─── Page ─────────────────────────────────────────────────────────────────────

class PersonalEventDetailPage extends StatefulWidget {
  final VenueUpcomingEvent event;
  final String venueId;

  /// Etkinliğin ait olduğu mekanın kartını göstermek için opsiyonel bilgiler.
  /// Verilmezse venue kartı gizlenir.
  final String? venueName;
  final String? venueAddress;
  final String? venuePhotoUrl;

  const PersonalEventDetailPage({
    super.key,
    required this.event,
    required this.venueId,
    this.venueName,
    this.venueAddress,
    this.venuePhotoUrl,
  });

  @override
  State<PersonalEventDetailPage> createState() =>
      _PersonalEventDetailPageState();
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
    _event = widget.event;
    _rsvpCount = widget.event.rsvpCount;
    _capacity = widget.event.capacity;
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

  Future<void> _reportEvent() async {
    await showReportUserSheet(
      context,
      title: 'Why are you reporting this event?',
      eventId: _event.id,
    );
  }

  Future<void> _reportOffer() async {
    final offerId = _event.offerId;
    if (offerId == null || offerId.isEmpty) return;
    await showReportUserSheet(
      context,
      title: 'Why are you reporting this offer?',
      venueOfferId: offerId,
    );
  }

  Future<void> _reportBenefit(EventPartnerBenefit benefit) async {
    if (benefit.id.isEmpty) return;
    await showReportUserSheet(
      context,
      title: 'Why are you reporting this benefit?',
      venueBenefitId: benefit.id,
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
          _rsvpCount = map['rsvpCount'] is num
              ? (map['rsvpCount'] as num).toInt()
              : 0;
          _capacity = map['capacity'] is num
              ? (map['capacity'] as num).toInt()
              : null;
          _userHasRsvp = map['userHasRsvp'] == true;
          _rsvpOpensAt = DateTime.tryParse(
            map['rsvpOpensAt']?.toString() ?? '',
          );
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
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
        if (mounted)
          setState(() {
            _userHasRsvp = false;
            _rsvpCount = (_rsvpCount - 1).clamp(0, 999999);
          });
      } else {
        await _api.post(
          '/venues/${widget.venueId}/events/${widget.event.id}/rsvp',
          headers: {'Authorization': 'Bearer $token'},
          body: {},
        );
        if (mounted) {
          setState(() {
            _userHasRsvp = true;
            _rsvpCount++;
          });
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
    final kBg = isDark ? const Color(0xFF0D1525) : Colors.white;
    final kText = isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827);
    final kDim = isDark ? const Color(0xFF9AA8C2) : const Color(0xFF5D6B7B);

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kBg = isDark ? const Color(0xFF06091A) : Colors.white;
    final kCard = isDark ? const Color(0xFF0D1525) : const Color(0xFFF3F6FA);
    final kBorder = isDark ? const Color(0xFF162040) : const Color(0xFFD9E1EA);
    final kText = isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827);
    final kDim = isDark ? const Color(0xFF9AA8C2) : const Color(0xFF5D6B7B);
    final kLabel = isDark ? const Color(0xFF44597A) : const Color(0xFF8794A6);
    final kFaint = isDark ? const Color(0xFF3A5070) : const Color(0xFF9AA6B6);

    final event = _event;
    final photos = event.photos.isNotEmpty
        ? event.photos
        : (event.photo != null ? [event.photo!] : <String>[]);
    final coverPhoto = photos.isNotEmpty ? photos.first : null;
    final isFree = event.priceAed == null || event.priceAed == 0;
    final isFull = _capacity != null && _rsvpCount >= _capacity!;
    final earlyLocked = _earlyAccessLocked; // T46: general RSVP not open yet

    return Scaffold(
      backgroundColor: kBg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kMagenta))
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(_error!, style: TextStyle(color: kDim)),
              ),
            )
          : Stack(
              children: [
                RefreshIndicator(
                  onRefresh: _loadDetail,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: const EdgeInsets.only(bottom: 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── COVER HERO ─────────────────────────────────────
                        _EventCover(photo: coverPhoto, pageBg: kBg),

                        // ── TITLE + CHIPS (cover'a biner) ──────────────────
                        Transform.translate(
                          offset: const Offset(0, -36),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.title,
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                    color: kText,
                                    height: 1.15,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 7,
                                  runSpacing: 7,
                                  children: [
                                    _Chip(
                                      icon: isFree
                                          ? Icons.confirmation_num_outlined
                                          : Icons.local_activity_outlined,
                                      label: isFree
                                          ? 'Free entry'
                                          : '${event.currency} ${event.priceAed} min.',
                                      color: isFree ? _kTurkuaz : _kTuruncu,
                                      isDark: isDark,
                                    ),
                                    if (event.isRecurring)
                                      _Chip(
                                        icon: Icons.repeat_rounded,
                                        label: 'Recurring',
                                        color: _kMagenta,
                                        isDark: isDark,
                                      ),
                                    _Chip(
                                      icon: Icons.people_outline_rounded,
                                      label: _capacity != null
                                          ? '$_rsvpCount / $_capacity interested'
                                          : '$_rsvpCount interested',
                                      color: isFull ? _kRed : _kMavi,
                                      isDark: isDark,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ── CONTENT (cover altını biraz yukarı çeker) ──────
                        Transform.translate(
                          offset: const Offset(0, -20),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // DATE & TIME
                                _InfoCard(
                                  icon: Icons.calendar_month_rounded,
                                  accent: _kTurkuaz,
                                  label: 'Date & Time',
                                  value: event.formattedDate,
                                  sub: _durationLabel(
                                    event.endAt.difference(event.startAt),
                                  ),
                                  kCard: kCard,
                                  kBorder: kBorder,
                                  kText: kText,
                                  kLabel: kLabel,
                                  kFaint: kFaint,
                                ),
                                const SizedBox(height: 10),

                                // ENTRY
                                _InfoCard(
                                  icon: Icons.local_activity_rounded,
                                  accent: _kTuruncu,
                                  label: 'Entry',
                                  value: isFree
                                      ? 'Free · No ticket required'
                                      : '${event.currency} ${event.priceAed} minimum spend',
                                  kCard: kCard,
                                  kBorder: kBorder,
                                  kText: kText,
                                  kLabel: kLabel,
                                  kFaint: kFaint,
                                ),

                                // VENUE CARD
                                if ((widget.venueName ?? '')
                                    .trim()
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  _VenueCard(
                                    name: widget.venueName!,
                                    address: widget.venueAddress,
                                    photoUrl: widget.venuePhotoUrl,
                                    onTap: () => Navigator.pop(context),
                                    kCard: kCard,
                                    kText: kText,
                                    kFaint: kFaint,
                                  ),
                                ],

                                // ATTENDEES
                                if (_rsvpCount > 0) ...[
                                  const SizedBox(height: 14),
                                  _AttendeesRow(
                                    count: _rsvpCount,
                                    kFaint: kFaint,
                                  ),
                                ],

                                // RECURRING BANNER
                                if (event.isRecurring) ...[
                                  const SizedBox(height: 14),
                                  _RecurringBanner(
                                    label: _recurrenceLabel(event),
                                  ),
                                ],

                                // ABOUT
                                if (event.description != null &&
                                    event.description!.isNotEmpty) ...[
                                  const SizedBox(height: 20),
                                  _DotTitle(
                                    color: _kMagenta,
                                    label: 'About',
                                    kText: kText,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    event.description!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: kDim,
                                      height: 1.7,
                                    ),
                                  ),
                                ],

                                // KMSTRY OFFER
                                if (event.offerType != null) ...[
                                  const SizedBox(height: 20),
                                  _DotTitle(
                                    color: _kTuruncu,
                                    label: 'Kmstry Offer',
                                    kText: kText,
                                  ),
                                  const SizedBox(height: 8),
                                  _OfferCard(
                                    conditions: event.offerTitle,
                                    type: event.offerType,
                                    price: event.offerPrice,
                                    isDark: isDark,
                                    kCard: kCard,
                                    kBorder: kBorder,
                                    kText: kText,
                                    kDim: kDim,
                                  ),
                                  if ((event.offerId ?? '').isNotEmpty)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed: _reportOffer,
                                        icon: const Icon(
                                          Icons.flag_outlined,
                                          size: 16,
                                        ),
                                        label: const Text('Report offer'),
                                      ),
                                    ),
                                ],

                                // PARTNER BENEFITS
                                if (event.partnershipBenefits.isNotEmpty) ...[
                                  const SizedBox(height: 20),
                                  _DotTitle(
                                    color: _kMavi,
                                    label: 'Partner Benefits',
                                    kText: kText,
                                  ),
                                  const SizedBox(height: 8),
                                  ...event.partnershipBenefits.map(
                                    (b) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: kCard,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(color: kBorder),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                color: _kMavi.withValues(
                                                  alpha: 0.12,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(9),
                                              ),
                                              child: const Icon(
                                                Icons.handshake_outlined,
                                                size: 16,
                                                color: _kMavi,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    b.platformLabel ??
                                                        b.platform,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: kText,
                                                    ),
                                                  ),
                                                  Text(
                                                    b.offerLabel,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: kDim,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Report benefit',
                                              onPressed: () =>
                                                  _reportBenefit(b),
                                              icon: const Icon(
                                                Icons.flag_outlined,
                                                size: 18,
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
                  ),
                ),

                // ── Floating back button ───────────────────────────────
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 14,
                  child: AppBackButton.onCover(
                    onTap: () => Navigator.pop(context),
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  right: 14,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Report event',
                      onPressed: _reportEvent,
                      icon: const Icon(
                        Icons.flag_outlined,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),

      // ── RSVP / Attend button ────────────────────────────────────────────────
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                child: _buildAttendButton(
                  isDark: isDark,
                  kCard: kCard,
                  kBorder: kBorder,
                  kDim: kDim,
                  isFull: isFull,
                  earlyLocked: earlyLocked,
                ),
              ),
            ),
    );
  }

  String _durationLabel(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h <= 0 && m <= 0) return '';
    if (h > 0 && m > 0) return 'Duration: ${h}h ${m}m';
    if (h > 0) return 'Duration: $h hour${h > 1 ? 's' : ''}';
    return 'Duration: ${m}m';
  }

  String _recurrenceLabel(VenueUpcomingEvent event) {
    final freq = event.recurrence?.frequency.toLowerCase();
    switch (freq) {
      case 'daily':
        return 'Repeats every day';
      case 'weekly':
        return 'Repeats every week';
      case 'monthly':
        return 'Repeats every month';
      default:
        return 'This is a recurring event';
    }
  }

  /// Alt sabit Attend butonu — mockup'taki magenta gradient CTA; diğer
  /// durumlarda (katılıyor / dolu) muted stile döner. Tüm RSVP mantığı korunur.
  Widget _buildAttendButton({
    required bool isDark,
    required Color kCard,
    required Color kBorder,
    required Color kDim,
    required bool isFull,
    required bool earlyLocked,
  }) {
    final showGradient =
        earlyLocked || (!_userHasRsvp && !isFull); // birincil CTA görünümü
    final disabled = _rsvping || (isFull && !_userHasRsvp && !earlyLocked);

    final label = earlyLocked
        ? '$_opensInLabel · KMSTRY+ early'
        : _userHasRsvp
        ? 'Remove from my calendar'
        : isFull
        ? 'Event is full'
        : 'Add to my calendar';
    final icon = earlyLocked
        ? Icons.lock_clock_rounded
        : _userHasRsvp
        ? Icons.check_circle_outline_rounded
        : isFull
        ? Icons.block_rounded
        : Icons.person_add_alt_1_rounded;
    final fg = showGradient ? Colors.white : kDim;

    return SizedBox(
      height: 54,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: disabled
              ? null
              : earlyLocked
              ? _openEarlyAccessUpsell
              : _toggleRsvp,
          child: Ink(
            decoration: BoxDecoration(
              gradient: showGradient
                  ? const LinearGradient(
                      colors: [Color(0xFF8B10C0), _kMagenta],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: showGradient ? null : kCard,
              borderRadius: BorderRadius.circular(16),
              border: showGradient ? null : Border.all(color: kBorder),
              boxShadow: showGradient
                  ? [
                      BoxShadow(
                        color: _kMagenta.withValues(alpha: 0.32),
                        blurRadius: 22,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: _rsvping
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 18, color: fg),
                        const SizedBox(width: 9),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: fg,
                          ),
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

// ─── Cover hero ─────────────────────────────────────────────────────────────

class _EventCover extends StatelessWidget {
  final String? photo;
  final Color pageBg;
  const _EventCover({required this.photo, required this.pageBg});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photo != null && photo!.isNotEmpty)
            CachedImage(photo!, fit: BoxFit.cover)
          else ...[
            // Foto yoksa logo renkli mesh arka plan
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1A0828),
                    Color(0xFF0A1840),
                    Color(0xFF0A2010),
                  ],
                ),
              ),
            ),
            Align(
              alignment: const Alignment(-0.5, -0.2),
              child: _glow(_kMagenta.withValues(alpha: 0.22), 240),
            ),
            Align(
              alignment: const Alignment(0.6, 0.4),
              child: _glow(_kTurkuaz.withValues(alpha: 0.16), 220),
            ),
          ],
          // Alt zemin geçişi
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 130,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, pageBg],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(Color color, double size) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    ),
  );
}

// ─── Info card (Date & Time, Entry) ───────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final String? sub;
  final Color kCard, kBorder, kText, kLabel, kFaint;

  const _InfoCard({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    this.sub,
    required this.kCard,
    required this.kBorder,
    required this.kText,
    required this.kLabel,
    required this.kFaint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 17, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: kLabel,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: kText,
                  ),
                ),
                if (sub != null && sub!.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(sub!, style: TextStyle(fontSize: 11, color: kFaint)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Venue card ───────────────────────────────────────────────────────────────

class _VenueCard extends StatelessWidget {
  final String name;
  final String? address;
  final String? photoUrl;
  final VoidCallback onTap;
  final Color kCard, kText, kFaint;

  const _VenueCard({
    required this.name,
    required this.address,
    required this.photoUrl,
    required this.onTap,
    required this.kCard,
    required this.kText,
    required this.kFaint,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kTurkuaz.withValues(alpha: 0.20)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: (photoUrl != null && photoUrl!.trim().isNotEmpty)
                    ? CachedImage(
                        photoUrl!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF1A1020), Color(0xFF0A1840)],
                          ),
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          size: 19,
                          color: _kTurkuaz,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: kText,
                      ),
                    ),
                    if ((address ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 12,
                            color: _kMavi,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              address!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: kFaint),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: kFaint),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Attendees row ────────────────────────────────────────────────────────────

class _AttendeesRow extends StatelessWidget {
  final int count;
  final Color kFaint;
  const _AttendeesRow({required this.count, required this.kFaint});

  static const _avatarGradients = [
    [Color(0xFF8B10C0), _kMagenta],
    [Color(0xFF0F8060), _kTurkuaz],
    [Color(0xFF0A5090), _kMavi],
  ];

  @override
  Widget build(BuildContext context) {
    final shown = count.clamp(0, 3);
    return Row(
      children: [
        for (int i = 0; i < shown; i++)
          Container(
            width: 28,
            height: 28,
            margin: EdgeInsets.only(left: i == 0 ? 0 : -7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: _avatarGradients[i % _avatarGradients.length],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: const Color(0xFF06091A), width: 2),
            ),
            child: const Icon(
              Icons.person_rounded,
              size: 14,
              color: Colors.white,
            ),
          ),
        const SizedBox(width: 10),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$count ${count == 1 ? 'person' : 'people'}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5B8CFF),
                ),
              ),
              TextSpan(
                text: ' interested',
                style: TextStyle(fontSize: 12, color: kFaint),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Recurring banner ─────────────────────────────────────────────────────────

class _RecurringBanner extends StatelessWidget {
  final String label;
  const _RecurringBanner({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _kMagenta.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kMagenta.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.repeat_rounded, size: 16, color: _kMagenta),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: _kMagenta.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dot section title ────────────────────────────────────────────────────────

class _DotTitle extends StatelessWidget {
  final Color color;
  final String label;
  final Color kText;
  const _DotTitle({
    required this.color,
    required this.label,
    required this.kText,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: kText,
          ),
        ),
      ],
    );
  }
}

// ─── Chip ─────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;

  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
  });

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
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
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
      case 'BUFFET':
        return 'Buffet';
      case 'SET_MENU':
        return 'Set Menu';
      case 'OPEN_DRINK':
        return 'Open Drink';
      case 'OPEN_FOOD':
        return 'Open Food';
      case 'PERCENT_OFF':
        return 'Percent off';
      case 'FIXED_DISCOUNT':
        return 'Fixed discount';
      case 'FREE_ITEM':
        return 'Free item';
      case 'BUNDLE':
        return 'Bundle deal';
      case 'BOGO':
        return 'Buy one get one';
      default:
        return '';
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
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _kTuruncu.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.local_offer_outlined,
              size: 16,
              color: _kTuruncu,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _typeLabel().isNotEmpty ? _typeLabel() : 'Offer',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kText,
                  ),
                ),
                if (conditions != null && conditions!.trim().isNotEmpty)
                  Text(
                    conditions!,
                    style: TextStyle(fontSize: 12, color: kDim),
                  ),
              ],
            ),
          ),
          if (price != null)
            Text(
              price!.toStringAsFixed(0),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _kTuruncu,
              ),
            ),
        ],
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
        border: Border.all(color: _kMagenta.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "You're In! 🎉",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: kText,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),

            Text(
              'Your spot is confirmed for "$eventTitle". '
              "We can't wait to see you there. Get ready for a night to remember! ✨",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: kText.withValues(alpha: 0.75),
                height: 1.65,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Good vibes only. Make it count. ✨',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
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
