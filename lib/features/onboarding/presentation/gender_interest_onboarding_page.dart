import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_routes.dart';

class GenderInterestOnboardingPage extends StatefulWidget {
  const GenderInterestOnboardingPage({super.key});

  @override
  State<GenderInterestOnboardingPage> createState() =>
      _GenderInterestOnboardingPageState();
}

class _GenderInterestOnboardingPageState
    extends State<GenderInterestOnboardingPage> {
  String? gender;
  String? interest;
  bool loading = false;
  bool _buttonPressed = false;

  bool get valid => gender != null && interest != null;

  Future<void> submit() async {
    if (!valid) return;

    setState(() => loading = true);
    try {
      await AuthRepository().upsertPersonalProfile({
        'gender': gender!,
        'interestedIn': interest!,
      });

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong')),
      );
    }
  }

  Widget tile(
    String value,
    String label,
    String? selected,
    ValueChanged<String> onTap,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final active = selected == value;
    const accent = AppTheme.brandPrimary;
    final textPrimary = isDark
        ? const Color(0xFFF3F6FF)
        : theme.colorScheme.onSurface;
    final textSecondary = isDark
        ? const Color(0xFF98A3BC)
        : theme.colorScheme.onSurface.withValues(alpha: 0.66);
    final border = isDark
        ? const Color(0xFF252D3D)
        : theme.colorScheme.outline.withValues(alpha: 0.28);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => onTap(value)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: active
                ? [
                    accent.withValues(alpha: 0.24),
                    accent.withValues(alpha: 0.14),
                  ]
                : (isDark
                    ? const [
                        Color(0xFF161C28),
                        Color(0xFF1A2233),
                      ]
                    : [
                        theme.colorScheme.surface,
                        theme.colorScheme.surface.withValues(alpha: 0.96),
                      ]),
          ),
          border: Border.all(
            color: active ? accent : border,
            width: active ? 1.25 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: active
                  ? accent.withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: isDark ? 0.10 : 0.05),
              blurRadius: active ? 20 : 10,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: active ? textPrimary : textSecondary,
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: active
                  ? Container(
                      key: const ValueKey('selected'),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: accent.withValues(alpha: 0.9),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.check,
                        size: 15,
                        color: textPrimary,
                      ),
                    )
                  : Container(
                      key: const ValueKey('empty'),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: textSecondary.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textPrimary = isDark
        ? const Color(0xFFF3F6FF)
        : theme.colorScheme.onSurface;
    final textSecondary = isDark
        ? const Color(0xFF98A3BC)
        : theme.colorScheme.onSurface.withValues(alpha: 0.68);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('About you'),
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 112, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What is your gender?',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This helps us personalize your experience.',
                    style: TextStyle(
                      fontSize: 15,
                      color: textSecondary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  tile('male', 'Male', gender, (v) => gender = v),
                  const SizedBox(height: 10),
                  tile('female', 'Female', gender, (v) => gender = v),
                  const SizedBox(height: 32),
                  Text(
                    'Who do you want to connect with?',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose who you would like to see.',
                    style: TextStyle(
                      fontSize: 15,
                      color: textSecondary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  tile('men', 'Men', interest, (v) => interest = v),
                  const SizedBox(height: 10),
                  tile('women', 'Women', interest, (v) => interest = v),
                  const SizedBox(height: 10),
                  tile('everyone', 'Everyone', interest, (v) => interest = v),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            minimum: EdgeInsets.fromLTRB(
              24,
              12,
              24,
              MediaQuery.of(context).padding.bottom + 12,
            ),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 120),
              scale: _buttonPressed ? 0.985 : 1,
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: Listener(
                  onPointerDown: (_) => setState(() => _buttonPressed = true),
                  onPointerCancel: (_) => setState(() => _buttonPressed = false),
                  onPointerUp: (_) => setState(() => _buttonPressed = false),
                  child: ElevatedButton(
                    onPressed: valid && !loading ? submit : null,
                    child: loading
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: isDark ? Colors.black : Colors.white,
                            ),
                          )
                        : const Text('Continue'),
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
