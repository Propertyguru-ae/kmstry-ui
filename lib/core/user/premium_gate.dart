import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/user/premium_feature.dart';
import 'package:kmstry_frontend/core/user/user_session.dart';

/// KMSTRY+ access helper — the user-side mirror of [PlanGate]. It checks the
/// user's assigned entitlement independently of any venue role. Every premium
/// feature (T41–T48) routes through here.
class PremiumGate {
  static const Color _kmstryPlus = Color(0xFFE020D8); // brand magenta

  /// Does the current user's entitlement unlock [feature]?
  static bool allows(PremiumFeature feature) =>
      UserSession.instance.has(feature);

  /// Ensures [UserSession] is loaded, then returns whether [feature] is unlocked.
  /// Opens the beta access information sheet when locked. Use as:
  /// `if (!await PremiumGate.ensure(context, X)) return;`
  static Future<bool> ensure(
    BuildContext context,
    PremiumFeature feature, {
    String? title,
    String? message,
    IconData icon = Icons.workspace_premium_rounded,
  }) async {
    await UserSession.instance.ensureLoaded();
    if (allows(feature)) return true;
    if (!context.mounted) return false;
    await _showUpsellSheet(
      context,
      feature,
      icon: icon,
      title: title ?? '${feature.label} access',
      message: 'This feature is not enabled for this beta account. '
          'Access is assigned by the KMSTRY test team.',
    );
    return false;
  }

  /// Runs [onAllowed] when unlocked; otherwise shows access information.
  static Future<void> ensureWithUpsell(
    BuildContext context,
    PremiumFeature feature, {
    required VoidCallback onAllowed,
    String? title,
    String? message,
    IconData icon = Icons.workspace_premium_rounded,
  }) async {
    if (await ensure(context, feature,
        title: title, message: message, icon: icon)) {
      onAllowed();
    }
  }

  static Future<void> _showUpsellSheet(
    BuildContext context,
    PremiumFeature feature, {
    required IconData icon,
    required String title,
    required String message,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final kBg = isDark ? const Color(0xFF0E1430) : Colors.white;
        final kText = isDark ? Colors.white : const Color(0xFF0B1020);
        final kSub = isDark ? Colors.white70 : const Color(0xFF5B6178);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          _kmstryPlus,
                          _kmstryPlus.withValues(alpha: 0.6),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(icon, color: Colors.white, size: 30),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: kText,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kSub, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kmstryPlus,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      child: const Text('Close'),
                    ),
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
