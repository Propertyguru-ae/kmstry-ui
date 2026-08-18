import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/checkin/services/avatar_crop_helper.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';

class PhotoOnboardingPage extends StatefulWidget {
  final VoidCallback? onContinue;

  const PhotoOnboardingPage({super.key, this.onContinue});

  @override
  State<PhotoOnboardingPage> createState() => _PhotoOnboardingPageState();
}

class _PhotoOnboardingPageState extends State<PhotoOnboardingPage> {
  File? _image;
  bool _loading = false;
  final _picker = ImagePicker();

  static const _blue = AppColors.blue;
  static const _blueBright = AppColors.blueDark;
  static const _teal = AppColors.teal;
  static const _orange = AppColors.orange;
  static const _magenta = AppColors.magenta;
  static const _muted = Color(0xFFA6B3D2);

  // ── Tema-duyarlı yüzey/metin renkleri ────────────────────────────────────
  bool _isDark = true;
  Color get _bg => _isDark ? AppColors.darkBg : const Color(0xFFF7FAFF);
  Color get _sheet => _isDark ? AppColors.darkSurface : Colors.white;
  Color get _textPrimary =>
      _isDark ? Colors.white : AppColors.lightTextPrimary;
  Color get _textSecondary => _isDark ? _muted : AppColors.lightTextSecondary;
  Color get _iconBtnBg => _isDark
      ? Colors.white.withValues(alpha: 0.05)
      : AppColors.lightTextPrimary.withValues(alpha: 0.05);
  Color get _iconBtnBorder => _isDark
      ? Colors.white.withValues(alpha: 0.10)
      : AppColors.lightTextPrimary.withValues(alpha: 0.12);

  Future<void> _pickImage(ImageSource source) async {
    if (_loading) return;
    final picked = await _picker.pickImage(source: source, imageQuality: 85);

    if (picked != null) {
      if (!mounted) return;
      final cropped = await cropSquareAvatar(context, File(picked.path));
      if (cropped != null && mounted) {
        setState(() => _image = cropped);
      }
    }
  }

  Future<void> _chooseFromGallery() => _pickImage(ImageSource.gallery);

  Future<void> _goToPermissions() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      if (_image != null) {
        await AuthRepository().uploadProfilePhoto(_image!);
      } else {
        await AuthRepository().updateMe({
          'skipPhoto': true,
          'skip_photo': true,
        });
      }
    } catch (e) {
      debugPrint('Photo onboarding error: $e');
    }

    if (!mounted) return;
    setState(() => _loading = false);

    if (widget.onContinue != null) {
      widget.onContinue!();
    } else {
      Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
    }
  }

  @override
  Widget build(BuildContext context) {
    _isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Positioned(
            top: -90,
            left: 0,
            right: 0,
            child: Center(child: _glow(320, 280, _blue.withValues(alpha: .14))),
          ),
          Positioned(
            bottom: 70,
            right: -70,
            child: _glow(220, 220, _magenta.withValues(alpha: .10)),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (Navigator.canPop(context))
                        _circleIconButton(() => Navigator.of(context).pop())
                      else
                        const SizedBox(width: 38),
                      const Spacer(),
                      TextButton(
                        onPressed: _loading ? null : _goToPermissions,
                        style: TextButton.styleFrom(foregroundColor: _orange),
                        child: const Text(
                          'Skip',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
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
                        'ALMOST THERE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: _orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Add your',
                    style: TextStyle(
                      fontSize: 34,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                      color: _textPrimary,
                    ),
                  ),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [_blueBright, _teal],
                    ).createShader(bounds),
                    child: const Text(
                      'profile photo.',
                      style: TextStyle(
                        fontSize: 34,
                        height: 1.08,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Choose a photo people can recognize. You can skip this and add it later.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                      color: _textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Center(
                    child: GestureDetector(
                      onTap: _chooseFromGallery,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 156,
                        height: 156,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(42),
                          gradient: const LinearGradient(
                            colors: [_blue, _teal],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _blue.withValues(alpha: .22),
                              blurRadius: 34,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(38),
                          child: Container(
                            color: _isDark ? _sheet : const Color(0xFFF2F7FF),
                            child: _image == null
                                ? const Icon(
                                    Icons.add_a_photo_rounded,
                                    color: _blue,
                                    size: 42,
                                  )
                                : Image.file(_image!, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: PrimaryButton.secondary(
                      label: _image == null
                          ? 'Choose from Gallery'
                          : 'Choose Another Photo',
                      onPressed: _loading ? null : _chooseFromGallery,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: PrimaryButton(
                      label: 'Continue',
                      onPressed: _image == null || _loading
                          ? null
                          : _goToPermissions,
                      loading: _loading,
                      trailingArrow: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleIconButton(VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: _loading ? null : onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: _iconBtnBg,
          shape: BoxShape.circle,
          border: Border.all(color: _iconBtnBorder),
        ),
        child: Icon(
          Icons.arrow_back_rounded,
          color: _isDark ? Colors.white : AppColors.lightTextPrimary,
          size: 22,
        ),
      ),
    );
  }

  Widget _glow(double width, double height, Color color) {
    return IgnorePointer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
