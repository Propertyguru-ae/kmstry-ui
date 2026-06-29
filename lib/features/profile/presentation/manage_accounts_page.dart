import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/profile/presentation/account_detail_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/name_dob_onboarding_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_context_onboarding_page.dart';

class ManageAccountsPage extends StatefulWidget {
  const ManageAccountsPage({super.key});

  @override
  State<ManageAccountsPage> createState() => _ManageAccountsPageState();
}

class _ManageAccountsPageState extends State<ManageAccountsPage> {
  bool _loading = true;
  MeContextModel? _context;
  String? _fullName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await AuthRepository().getMe();
      if (!mounted) return;
      setState(() {
        _context = MeContextModel.fromMe(me);
        final username = me['username']?.toString();
        final fullName = (me['fullName'] ?? me['full_name'])?.toString();
        _fullName = (username != null && username.isNotEmpty)
            ? '@$username'
            : fullName;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final ctx = _context;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        title: Text(
          'Manage Accounts',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.grey[200],
            height: 1,
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [

                // ── Add Venue Account ────────────────────────────
                _ActionCard(
                  icon: Icons.add_business_outlined,
                  title: 'Add Venue Account',
                  subtitle: 'Claim or join a venue to manage it',
                  colors: colors,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const VenueContextOnboardingPage(
                          fromAppShell: true,
                        ),
                      ),
                    );
                    if (mounted) _load();
                  },
                ),

                // ── Add Personal Account (yalnızca personal profil yoksa) ──
                if (ctx != null && !ctx.hasPersonalProfile) ...[
                  const SizedBox(height: 8),
                  _ActionCard(
                    icon: Icons.person_add_outlined,
                    title: 'Add Personal Account',
                    subtitle: 'Create a personal profile on KMSTRY',
                    colors: colors,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NameDobOnboardingPage(),
                        ),
                      );
                      if (mounted) _load();
                    },
                  ),
                ],

                const SizedBox(height: 24),

                if (ctx != null) ...[
                  Text(
                    'Your Accounts',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Personal account
                  if (ctx.hasPersonalProfile)
                    _AccountCard(
                      name: _fullName?.isNotEmpty == true
                          ? _fullName!
                          : 'Personal Account',
                      subtitle: 'Personal',
                      icon: Icons.person_outline,
                      colors: colors,
                      onManage: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AccountDetailPage(
                              accountName: _fullName?.isNotEmpty == true
                                  ? _fullName!
                                  : 'Personal Account',
                              isVenue: false,
                            ),
                          ),
                        );
                        if (mounted) _load();
                      },
                    ),

                  // Venue accounts
                  ...ctx.memberVenues
                      .where((v) => v.isActive)
                      .map(
                        (venue) => Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _AccountCard(
                            name: venue.name,
                            subtitle: venue.role ?? 'Venue',
                            icon: Icons.business_outlined,
                            colors: colors,
                            onManage: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AccountDetailPage(
                                    accountName: venue.name,
                                    isVenue: true,
                                    venueId: venue.id,
                                  ),
                                ),
                              );
                              if (mounted) _load();
                            },
                          ),
                        ),
                      ),
                ],

                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final ColorScheme colors;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.primary.withValues(alpha: 0.12)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: colors.primary),
        title: Text(title,
            style: TextStyle(
                color: colors.onSurface, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.6), fontSize: 13)),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final IconData icon;
  final ColorScheme colors;
  final VoidCallback onManage;

  const _AccountCard({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: colors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: colors.onSurface.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onManage,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: colors.primary,
            ),
            child: const Text(
              'Manage',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
