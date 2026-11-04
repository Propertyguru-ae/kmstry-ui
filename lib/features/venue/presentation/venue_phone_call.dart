import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/data/reservation_phone.dart';
import 'package:kmstry_frontend/features/venue/presentation/google_place_photo.dart';
import 'package:url_launcher/url_launcher.dart';

/// Numarayı arama uygulamasında açar. Arama uygulaması olmayan cihazda numara,
/// Google kaynağıyla birlikte popup'ta okunabilir.
Future<void> dialVenuePhone(
  BuildContext context,
  VenuePhone phone, {
  GooglePhotoLinkLauncher? launcher,
}) async {
  final number = phone.phone;
  if (number == null) return;
  final uri = Uri(scheme: 'tel', path: number);
  try {
    final opened = launcher != null
        ? await launcher(uri)
        : await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened) return;
  } catch (_) {
    /* Devices without a dialer can still read the number. */
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Reservations phone'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(number),
            if (phone.fromGoogle) ...[
              const SizedBox(height: 12),
              VenuePhoneAttribution(
                phone: phone,
                alignment: WrapAlignment.start,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Arama isteği numarasız kaldığında kullanıcıya nedenini söyler; ağ hatası
/// "numara yok" gibi gösterilmez.
void showVenuePhoneUnavailable(BuildContext context, {required bool failed}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        failed
            ? 'Could not get the phone number. Please try again.'
            : 'No phone number available for this venue.',
      ),
    ),
  );
}

class VenuePhoneAttribution extends StatelessWidget {
  final VenuePhone phone;
  final WrapAlignment alignment;

  const VenuePhoneAttribution({
    super.key,
    required this.phone,
    this.alignment = WrapAlignment.end,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      letterSpacing: 0,
      color: isDark ? Colors.white : const Color(0xFF5E5E5E),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      alignment: alignment,
      children: [
        Text('Phone · Google Maps', softWrap: false, style: style),
        for (final attribution in phone.attributions)
          InkWell(
            onTap: attribution.uri == null
                ? null
                : () => launchUrl(
                    attribution.uri!,
                    mode: LaunchMode.externalApplication,
                  ),
            child: Text(
              attribution.name,
              style: style.copyWith(
                decoration: attribution.uri == null
                    ? null
                    : TextDecoration.underline,
              ),
            ),
          ),
      ],
    );
  }
}
