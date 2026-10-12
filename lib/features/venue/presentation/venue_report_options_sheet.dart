import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/app_sheet.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';

enum VenueReportTarget { venue, photo }

Future<VenueReportTarget?> showVenueReportOptions(
  BuildContext context, {
  required bool hasPhoto,
}) => showAppSheet<VenueReportTarget>(
  context,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSheetHeader(
            title: 'Report',
            subtitle: 'What would you like to report?',
          ),
          AppSheetCard(
            children: [
              AppSheetRow(
                leading: const AppSheetIconTile(
                  icon: Icons.storefront_outlined,
                  color: AppColors.orange,
                ),
                title: 'Report venue',
                onTap: () => Navigator.pop(context, VenueReportTarget.venue),
              ),
              if (hasPhoto)
                AppSheetRow(
                  leading: const AppSheetIconTile(
                    icon: Icons.image_outlined,
                    color: AppColors.magenta,
                  ),
                  title: 'Report photo',
                  subtitle: 'Reviewed by the KMSTRY team.',
                  onTap: () => Navigator.pop(context, VenueReportTarget.photo),
                ),
            ],
          ),
        ],
      ),
    ),
  ),
);

/// Used only when Google cannot open the exact report form directly, or the
/// venue destination was determined after the user chose the neutral action.
/// Opening a provider page is not the same as submitting a report.
Future<bool> confirmGoogleReportNavigation(
  BuildContext context, {
  required String instructions,
}) => showPremiumPromptDialog(
  context,
  icon: Icons.outlined_flag_rounded,
  title: 'Continue on Google Maps?',
  message:
      'Complete your report on Google Maps. It will be reviewed by Google, '
      'not KMSTRY.\n\n$instructions',
  confirmLabel: 'Continue to Google Maps',
  cancelLabel: 'Cancel',
);
