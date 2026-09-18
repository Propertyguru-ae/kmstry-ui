import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_model.dart';
import 'package:kmstry_frontend/features/reports/presentation/report_user_sheet.dart';

/// Bir venue'nun tek bir deal/indirim ortaklığının detay sayfası. Chip'e
/// dokununca açılır; platform, teklif tipi, açıklama, geçerlilik ve varsa
/// dış bağlantı + kanıt görselini gösterir.
class VenueDealDetailPage extends StatelessWidget {
  final ExternalPartnershipModel deal;
  final String venueName;

  const VenueDealDetailPage({
    super.key,
    required this.deal,
    required this.venueName,
  });

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _validLabel(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : const Color(0xFFF6F7F9);
    final surface = isDark ? AppColors.darkSurface : Colors.white;
    final primary = isDark ? Colors.white : const Color(0xFF0F172A);
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final hasUrl =
        deal.externalUrl != null && deal.externalUrl!.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Deal details',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Report benefit',
            onPressed: () => showReportUserSheet(
              context,
              title: 'Why are you reporting this benefit?',
              venueBenefitId: deal.id,
            ),
            icon: const Icon(Icons.flag_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Platform başlığı
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.local_offer_rounded,
                  color: AppColors.orange,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deal.platformDisplayName,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      venueName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Teklif tipi rozeti
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.orange.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                deal.offerTypeDisplayName,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.orange,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Teklif açıklaması
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deal.offerLabel,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                    color: primary,
                  ),
                ),
                if (deal.validUntil != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.event_available_outlined,
                        size: 16,
                        color: muted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Valid until ${_validLabel(deal.validUntil!)}',
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Kanıt görseli (varsa)
          if (deal.proofImageUrl != null &&
              deal.proofImageUrl!.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CachedImage(deal.proofImageUrl!, fit: BoxFit.cover),
            ),
          ],

          if (hasUrl) ...[
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: Material(
                color: AppColors.orange,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _openUrl(deal.externalUrl!),
                  child: const Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Open offer',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
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
