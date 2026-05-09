import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_routes.dart';

class NameDobOnboardingPage extends StatefulWidget {
  final String? initialName;

  const NameDobOnboardingPage({super.key, this.initialName});

  @override
  State<NameDobOnboardingPage> createState() => _NameDobOnboardingPageState();
}

class _NameDobOnboardingPageState extends State<NameDobOnboardingPage> {
  late final TextEditingController _nameController;
  late final FocusNode _nameFocusNode;
  DateTime? _birthdate;
  bool _loading = false;
  bool _buttonPressed = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _nameFocusNode = FocusNode()..addListener(() => setState(() {}));
  }

  bool get _is18Plus {
    if (_birthdate == null) return false;
    final today = DateTime.now();
    final age = today.year - _birthdate!.year;
    return age >= 18;
  }

  bool get _isValid {
    return _nameController.text.trim().isNotEmpty && _is18Plus;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 20),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
    );

    if (picked != null) {
      setState(() => _birthdate = picked);
    }
  }

  Future<void> _continue() async {
    if (!_isValid) return;

    setState(() => _loading = true);

    try {
      await AuthRepository().upsertPersonalProfile({
        'fullName': _nameController.text.trim(),
        'birthdate': _birthdate!.toIso8601String(),
      });

      if (!mounted) return;

      Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
    } catch (_) {
      setState(() => _loading = false);
      await showPremiumErrorDialog(context, message: 'Something went wrong');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return '$mm/$dd/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark
        ? const Color(0xFF161C28)
        : theme.colorScheme.surface.withValues(alpha: 0.96);
    final surfaceBorder = isDark
        ? const Color(0xFF252D3D)
        : theme.colorScheme.outline.withValues(alpha: 0.28);
    const accent = Color.fromARGB(255, 11, 162, 237);
    final textPrimary = isDark
        ? const Color(0xFFF3F6FF)
        : theme.colorScheme.onSurface;
    final textSecondary = isDark
        ? const Color(0xFF98A3BC)
        : theme.colorScheme.onSurface.withValues(alpha: 0.68);
    final isFocused = _nameFocusNode.hasFocus;

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
                      'What’s your name?',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'This is how others will see you',
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
                        gradient: LinearGradient(
                          colors: isDark
                              ? const [Color(0xFF161C28), Color(0xFF1A2233)]
                              : [
                                  theme.colorScheme.surface,
                                  theme.colorScheme.surface.withValues(
                                    alpha: 0.94,
                                  ),
                                ],
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
                                : Colors.black.withValues(
                                    alpha: isDark ? 0.10 : 0.05,
                                  ),
                            blurRadius: isFocused ? 24 : 12,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: TextField(
                        focusNode: _nameFocusNode,
                        controller: _nameController,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Full name',
                          hintStyle: TextStyle(color: textSecondary),
                          filled: true,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Date of birth',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _pickDate,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: surfaceBorder),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.18 : 0.06,
                              ),
                              blurRadius: 16,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_month_rounded,
                              color: accent,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _birthdate == null
                                  ? 'Select date'
                                  : _formatDate(_birthdate!),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: _birthdate == null
                                    ? textSecondary
                                    : textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_birthdate != null && !_is18Plus)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          'You must be at least 18 years old',
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
                      onPressed: _isValid && !_loading ? _continue : null,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            )
                          : const Text(
                              'Continue',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                letterSpacing: 0.2,
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
