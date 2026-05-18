import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';

/// Venue claim gönderilmiş, admin onayı bekleniyor.
/// homeRoute == 'VENUE_PENDING' veya uygulama içi claim sonrası gösterilir.
/// getMe'yi kendi çeker; aktif hesaplar varsa daire avatarları gösterir.
class VenuePendingPage extends StatefulWidget {
  const VenuePendingPage({super.key});

  @override
  State<VenuePendingPage> createState() => _VenuePendingPageState();
}

class _VenuePendingPageState extends State<VenuePendingPage> {
  List<_SwitchAccount> _accounts = [];
  bool _loading = true;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    try {
      final me = await AuthRepository().getMe();
      final ctx = MeContextModel.fromMe(me);
      final fullName =
          (me['fullName'] ?? me['full_name'])?.toString().trim() ?? '';

      final accounts = <_SwitchAccount>[];

      if (ctx.hasPersonalProfile) {
        final initial =
            fullName.isNotEmpty ? fullName[0].toUpperCase() : 'P';
        accounts.add(_SwitchAccount(
          type: 'personal',
          displayName: fullName.isNotEmpty ? fullName : 'Personal',
          initial: initial,
        ));
      }

      for (final v in ctx.memberVenues.where((v) => v.isActive)) {
        final initial = v.name.isNotEmpty ? v.name[0].toUpperCase() : 'V';
        accounts.add(_SwitchAccount(
          type: 'venue',
          displayName: v.name,
          initial: initial,
          photoUrl: v.photoUrl,
          venueId: v.id,
        ));
      }

      if (mounted) {
        setState(() {
          _accounts = accounts;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switchTo(_SwitchAccount account) async {
    if (_switching) return;
    setState(() => _switching = true);
    try {
      await AuthRepository().switchContext(
        lastActiveContext: account.isPersonal ? 'PERSONAL' : 'VENUE',
        activeVenueId: account.venueId,
      );
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        AuthRoutes.authGate,
        (route) => false,
      );
    } catch (_) {
      if (mounted) setState(() => _switching = false);
    }
  }

  void _refresh() {
    AuthRepository.invalidateMeCache();
    Navigator.of(context).pushNamedAndRemoveUntil(
      AuthRoutes.authGate,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasAccounts = _accounts.isNotEmpty;

    return Scaffold(
      backgroundColor:
          isDark ? Theme.of(context).scaffoldBackgroundColor : Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),

              // ── Icon ──
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.hourglass_top_rounded,
                    size: 44,
                    color: colors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // ── Başlık ──
              Text(
                'Claim Under Review',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Text(
                'We received your venue ownership request and our team is '
                'reviewing it. You will be notified by email once it is approved.',
                style: TextStyle(
                  fontSize: 15,
                  color: colors.onSurface.withValues(alpha: 0.65),
                  height: 1.55,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 44),

              // ── Hesap avatarları ──
              if (_loading)
                Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  ),
                )
              else if (hasAccounts) ...[
                Text(
                  'Continue as',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface.withValues(alpha: 0.45),
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _accounts.map((acc) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: _AccountAvatar(
                        account: acc,
                        switching: _switching,
                        onTap: () => _switchTo(acc),
                        colors: colors,
                      ),
                    );
                  }).toList(),
                ),
              ],

              const Spacer(flex: 3),

              // ── Refresh status ──
              Center(
                child: TextButton(
                  onPressed: _switching ? null : _refresh,
                  child: Text(
                    'Refresh status',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurface.withValues(alpha: 0.40),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Avatar widget ──────────────────────────────────────────────
class _AccountAvatar extends StatelessWidget {
  final _SwitchAccount account;
  final bool switching;
  final VoidCallback onTap;
  final ColorScheme colors;

  const _AccountAvatar({
    required this.account,
    required this.switching,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: switching ? null : onTap,
      child: Opacity(
        opacity: switching ? 0.5 : 1.0,
        child: Column(
          children: [
            // Daire
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: account.isPersonal
                    ? colors.primary.withValues(alpha: 0.14)
                    : colors.secondary.withValues(alpha: 0.14),
              ),
              child: ClipOval(
                child: account.photoUrl != null
                    ? Image.network(
                        account.photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _InitialFallback(
                          initial: account.initial,
                          isPersonal: account.isPersonal,
                          colors: colors,
                        ),
                      )
                    : _InitialFallback(
                        initial: account.initial,
                        isPersonal: account.isPersonal,
                        colors: colors,
                      ),
              ),
            ),
            const SizedBox(height: 8),
            // İsim
            SizedBox(
              width: 72,
              child: Text(
                account.displayName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface.withValues(alpha: 0.80),
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InitialFallback extends StatelessWidget {
  final String initial;
  final bool isPersonal;
  final ColorScheme colors;

  const _InitialFallback({
    required this.initial,
    required this.isPersonal,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: isPersonal ? colors.primary : colors.secondary,
        ),
      ),
    );
  }
}

// ── Data model ─────────────────────────────────────────────────
class _SwitchAccount {
  final String type; // 'personal' | 'venue'
  final String displayName;
  final String initial;
  final String? photoUrl;
  final String? venueId;

  const _SwitchAccount({
    required this.type,
    required this.displayName,
    required this.initial,
    this.photoUrl,
    this.venueId,
  });

  bool get isPersonal => type == 'personal';
}
