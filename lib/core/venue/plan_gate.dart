import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/venue/venue_plan.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_plan_upgrade_page.dart';

/// Kademe (plan) tabanlı erişim yardımcıları.
///
/// Rol izni [VenueSession.can] ile ayrı kontrol edilir; bu katman "venue bu
/// özelliği satın aldı mı" sorusunu yanıtlar.
class PlanGate {
  /// Aktif venue planı [feature]'ı açıyor mu?
  static bool allows(VenueFeature feature) => VenueSession.instance.hasFeature(feature);

  /// Özellik açıksa true döner. Kapalıysa salt okunur plan erişim ekranını açar —
  /// buton onTap'lerinde `if (!await PlanGate.ensure(context, X)) return;` şeklinde.
  static Future<bool> ensure(BuildContext context, VenueFeature feature) async {
    if (allows(feature)) return true;
    await openPaywall(context, feature: feature);
    return false;
  }

  static Future<void> openPaywall(BuildContext context, {VenueFeature? feature}) {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VenuePlanUpgradePage(
        currentPlan: VenueSession.instance.plan,
        highlightFeature: feature,
      ),
    ));
  }

  /// Özellik açıksa [onAllowed]'ı çalıştırır. Kapalıysa bilgilendirme
  /// bottom-sheet'i gösterir (kamera/akış hiç açılmadan) ve plan erişimini açıklar.
  static Future<void> ensureWithUpsell(
    BuildContext context,
    VenueFeature feature, {
    required IconData icon,
    required String title,
    required String message,
    required VoidCallback onAllowed,
  }) async {
    if (allows(feature)) {
      onAllowed();
      return;
    }
    await _showUpsellSheet(context, feature, icon: icon, title: title);
  }

  static Future<void> _showUpsellSheet(
    BuildContext context,
    VenueFeature feature, {
    required IconData icon,
    required String title,
  }) {
    final color = feature.minPlan.color;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final kBg = isDark ? const Color(0xFF0E1430) : Colors.white;
        final kText = isDark ? Colors.white : const Color(0xFF0B1020);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
              decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(24)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [color, color.withValues(alpha: 0.6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(icon, color: Colors.white, size: 30),
                  ),
                  const SizedBox(height: 18),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kText, fontSize: 19, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text(
                      'This feature is not enabled for this beta account. '
                      'Plan access is assigned by the KMSTRY test team.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kText.withValues(alpha: 0.6), fontSize: 14, height: 1.45)),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        openPaywall(context, feature: feature);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: color,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('View plan access',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('Not now', style: TextStyle(color: kText.withValues(alpha: 0.5))),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Kilitli özellikleri "lock" rozetiyle sarıp tıklanınca Paywall açan sarmalayıcı.
/// Açıksa [child]'ı olduğu gibi gösterir.
class PlanFeatureGate extends StatelessWidget {
  final VenueFeature feature;
  final Widget child;

  const PlanFeatureGate({super.key, required this.feature, required this.child});

  @override
  Widget build(BuildContext context) {
    if (PlanGate.allows(feature)) return child;
    return Opacity(
      opacity: 0.55,
      child: Stack(
        children: [
          IgnorePointer(child: child),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => PlanGate.openPaywall(context, feature: feature),
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(Icons.lock, size: 18, color: feature.minPlan.color),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
