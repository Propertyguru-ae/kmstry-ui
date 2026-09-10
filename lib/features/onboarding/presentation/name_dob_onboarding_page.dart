import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_routes.dart';

class NameDobOnboardingPage extends StatefulWidget {
  final String? initialName;
  final DateTime? initialBirthdate;

  /// true olduğunda isim alanı sadece okunur — venue claim'den gelen ad soyadı
  /// değiştirilemesin, kullanıcı sadece doğum tarihini seçsin.
  final bool nameReadOnly;

  /// Opsiyonel — "Maybe later" basıldığında çağrılır. Null ise authGate'e yönlendirilir.
  final VoidCallback? onCancel;

  /// Opsiyonel — çok adımlı onboarding akışında bir sonraki adıma ilerlemek için
  /// çağrılır. Null ise klasik authGate yönlendirmesi yapılır.
  final VoidCallback? onContinue;
  final void Function(String fullName, DateTime birthdate)? onSaved;

  const NameDobOnboardingPage({
    super.key,
    this.initialName,
    this.initialBirthdate,
    this.nameReadOnly = false,
    this.onCancel,
    this.onContinue,
    this.onSaved,
  });

  @override
  State<NameDobOnboardingPage> createState() => _NameDobOnboardingPageState();
}

class _NameDobOnboardingPageState extends State<NameDobOnboardingPage> {
  late final TextEditingController _nameController;
  late final FocusNode _nameFocusNode;
  DateTime? _birthdate;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _birthdate = widget.initialBirthdate;
    _nameFocusNode = FocusNode()..addListener(_handleNameFocusChange);
  }

  bool get _is18Plus {
    if (_birthdate == null) return false;
    final today = DateTime.now();
    // 18. yaş gününü hesapla; bugün o tarihte veya sonrasındaysa 18+.
    // (Yıl-bazlı çıkarma, doğum günü henüz gelmemiş 17 yaşındakileri kaçırıyordu.)
    final eighteenthBirthday = DateTime(
      _birthdate!.year + 18,
      _birthdate!.month,
      _birthdate!.day,
    );
    return !eighteenthBirthday.isAfter(today);
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
      // Kalem (manuel giriş) ikonunu gizle — yalnızca takvim.
      initialEntryMode: DatePickerEntryMode.calendarOnly,
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
      widget.onSaved?.call(_nameController.text.trim(), _birthdate!);

      if (widget.onContinue != null) {
        setState(() => _loading = false);
        widget.onContinue!();
      } else {
        Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
      }
    } catch (_) {
      setState(() => _loading = false);
      await showPremiumErrorDialog(context, message: 'Something went wrong');
    }
  }

  @override
  void dispose() {
    _nameFocusNode.removeListener(_handleNameFocusChange);
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  void _handleNameFocusChange() {
    if (!mounted) return;
    setState(() {});
  }

  String _formatDate(DateTime date) {
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return '$mm/$dd/${date.year}';
  }

  // ── Marka renkleri (logo paleti — her iki temada aynı) ───────────────────
  static const _blue = AppColors.blue; // #1A9FE8
  static const _blueBright = AppColors.blueDark; // #4EC8FF
  static const _magenta = AppColors.magenta; // #E020D8
  static const _orange = AppColors.orange; // #F08838
  static const _purple = AppColors.brandLight; // #5B21B6
  static const _muted = Color(0xFFA6B3D2);
  static const _mutedDim = Color(0xFF7F91B2);

  // ── Tema-duyarlı yüzey/metin renkleri ────────────────────────────────────
  bool _isDark = true;
  Color get _bg => _isDark ? AppColors.darkBg : const Color(0xFFF7FAFF);
  Color get _sheet => _isDark ? AppColors.darkSurface : Colors.white;
  Color get _sheetBorder =>
      _isDark ? const Color(0xFF172445) : const Color(0xFFD9E5F4);
  Color get _fieldFill =>
      _isDark ? const Color(0xFF0F1C35) : const Color(0xFFF2F7FF);
  Color get _fieldBorderIdle =>
      _isDark ? const Color(0xFF1A3060) : const Color(0xFFD9E5F4);
  Color get _textPrimary =>
      _isDark ? const Color(0xFFEEF2FF) : AppColors.lightTextPrimary;
  Color get _textSecondary => _isDark ? _muted : AppColors.lightTextSecondary;
  Color get _hint =>
      _isDark ? const Color(0xFF33486A) : const Color(0xFF95A8C2);
  Color get _handle => _isDark
      ? Colors.white.withValues(alpha: 0.10)
      : AppColors.lightTextPrimary.withValues(alpha: 0.12);
  Color get _iconBtnBg => _isDark
      ? Colors.white.withValues(alpha: 0.05)
      : AppColors.lightTextPrimary.withValues(alpha: 0.05);
  Color get _iconBtnBorder => _isDark
      ? Colors.white.withValues(alpha: 0.09)
      : AppColors.lightTextPrimary.withValues(alpha: 0.12);

  @override
  Widget build(BuildContext context) {
    _isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            // ── Marka ışıltıları (blue + magenta + purple) ───────────────────
            Positioned(
              top: -80,
              left: 0,
              right: 0,
              child: Center(
                child: _glow(320, 280, _blue.withValues(alpha: 0.14)),
              ),
            ),
            Positioned(
              bottom: 40,
              right: -60,
              child: _glow(220, 220, _magenta.withValues(alpha: 0.10)),
            ),
            Positioned(
              top: 200,
              left: -70,
              child: _glow(190, 190, _purple.withValues(alpha: 0.12)),
            ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Topbar ─────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        if (Navigator.canPop(context))
                          _circleIconButton(() => Navigator.of(context).pop())
                        else
                          const SizedBox(width: 38),
                        const Spacer(),
                        if (widget.onCancel != null)
                          TextButton(
                            onPressed: widget.onCancel,
                            style: TextButton.styleFrom(
                              foregroundColor: _blueBright,
                            ),
                            child: const Text(
                              'Maybe later',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // ── Hero ───────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 18,
                              height: 2,
                              decoration: BoxDecoration(
                                color: _orange,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'ABOUT YOU',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                                color: _orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'What’s your',
                          style: TextStyle(
                            fontSize: 30,
                            height: 1.12,
                            letterSpacing: -0.7,
                            fontWeight: FontWeight.w800,
                            color: _textPrimary,
                          ),
                        ),
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [AppColors.orange, _magenta],
                          ).createShader(bounds),
                          child: const Text(
                            'name?',
                            style: TextStyle(
                              fontSize: 30,
                              height: 1.12,
                              letterSpacing: -0.7,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          'This is how others will see you on KMSTRY.',
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                            color: _textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── Sheet ──────────────────────────────────────────────
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: _sheet,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(26),
                        ),
                        border: Border(top: BorderSide(color: _sheetBorder)),
                      ),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.only(
                          left: 20,
                          right: 20,
                          top: 8,
                          bottom: bottomInset + 24,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 34,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 22),
                                decoration: BoxDecoration(
                                  color: _handle,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            _fieldLabel(
                              Icons.person_outline_rounded,
                              'FULL NAME',
                            ),
                            const SizedBox(height: 8),
                            _buildNameField(),
                            const SizedBox(height: 20),
                            _fieldLabel(
                              Icons.calendar_today_rounded,
                              'DATE OF BIRTH',
                            ),
                            const SizedBox(height: 8),
                            _buildDateField(),
                            if (_birthdate != null && !_is18Plus)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  'You must be at least 18 years old to use KMSTRY.',
                                  style: TextStyle(
                                    color: _magenta.withValues(alpha: 0.9),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 16),
                            _buildAgeNote(),
                            const SizedBox(height: 20),
                            PrimaryButton(
                              label: 'Continue',
                              onPressed: _isValid ? _continue : null,
                              loading: _loading,
                              trailingArrow: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glow(double w, double h, Color color) {
    return IgnorePointer(
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0.0, 0.65],
          ),
        ),
      ),
    );
  }

  Widget _circleIconButton(VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _iconBtnBg,
          border: Border.all(color: _iconBtnBorder),
        ),
        child: Icon(
          Icons.chevron_left_rounded,
          size: 22,
          color: _isDark
              ? const Color(0xFF7D88A8)
              : AppColors.lightTextSecondary,
        ),
      ),
    );
  }

  Widget _fieldLabel(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: _blueBright),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: _blueBright,
          ),
        ),
      ],
    );
  }

  Widget _buildNameField() {
    final readOnly = widget.nameReadOnly;
    return TextField(
      focusNode: _nameFocusNode,
      controller: _nameController,
      readOnly: readOnly,
      onChanged: readOnly ? null : (_) => setState(() {}),
      contextMenuBuilder: (context, editableTextState) {
        return AdaptiveTextSelectionToolbar.editableText(
          editableTextState: editableTextState,
        );
      },
      cursorColor: _blue,
      style: TextStyle(
        color: readOnly ? _textSecondary : _textPrimary,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: _fieldFill,
        hintText: 'Your full name',
        hintStyle: TextStyle(color: _hint),
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: 15, right: 10),
          child: Icon(Icons.person_outline_rounded, size: 20, color: _blue),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: readOnly ? _fieldBorderIdle : _blue,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _blueBright, width: 1.6),
        ),
      ),
    );
  }

  Widget _buildDateField() {
    final hasDate = _birthdate != null;
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        decoration: BoxDecoration(
          color: _fieldFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _blue, width: 1.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded, size: 19, color: _blue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasDate ? _formatDate(_birthdate!) : 'Select date',
                style: TextStyle(
                  fontSize: 15,
                  color: hasDate ? _textPrimary : _hint,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: _mutedDim,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgeNote() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: _blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _blue.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined, size: 15, color: _blue),
          const SizedBox(width: 9),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: _textSecondary,
                ),
                children: const [
                  TextSpan(
                    text: 'We use your date of birth to confirm that you’re ',
                  ),
                  TextSpan(
                    text: '18 or older',
                    style: TextStyle(
                      color: _blueBright,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: '. It will never be shown publicly.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
