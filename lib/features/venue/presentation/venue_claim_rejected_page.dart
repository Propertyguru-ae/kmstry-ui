import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';

/// Venue claim admin tarafından reddedildiğinde gösterilen sayfa.
/// Bildirime tıklanarak açılır; kullanıcıya destek linki ve hesap geçiş
/// seçenekleri sunulur.
class VenueClaimRejectedPage extends StatefulWidget {
  final String venueId;
  final String venueName;

  const VenueClaimRejectedPage({
    super.key,
    required this.venueId,
    required this.venueName,
  });

  @override
  State<VenueClaimRejectedPage> createState() =>
      _VenueClaimRejectedPageState();
}

class _VenueClaimRejectedPageState extends State<VenueClaimRejectedPage> {
  List<_SwitchAccount> _accounts = [];
  bool _loading = true;
  bool _switching = false;
  bool _hasPersonalProfile = false;

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
          _hasPersonalProfile = ctx.hasPersonalProfile;
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
    } catch (e) {
      debugPrint('[VenueClaimRejectedPage] switchContext error: $e');
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AuthRoutes.authGate,
      (route) => false,
    );
  }

  Future<void> _createPersonalAccount() async {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AuthRoutes.authGate,
      (route) => false,
    );
  }

  Future<void> _openSupport() async {
    // Destek hattı URL'si hazır olduğunda buraya eklenecek.
    const url = 'mailto:adops@brightmindshub.net';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasAccounts = _accounts.isNotEmpty;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),

                // ── Kapat butonu ──
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: colors.onSurface.withValues(alpha: 0.50),
                    ),
                    onPressed: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      } else {
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          AuthRoutes.authGate,
                          (route) => false,
                        );
                      }
                    },
                  ),
                ),

                const SizedBox(height: 16),

                // ── İkon ──
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: colors.error.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.store_outlined,
                      size: 44,
                      color: colors.error,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ── Başlık ──
                Text(
                  'Claim Not Approved',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                Text(
                  'We were unable to verify your ownership of ${widget.venueName}. '
                  'This can happen if the submitted documents were incomplete or '
                  'could not be verified. Please contact our support team for more information.',
                  style: TextStyle(
                    fontSize: 15,
                    color: colors.onSurface.withValues(alpha: 0.65),
                    height: 1.55,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 36),

                // ── Venue bilgi kartı ──
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: colors.error.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: colors.error.withValues(alpha: 0.18)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.error.withValues(alpha: 0.12),
                        ),
                        child: Icon(Icons.store_outlined,
                            size: 18, color: colors.error),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Venue',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: colors.onSurface
                                      .withValues(alpha: 0.45)),
                            ),
                            Text(
                              widget.venueName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Rejected',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── Destek butonu ──
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _openSupport,
                    icon: const Icon(Icons.headset_mic_outlined, size: 20),
                    label: const Text('Contact Support'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.error,
                      foregroundColor: colors.onError,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 36),

                // ── Hesap seçimi ──
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
                else ...[
                  if (hasAccounts) ...[
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
                    _AccountAvatarRow(
                      accounts: _accounts,
                      switching: _switching,
                      onSwitch: _switchTo,
                      colors: colors,
                    ),
                    const SizedBox(height: 28),
                  ],
                  if (!_hasPersonalProfile) ...[
                    Divider(
                        color: colors.onSurface.withValues(alpha: 0.08)),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed:
                            _switching ? null : _createPersonalAccount,
                        icon: const Icon(Icons.person_add_outlined,
                            size: 20),
                        label: const Text('Create Personal Account'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: BorderSide(
                              color:
                                  colors.onSurface.withValues(alpha: 0.20)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ],

                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: _switching
                        ? null
                        : () async {
                            await AuthRepository().logout();
                            if (!mounted) return;
                            // ignore: use_build_context_synchronously
                            Navigator.of(context).pushNamedAndRemoveUntil(
                              AuthRoutes.authGate,
                              (route) => false,
                            );
                          },
                    child: Text(
                      'Sign out',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurface.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Avatar row ────────────────────────────────────────────────────
class _AccountAvatarRow extends StatelessWidget {
  static const int _maxVisible = 3;

  final List<_SwitchAccount> accounts;
  final bool switching;
  final void Function(_SwitchAccount) onSwitch;
  final ColorScheme colors;

  const _AccountAvatarRow({
    required this.accounts,
    required this.switching,
    required this.onSwitch,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final visible = accounts.take(_maxVisible).toList();
    final overflow = accounts.length - _maxVisible;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ...visible.map(
          (acc) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: GestureDetector(
              onTap: switching ? null : () => onSwitch(acc),
              child: Opacity(
                opacity: switching ? 0.5 : 1.0,
                child: Column(
                  children: [
                    _AvatarCircle(account: acc, size: 64, colors: colors),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 68,
                      child: Text(
                        acc.displayName,
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
            ),
          ),
        ),
        if (overflow > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: GestureDetector(
              onTap: switching ? null : () {},
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.onSurface.withValues(alpha: 0.08),
                    ),
                    child: Center(
                      child: Text(
                        '+$overflow',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 68,
                    child: Text(
                      'More',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface.withValues(alpha: 0.55),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Avatar dairesi ────────────────────────────────────────────────
class _AvatarCircle extends StatelessWidget {
  final _SwitchAccount account;
  final double size;
  final ColorScheme colors;

  const _AvatarCircle({
    required this.account,
    required this.size,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
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
                errorBuilder: (context, error, stack) => _Initial(
                  initial: account.initial,
                  isPersonal: account.isPersonal,
                  fontSize: size * 0.38,
                  colors: colors,
                ),
              )
            : _Initial(
                initial: account.initial,
                isPersonal: account.isPersonal,
                fontSize: size * 0.38,
                colors: colors,
              ),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  final String initial;
  final bool isPersonal;
  final double fontSize;
  final ColorScheme colors;

  const _Initial({
    required this.initial,
    required this.isPersonal,
    required this.colors,
    this.fontSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: isPersonal ? colors.primary : colors.secondary,
        ),
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────
class _SwitchAccount {
  final String type;
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
