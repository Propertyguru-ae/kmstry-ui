import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/user/premium_feature.dart';
import 'package:kmstry_frontend/core/user/premium_gate.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';

/// Message-scoped preferences hub. Reached from the settings icon on the
/// Messages tab. Starts with Read Receipts (T48, KMSTRY+); designed so each new
/// message setting is a single [_SettingRow] added below.
class MessageSettingsPage extends StatefulWidget {
  const MessageSettingsPage({super.key});

  @override
  State<MessageSettingsPage> createState() => _MessageSettingsPageState();
}

class _MessageSettingsPageState extends State<MessageSettingsPage> {
  static const Color _kmstryPlus = Color(0xFFE020D8);

  bool _loading = true;
  bool _readReceipts = true;
  bool _saving = false;

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
        _readReceipts = me['readReceiptsEnabled'] != false; // default on
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleReadReceipts(bool enabled) async {
    // Turning receipts OFF (hiding your "seen") is the KMSTRY+ perk. Free users
    // get the upsell instead. Turning them back on is free for everyone.
    if (!enabled) {
      final ok = await PremiumGate.ensure(
        context,
        PremiumFeature.readReceiptsControl,
        icon: Icons.done_all_rounded,
        title: 'Control your read receipts with KMSTRY+',
        message:
            'Read receipt controls are not enabled for this beta account. '
            'Access is assigned by the KMSTRY test team.',
      );
      if (!ok) return; // not premium — leave the switch on
    }

    setState(() {
      _readReceipts = enabled;
      _saving = true;
    });
    try {
      await AuthRepository().setReadReceipts(enabled);
    } catch (_) {
      if (mounted) setState(() => _readReceipts = !enabled); // revert
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;
    final bg = isDark
        ? const Color(0xFF0B0F17)
        : theme.scaffoldBackgroundColor;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.grey[200];

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.onSurface),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Message settings',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: borderColor, height: 1),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _SectionLabel(label: 'Privacy', colors: colors),
                _SettingRow(
                  icon: Icons.done_all_rounded,
                  title: 'Read receipts',
                  subtitle:
                      "When off, others won't see when you've read their "
                      "messages. You'll still see theirs.",
                  value: _readReceipts,
                  onChanged: _saving ? null : _toggleReadReceipts,
                  premiumBadge: true,
                  accent: _kmstryPlus,
                  colors: colors,
                ),
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final ColorScheme colors;
  const _SectionLabel({required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: colors.onSurface.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool premiumBadge;
  final Color accent;
  final ColorScheme colors;

  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.accent,
    required this.colors,
    this.premiumBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 22, color: colors.onSurface.withValues(alpha: 0.7)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    if (premiumBadge) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'KMSTRY+',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: colors.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: accent,
          ),
        ],
      ),
    );
  }
}
