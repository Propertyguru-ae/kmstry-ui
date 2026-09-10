import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_deal_detail_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/personal_event_detail_page.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/venue_event_detail_page.dart';

/// Venue detay ve venue profil sayfalarında AYNI görünen, salt-görüntü içerik
/// bölümleri. Tek kaynak olması için burada tutulur (deals chip'leri, upcoming
/// events kartları). Renkler venue detay sayfasıyla birebir eşleşir.

// ── Ortak renkler / başlık ──────────────────────────────────────────────────

bool _isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
Color _cardSurface(BuildContext c) =>
    _isDark(c) ? const Color(0xFF0D1525) : const Color(0xFFF4F7FB);
Color _cardBorder(BuildContext c) =>
    _isDark(c) ? const Color(0xFF162040) : Colors.black.withValues(alpha: 0.08);
Color _textPrimary(BuildContext c) =>
    _isDark(c) ? Colors.white : const Color(0xFF0F172A);
Color _textFaint(BuildContext c) =>
    _isDark(c) ? const Color(0xFF7E93B4) : const Color(0xFF6B7684);

/// Bölüm başlığı: renkli logo noktası + başlık (venue detay sayfasıyla AYNI
/// stil). Hem venue detay hem venue profil sayfası bunu kullanır ki tüm
/// başlıklar tutarlı görünsün. [trailing] verilirse sağa yaslanır (ör. Edit).
Widget venueSectionTitle(
  BuildContext context,
  Color dotColor,
  String title, {
  Widget? trailing,
}) {
  final isDark = _isDark(context);
  final left = Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
      ),
      const SizedBox(width: 7),
      Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: isDark ? const Color(0xFFC8D8F0) : _textPrimary(context),
        ),
      ),
    ],
  );
  if (trailing == null) return left;
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [left, trailing],
  );
}

// ── Deals & discounts (tek satır, yatay kaydırılabilir chip'ler) ──────────────

class VenueDealsChipRow extends StatelessWidget {
  final List<ExternalPartnershipModel> partnerships;
  final String venueName;

  const VenueDealsChipRow({
    super.key,
    required this.partnerships,
    required this.venueName,
  });

  @override
  Widget build(BuildContext context) {
    if (partnerships.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        venueSectionTitle(context, AppColors.orange, 'Deals & discounts'),
        const SizedBox(height: 10),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: partnerships.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, i) => _chip(context, partnerships[i]),
          ),
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, ExternalPartnershipModel p) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VenueDealDetailPage(deal: p, venueName: venueName),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: _isDark(context)
                ? Colors.white.withValues(alpha: 0.04)
                : const Color(0xFFF8FBFD),
            border: Border.all(color: AppColors.orange.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.local_offer_outlined,
                color: AppColors.orange,
                size: 15,
              ),
              const SizedBox(width: 7),
              Text(
                p.platformDisplayName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Upcoming events (venue detaydaki kart tasarımının aynısı) ─────────────────

class VenueUpcomingEventsSection extends StatelessWidget {
  final List<VenueUpcomingEvent> events;
  final String venueId;
  final String venueName;
  final String? venueAddress;
  final String? venuePhotoUrl;
  final bool openAsVenueMember;

  const VenueUpcomingEventsSection({
    super.key,
    required this.events,
    required this.venueId,
    required this.venueName,
    this.venueAddress,
    this.venuePhotoUrl,
    this.openAsVenueMember = false,
  });

  /// Bu haftanın (önümüzdeki 7 gün) upcoming event'lerini süzer: bitmemiş VE
  /// başlangıcı şu andan itibaren 7 gün içinde olan event'ler. Geçmiş event'ler
  /// ve bir haftadan uzak event'ler listelenmez.
  static List<VenueUpcomingEvent> weeklyUpcoming(
    List<VenueUpcomingEvent> events,
  ) {
    final now = DateTime.now();
    final weekAhead = now.add(const Duration(days: 7));
    return events
        .where(
          (e) =>
              e.endAt.toLocal().isAfter(now) &&
              e.startAt.toLocal().isBefore(weekAhead),
        )
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  /// Listede gösterilecek (bu haftaki) en az bir event var mı? Üst widget'ın
  /// boş bölüm için başlık/boşluk çizmemesi için.
  static bool hasUpcoming(List<VenueUpcomingEvent> events) =>
      weeklyUpcoming(events).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    // Yalnızca bu haftanın (önümüzdeki 7 gün) bitmemiş event'leri listelenir.
    final upcoming = weeklyUpcoming(events);
    if (upcoming.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        venueSectionTitle(context, AppColors.orange, 'Upcoming Events'),
        const SizedBox(height: 10),
        ...upcoming.map((e) => _eventCard(context, e)),
      ],
    );
  }

  Widget _eventCard(BuildContext context, VenueUpcomingEvent event) {
    final paid = event.priceAed != null;
    final accent = paid ? AppColors.orange : AppColors.teal;
    final imgUrl = event.photos.isNotEmpty ? event.photos.first : event.photo;
    final isDark = _isDark(context);
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => openAsVenueMember
              ? VenueEventDetailPage(event: event, venueId: venueId)
              : PersonalEventDetailPage(
                  event: event,
                  venueId: venueId,
                  venueName: venueName,
                  venueAddress: venueAddress,
                  venuePhotoUrl: venuePhotoUrl,
                ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(11, 11, 13, 11),
        decoration: BoxDecoration(
          color: _cardSurface(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _cardBorder(context)),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 34,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 11),
            if (imgUrl != null && imgUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: CachedImage(
                  imgUrl,
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  errorWidget: (ctx) => _iconTile(accent, paid),
                ),
              )
            else
              _iconTile(accent, paid),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    event.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? const Color(0xFFEEF2FF)
                          : _textPrimary(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule_rounded, size: 12, color: accent),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          event.formattedDate,
                          style: TextStyle(
                            fontSize: 11,
                            color: _textFaint(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accent.withValues(alpha: 0.24)),
              ),
              child: Text(
                paid ? '${event.priceAed} AED' : 'Free',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconTile(Color accent, bool paid) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(
        paid ? Icons.confirmation_number_outlined : Icons.event_outlined,
        color: accent,
        size: 17,
      ),
    );
  }
}
