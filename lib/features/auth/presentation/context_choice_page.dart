import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/features/auth/presentation/signup_page.dart';

/// Kayit akisinin ilk adimi: kisisel mi yoksa mekan hesabi mi aciyor?
/// Login sayfasindaki "Kayit Ol" dugmesine basilinca gosterilir.
class ContextChoicePage extends StatelessWidget {
  const ContextChoicePage({super.key});

  // Dark mode
  static const _darkBg = Color(0xFF06091A);
  static const _blueCard = Color(0xFF051525);
  static const _blueBorder = Color(0xFF0D2840);
  static const _blueIconBg = AppColors.blue;
  static const _blueAccent = AppColors.blueDark;
  static const _purpleCard = Color(0xFF130818);
  static const _purpleBorder = Color(0xFF2A0E40);
  static const _purpleIconBg = AppColors.brand;
  static const _purpleAccent = AppColors.magentaDark;
  // Light mode
  static const _lightBlueCard = Color(0xFFEEF4FF);
  static const _lightBlueBorder = Color(0xFFCFE0FF);
  static const _lightBlueIconBg = AppColors.blue;
  static const _lightBlueTagBg = Color(0x1F1A9FE8);
  static const _lightBlueTagColor = AppColors.blueLight;
  static const _lightPurpleCard = Color(0xFFF6F0FF);
  static const _lightPurpleBorder = Color(0xFFE3D4FF);
  static const _lightPurpleIconBg = AppColors.brand;
  static const _lightPurpleTagBg = Color(0x1F3D1F8C);
  static const _lightPurpleTagColor = AppColors.brandLight;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? _darkBg : Colors.white,
      body: Stack(
        children: [
          if (isDark) ...[
            Positioned(
              top: -80,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 320,
                  height: 280,
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -0.4),
                      radius: 1.0,
                      colors: [
                        Color(0x215078FF), // rgba(80,120,255,0.13)
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 100,
              right: -40,
              child: Container(
                width: 180,
                height: 180,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    colors: [Color(0x148C46FF), Colors.transparent],
                  ),
                ),
              ),
            ),
          ],
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _CircleBackButton(isDark: isDark),
                  ),
                ),

                const Spacer(flex: 3),

                // Hero
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Eyebrow(isDark: isDark),
                      const SizedBox(height: 14),
                      _Headline(isDark: isDark),
                      const SizedBox(height: 12),
                      Text(
                        'Choose the account type that fits you best. You can add the other one later.',
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.6,
                          color: isDark
                              ? Color(0xFFB1B4BB)
                              : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 3),

                // Cards
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _OptionCard(
                        isDark: isDark,
                        cardColor: isDark ? _blueCard : _lightBlueCard,
                        borderColor: isDark ? _blueBorder : _lightBlueBorder,
                        iconBgColor: isDark ? _blueIconBg : _lightBlueIconBg,
                        iconColor: Colors.white,
                        icon: Icons.person_outline_rounded,
                        title: 'Personal',
                        description: 'Discover venues, meet people and share moments.',
                        tags: const ['Discover', 'Connect', 'Share'],
                        tagBg: isDark ? const Color(0x2F4EC8FF) : _lightBlueTagBg,
                        tagColor: isDark ? _blueAccent : _lightBlueTagColor,
                        arrowBg: isDark ? const Color(0x334EC8FF) : _lightBlueIconBg,
                        arrowColor: Colors.white,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SignupPage(isVenueSignup: false),
                          ),
                        ),
                      ),
                      const SizedBox(height: 11),
                      _OptionCard(
                        isDark: isDark,
                        cardColor: isDark ? _purpleCard : _lightPurpleCard,
                        borderColor: isDark ? _purpleBorder : _lightPurpleBorder,
                        iconBgColor: isDark ? _purpleIconBg : _lightPurpleIconBg,
                        iconColor: Colors.white,
                        icon: Icons.store_mall_directory_outlined,
                        title: 'Venue',
                        description:
                            'Manage your venue, engage guests and grow your presence.',
                        tags: const ['Manage', 'Engage', 'Grow'],
                        tagBg: isDark ? const Color(0x2FBB86FC) : _lightPurpleTagBg,
                        tagColor: isDark ? _purpleAccent : _lightPurpleTagColor,
                        arrowBg: isDark ? const Color(0x33BB86FC) : _lightPurpleIconBg,
                        arrowColor: Colors.white,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SignupPage(isVenueSignup: true),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 4),

                // Bottom social proof
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: Column(
                    children: [
                      Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            Colors.transparent,
                            isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.08),
                            Colors.transparent,
                          ]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Not sure? ',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: isDark
                                    ? const Color(0xFF3A5070)
                                    : Colors.black38,
                              ),
                            ),
                            TextSpan(
                              text: 'Learn about account types ',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: isDark
                                    ? AppColors.blueDark
                                    : AppColors.blueLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: '→',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: isDark
                                    ? AppColors.blueDark
                                    : AppColors.blueLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleBackButton extends StatelessWidget {
  final bool isDark;
  const _CircleBackButton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : const Color(0xFFF3F5F8),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE2E6EC),
          ),
        ),
        child: Icon(
          Icons.chevron_left_rounded,
          size: 22,
          color: isDark ? const Color(0xFF607090) : const Color(0xFF5A6478),
        ),
      ),
    );
  }
}


class _Eyebrow extends StatelessWidget {
  final bool isDark;
  const _Eyebrow({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 2,
          decoration: BoxDecoration(
            color: isDark ? AppColors.blueDark : AppColors.blue,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          'GET STARTED',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
            color: isDark ? AppColors.blueDark : AppColors.blue,
          ),
        ),
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  final bool isDark;
  const _Headline({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Ekran genişliğine orantılı font: 375px referans ekranda 36px
    final fontSize = (screenWidth * 0.096).clamp(32.0, 44.0);
    final baseStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.2,
      height: 1.12,
      color: isDark ? Colors.white : const Color(0xFF111827),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How would', style: baseStyle),
        Text('you like to', style: baseStyle),
        ShaderMask(
          shaderCallback: _blueVioletShader,
          blendMode: BlendMode.srcIn,
          child: Text('join us?', style: baseStyle),
        ),
      ],
    );
  }

  Shader _blueVioletShader(Rect bounds) {
    return LinearGradient(
      colors: isDark
          ? AppColors.gradientDark
          : AppColors.gradientLight,
    ).createShader(bounds);
  }
}

class _OptionCard extends StatelessWidget {
  final bool isDark;
  final Color cardColor;
  final Color borderColor;
  final Color iconBgColor;
  final Color iconColor;
  final IconData icon;
  final String title;
  final String description;
  final List<String> tags;
  final Color tagBg;
  final Color tagColor;
  final Color arrowBg;
  final Color arrowColor;
  final VoidCallback onTap;

  const _OptionCard({
    required this.isDark,
    required this.cardColor,
    required this.borderColor,
    required this.iconBgColor,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.description,
    required this.tags,
    required this.tagBg,
    required this.tagColor,
    required this.arrowBg,
    required this.arrowColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          children: [
            // Card top
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: iconBgColor,
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Icon(icon, color: iconColor, size: 26),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 27,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: isDark ? 0.07 : 0.18),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(17),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? const Color(0xFFEEF2FF) : const Color(0xFF14171F),
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFF4A6080) : const Color(0xFF6B7588),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // CTA row
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFF14171F).withValues(alpha: 0.05),
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      children: tags
                          .map(
                            (t) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(
                                color: tagBg,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text(
                                t,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: tagColor,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: arrowBg,
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: arrowColor,
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
}

