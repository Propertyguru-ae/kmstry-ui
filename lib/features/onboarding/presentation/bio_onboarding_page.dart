import 'package:flutter/material.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_routes.dart';

/// Kişisel onboarding: isteğe bağlı bio (Skip veya Continue).
/// Metinler ürün dili: İngilizce.
class BioOnboardingPage extends StatefulWidget {
  final String? initialBio;

  const BioOnboardingPage({super.key, this.initialBio});

  static const int maxLength = 150;

  @override
  State<BioOnboardingPage> createState() => _BioOnboardingPageState();
}

class _BioOnboardingPageState extends State<BioOnboardingPage> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _loading = false;
  bool _buttonPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialBio ?? '');
    _focusNode = FocusNode()..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_loading) return;
    final text = _controller.text.trim();
    if (text.characters.length > BioOnboardingPage.maxLength) return;

    setState(() => _loading = true);
    try {
      await AuthRepository().upsertPersonalProfile({'bio': text});
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong')),
      );
    }
  }

  /// Backend `skipBio` / `bioOnboardingSkipped` ile adımı ilerletir; yoksa boş bio ile dene.
  Future<void> _skip() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await AuthRepository().upsertPersonalProfile({
        'skipBio': true,
        'bioOnboardingSkipped': true,
      });
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
    } catch (_) {
      try {
        await AuthRepository().upsertPersonalProfile({'bio': ''});
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
      } catch (_) {
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const surfaceBorder = Color(0xFF252D3D);
    const accent = Color.fromARGB(255, 11, 162, 237);
    const textPrimary = Color(0xFFF3F6FF);
    const textSecondary = Color(0xFF98A3BC);
    final isFocused = _focusNode.hasFocus;
    final len = _controller.text.characters.length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('About you'),
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _loading ? null : _skip,
            child: const Text(
              'Skip',
              style: TextStyle(
                color: textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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
                    const Text(
                      'A few words about you',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Optional — you can add or change this anytime in profile.',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF161C28), Color(0xFF1A2233)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isFocused ? accent : surfaceBorder,
                          width: isFocused ? 1.3 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isFocused
                                ? accent.withValues(alpha: 0.10)
                                : Colors.black.withValues(alpha: 0.10),
                            blurRadius: isFocused ? 24 : 12,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: TextField(
                        focusNode: _focusNode,
                        controller: _controller,
                        onChanged: (_) => setState(() {}),
                        maxLines: 5,
                        maxLength: BioOnboardingPage.maxLength,
                        buildCounter: (
                          context, {
                          required currentLength,
                          required isFocused,
                          required maxLength,
                        }) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 12, bottom: 8),
                            child: Text(
                              '$currentLength / $maxLength',
                              style: const TextStyle(
                                color: textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                        style: const TextStyle(
                          color: textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: const InputDecoration(
                          hintText:
                              'What should people know when you check in?',
                          hintStyle: TextStyle(color: textSecondary),
                          filled: true,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.fromLTRB(16, 18, 16, 8),
                        ),
                      ),
                    ),
                    if (len > BioOnboardingPage.maxLength)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Bio is too long.',
                          style: TextStyle(color: Color(0xFFFF8A8A)),
                        ),
                      ),
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
                  height: 56,
                  child: Listener(
                    onPointerDown: (_) => setState(() => _buttonPressed = true),
                    onPointerCancel: (_) =>
                        setState(() => _buttonPressed = false),
                    onPointerUp: (_) => setState(() => _buttonPressed = false),
                    child: ElevatedButton(
                      onPressed: _loading ||
                              len > BioOnboardingPage.maxLength
                          ? null
                          : _continue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.zero,
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            colors: [
                              accent,
                              accent.withValues(alpha: 0.85),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.35),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Center(
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Continue',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
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
