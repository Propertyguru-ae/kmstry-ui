import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/force_dark.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/auth/presentation/signup_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/username_onboarding_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_context_onboarding_page.dart';

/// Signup akışında: kişisel mi yoksa mekan hesabı mı açıyor?
/// Login sayfasındaki "Kayıt Ol" butonuna basılınca gösterilir.
///
/// [isAuthenticated]=true olunca zaten giriş yapmış ama profil kurmamış
/// kullanıcılar için kullanılır (örn. invite'ı reddedip geri dönenler).
/// Bu modda Signup'a değil doğrudan onboarding sayfalarına yönlendirilir.
class ContextChoicePage extends StatelessWidget {
  final bool isAuthenticated;

  const ContextChoicePage({super.key, this.isAuthenticated = false});

  // Dark mode
  static const _darkBg = Color(0xFF06091A);
  static const _blueCard = Color(0xFF061A2A);
  static const _blueBorder = Color(0xFF164268);
  static const _blueIconBg = AppColors.blue;
  static const _blueAccent = AppColors.blueDark;
  static const _purpleCard = Color(0xFF100A1E);
  static const _purpleBorder = Color(0xFF2D1B52);
  static const _purpleIconBg = AppColors.brand;
  static const _purpleAccent = AppColors.brandLight;
  static const _venueGlow = AppColors.magentaDark;
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
    // Signup öncesi hesap-türü seçimi (isAuthenticated == false) → marka akışı,
    // DAİMA dark. Login sonrası bağlam ekleme/seçme → seçilen temayı izler.
    if (!isAuthenticated) {
      return ForceDark(child: Builder(builder: _buildBody));
    }
    return _buildBody(context);
  }

  Widget _buildBody(BuildContext context) {
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
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top bar — back button only for unauthenticated (signup) flow
                      if (!isAuthenticated)
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
                                fontSize: 14,
                                height: 1.55,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? const Color(0xFFC0C7DA)
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
                              borderColor: isDark
                                  ? _blueBorder
                                  : _lightBlueBorder,
                              iconBgColor: isDark
                                  ? _blueIconBg
                                  : _lightBlueIconBg,
                              iconColor: Colors.white,
                              icon: Icons.person_outline_rounded,
                              title: 'Personal',
                              description:
                                  'Discover venues, meet people and share moments.',
                              tags: const ['Discover', 'Connect', 'Share'],
                              tagBg: isDark
                                  ? const Color(0x2B4EC8FF)
                                  : _lightBlueTagBg,
                              tagColor: isDark
                                  ? _blueAccent
                                  : _lightBlueTagColor,
                              arrowBg: isDark
                                  ? const Color(0x2E4EC8FF)
                                  : _lightBlueIconBg,
                              arrowColor: Colors.white,
                              glowAccent: isDark
                                  ? AppColors.blue
                                  : _lightBlueIconBg,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (ctx) => isAuthenticated
                                      ? UsernameOnboardingPage(
                                          onCancel: () =>
                                              Navigator.of(ctx).pop(),
                                        )
                                      : const SignupPage(isVenueSignup: false),
                                ),
                              ),
                            ),
                            const SizedBox(height: 11),
                            _OptionCard(
                              isDark: isDark,
                              cardColor: isDark
                                  ? _purpleCard
                                  : _lightPurpleCard,
                              borderColor: isDark
                                  ? _purpleBorder
                                  : _lightPurpleBorder,
                              iconBgColor: isDark
                                  ? _purpleIconBg
                                  : _lightPurpleIconBg,
                              iconColor: Colors.white,
                              icon: Icons.store_mall_directory_outlined,
                              title: 'Venue',
                              description:
                                  'Manage your venue, engage guests and grow your presence.',
                              tags: const ['Manage', 'Engage', 'Grow'],
                              tagBg: isDark
                                  ? const Color(0x263D1F8C)
                                  : _lightPurpleTagBg,
                              tagColor: isDark
                                  ? _purpleAccent
                                  : _lightPurpleTagColor,
                              arrowBg: isDark
                                  ? const Color(0x2A3D1F8C)
                                  : _lightPurpleIconBg,
                              arrowColor: Colors.white,
                              glowAccent: isDark
                                  ? _venueGlow
                                  : _lightPurpleIconBg,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (ctx) => isAuthenticated
                                      ? VenueContextOnboardingPage(
                                          onCancel: () =>
                                              Navigator.of(ctx).pop(),
                                        )
                                      : const SignupPage(isVenueSignup: true),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(flex: 4),

                      // Bottom area
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                        child: Column(
                          children: [
                            Container(
                              height: 1,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Colors.black.withValues(alpha: 0.08),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (isAuthenticated)
                              GestureDetector(
                                onTap: () async {
                                  await AuthRepository().logout();
                                  if (context.mounted) {
                                    Navigator.of(
                                      context,
                                    ).pushNamedAndRemoveUntil(
                                      AuthRoutes.login,
                                      (_) => false,
                                    );
                                  }
                                },
                                child: Text(
                                  'Log out',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.35)
                                        : Colors.black38,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              )
                            else
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
              ),
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
      colors: isDark ? AppColors.gradientDark : AppColors.gradientLight,
    ).createShader(bounds);
  }
}

class _OptionCard extends StatefulWidget {
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
  final Color glowAccent;
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
    required this.glowAccent,
    required this.onTap,
  });

  @override
  State<_OptionCard> createState() => _OptionCardState();
}

class _OptionCardState extends State<_OptionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Container(
          decoration: BoxDecoration(
            color: widget.cardColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: widget.borderColor),
            boxShadow: [
              BoxShadow(
                color: widget.glowAccent.withValues(
                  alpha: widget.isDark ? 0.12 : 0.07,
                ),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: widget.isDark ? 0.20 : 0.04,
                ),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: widget.iconBgColor,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: widget.iconBgColor.withValues(
                                  alpha: 0.22,
                                ),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Icon(
                            widget.icon,
                            color: widget.iconColor,
                            size: 25,
                          ),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 26,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(
                                alpha: widget.isDark ? 0.07 : 0.18,
                              ),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(16),
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
                            widget.title,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: widget.isDark
                                  ? const Color(0xFFF4F6FF)
                                  : const Color(0xFF14171F),
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            widget.description,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: widget.isDark
                                  ? const Color(0xFF8EA2C5)
                                  : const Color(0xFF5F6B7D),
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: widget.isDark
                          ? Colors.white.withValues(alpha: 0.045)
                          : const Color(0xFF14171F).withValues(alpha: 0.05),
                    ),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 15),
                child: Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 7,
                        runSpacing: 6,
                        children: widget.tags
                            .map(
                              (t) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: widget.tagBg,
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(
                                    color: widget.tagColor.withValues(
                                      alpha: widget.isDark ? 0.18 : 0.10,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  t,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: widget.tagColor,
                                    letterSpacing: 0.15,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.arrowBg,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: widget.arrowColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
