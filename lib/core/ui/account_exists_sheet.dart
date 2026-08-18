import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/force_dark.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';

/// Bir hatanın "bu e-posta zaten kayıtlı" durumunu temsil edip etmediğini
/// merkezi olarak belirler (kod veya backend mesajından).
bool isEmailAlreadyInUseError(Object error) {
  if (error is! ApiException) return false;
  final code = error.data['errorCode']?.toString().toUpperCase();
  if (code == 'EMAIL_ALREADY_IN_USE' ||
      code == 'USER_ALREADY_EXISTS' ||
      code == 'AUTH_EMAIL_IN_USE' ||
      code == 'ACCOUNT_EXISTS_USE_PASSWORD') {
    return true;
  }
  final raw = error.data['message'];
  final msg = (raw is String
          ? raw
          : (raw is List && raw.isNotEmpty ? raw.first.toString() : ''))
      .toLowerCase();
  return msg.contains('already') &&
      (msg.contains('account') || msg.contains('email') || msg.contains('registered'));
}

/// "You already have an account" — e-posta zaten kayıtlıyken kullanıcıyı
/// sign-in'e yönlendiren, uygulama diline uygun tutarlı premium sheet.
///
/// Auth akışı (signup/login) görsel olarak daima dark olduğundan sheet
/// [ForceDark] ile sarılır; böylece ekranla eşleşir ve genel "Something went
/// wrong" diyaloğunun yerini alır.
///
/// [onSignIn] — "Sign In" butonuna basılınca (sheet kapandıktan sonra) çağrılır.
/// Örn. signup'tan login'e geri dönmek için `Navigator.pop`. Login'de zaten
/// giriş ekranında olunduğu için null bırakılabilir (sadece sheet kapanır).
Future<void> showAccountExistsSheet(
  BuildContext context, {
  String message =
      'This email is already registered with a password. Please sign in instead.',
  VoidCallback? onSignIn,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => ForceDark(
      child: Builder(
        builder: (ctx) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final sheetBg = isDark ? const Color(0xFF0B1322) : Colors.white;
          final sheetBorder =
              isDark ? const Color(0xFF172445) : const Color(0xFFD9E5F4);
          final textPrimary = isDark ? Colors.white : const Color(0xFF111827);
          final textSecondary =
              isDark ? const Color(0xFFA6B3D2) : const Color(0xFF5D6B7B);
          final handle = isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.10);

          return Container(
            decoration: BoxDecoration(
              color: sheetBg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(26)),
              border: Border(top: BorderSide(color: sheetBorder)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: handle,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          color: AppColors.blue.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.blue.withValues(alpha: 0.24),
                          ),
                        ),
                        child: const Icon(
                          Icons.account_circle_outlined,
                          size: 30,
                          color: AppColors.blue,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'You already have an account',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      label: 'Sign In',
                      trailingArrow: true,
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        onSignIn?.call();
                      },
                    ),
                    const SizedBox(height: 4),
                    PrimaryButton.secondary(
                      label: 'Cancel',
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
