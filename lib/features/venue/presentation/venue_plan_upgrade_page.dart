import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/venue/venue_plan.dart';

/// External beta sırasında venue erişim kademelerini salt okunur karşılaştırır.
/// Bu ekranda satın alma veya plan değiştirme işlemi sunulmaz.
class VenuePlanUpgradePage extends StatelessWidget {
  final VenuePlan currentPlan;
  final VenueFeature? highlightFeature; // hangi kilitli özellikten gelindi

  const VenuePlanUpgradePage({
    super.key,
    required this.currentPlan,
    this.highlightFeature,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kBg = isDark ? const Color(0xFF06091A) : Colors.white;
    final kText = isDark ? Colors.white : const Color(0xFF0B1020);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        title: Text('Plan access', style: TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w700)),
        iconTheme: IconThemeData(color: kText),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            if (highlightFeature != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: highlightFeature!.minPlan.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: highlightFeature!.minPlan.color.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline, color: highlightFeature!.minPlan.color, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This feature is not enabled for this beta account. '
                          'It is available with ${highlightFeature!.minPlan.label} access.',
                          style: TextStyle(color: kText, fontSize: 13, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            for (final plan in VenuePlan.values)
              _PlanCard(
                plan: plan,
                isCurrent: plan == currentPlan,
                isDark: isDark,
              ),
            const SizedBox(height: 8),
            Text(
              'Plan access is assigned by the KMSTRY test team during the external beta.',
              style: TextStyle(color: kText.withValues(alpha: 0.5), fontSize: 12, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final VenuePlan plan;
  final bool isCurrent;
  final bool isDark;

  const _PlanCard({required this.plan, required this.isCurrent, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final kText = isDark ? Colors.white : const Color(0xFF0B1020);
    final kDim = kText.withValues(alpha: 0.6);
    final card = isDark ? const Color(0xFF0E1430) : const Color(0xFFF5F7FB);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCurrent ? plan.color : (isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE2E8F0)),
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: plan.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  plan.label,
                  style: TextStyle(color: plan.color, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              const Spacer(),
              if (isCurrent)
                Text(
                  'Current',
                  style: TextStyle(color: plan.color, fontWeight: FontWeight.w700, fontSize: 13),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final line in _highlights(plan))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle, size: 16, color: plan.color),
                  const SizedBox(width: 8),
                  Expanded(child: Text(line, style: TextStyle(color: kDim, fontSize: 13, height: 1.3))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<String> _highlights(VenuePlan plan) {
    switch (plan) {
      case VenuePlan.free:
        return ['Verified profile & photos', 'Basic check-in count', 'Enhanced profile (bio, links)'];
      case VenuePlan.social:
        return ['Everything in Free', 'Stories & Offers', 'Weekly traffic reports', 'Priority listing + featured badge', 'Up to 3 staff accounts'];
      case VenuePlan.live:
        return ['Everything in Social', 'Events with RSVP', 'Go Live broadcasts', 'Advanced analytics & repeat visitors', 'Up to 10 staff accounts'];
      case VenuePlan.premium:
        return ['Everything in Live', 'Homepage / Trending feature', 'VIP list management', 'Customer demographics & area comparison', 'Unlimited staff accounts'];
    }
  }
}
