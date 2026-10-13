import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/ui/app_sheet.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'report_ui.dart';
import '../../checkin/data/checkin_repository.dart';

/// The backend `ReportReason` enum only has coarse buckets
/// (fake_profile/harassment/spam/scam/inappropriate_behavior/other);
/// each fine-grained UI category maps to one of these, and the exact
/// category label is always stored in `details` for admin visibility.
class _ReportCategory {
  final String label;
  final String backendReason;
  const _ReportCategory(this.label, this.backendReason);
}

const _kReportCategories = <_ReportCategory>[
  _ReportCategory('Nudity or sexual activity', 'INAPPROPRIATE_CONTENT'),
  _ReportCategory('Hate speech or symbols', 'HARASSMENT'),
  _ReportCategory('Scam or fraud', 'SPAM_SCAM'),
  _ReportCategory('Profile may have been hacked', 'OTHER'),
  _ReportCategory('Violence or dangerous organizations', 'HARASSMENT'),
  _ReportCategory('Sale of illegal or regulated goods', 'OTHER'),
  _ReportCategory('Bullying or harassment', 'HARASSMENT'),
  _ReportCategory('Intellectual property violation', 'OTHER'),
  _ReportCategory('Suicide, self-injury or eating disorder', 'OTHER'),
  _ReportCategory('Spam', 'SPAM_SCAM'),
];

/// Reusable WhatsApp/Instagram-style "Report" bottom sheet.
/// Used from stories and message screens as well, sharing the same
/// backend (`POST /reports/users`) and auto-block behavior as [profile_preview_page.dart].
///
/// Returns `true` if the report was submitted successfully.
Future<bool> showReportUserSheet(
  BuildContext context, {
  String? targetUserId,
  String title = 'What do you want to report?',
  String? messageId,
  String? storyId,
  String? venueStoryId,
  String? checkinMediaId,
  String? venueId,
  String? venuePhotoId,
  String? venuePhotoUrl,
  String? googlePhotoToken,
  String? venueGalleryItemId,
  String? eventId,
  String? venueOfferId,
  String? venueMenuItemId,
  String? venueBenefitId,
  CheckinRepository? repository,
}) async {
  final repo = repository ?? CheckinRepository();
  final reportsSelectedContent =
      messageId != null ||
      storyId != null ||
      venueStoryId != null ||
      checkinMediaId != null ||
      venueId != null ||
      venuePhotoId != null ||
      googlePhotoToken != null ||
      venueGalleryItemId != null ||
      eventId != null ||
      venueOfferId != null ||
      venueMenuItemId != null ||
      venueBenefitId != null;
  // Venue içeriği raporu venue tarafına gider; venue'nun kendi kullanıcısı
  // (ör. sahibi personal hesabından) raporlarsa backend CANNOT_REPORT_SELF döner.
  final reportsVenueContent =
      venueStoryId != null ||
      venueId != null ||
      venuePhotoId != null ||
      venueGalleryItemId != null ||
      eventId != null ||
      venueOfferId != null ||
      venueMenuItemId != null ||
      venueBenefitId != null;

  int? selectedIndex;
  bool submitting = false;
  String? submitError;
  var reportSucceeded = false;
  var alreadyReported = false;
  final reportTarget = venuePhotoId != null || googlePhotoToken != null
      ? 'this photo'
      : reportsSelectedContent
      ? 'this content'
      : 'this account';

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppSheetPalette.of(context).barrier,
    builder: (ctx) {
      final palette = AppSheetPalette.of(ctx);
      final screenHeight = MediaQuery.of(ctx).size.height;
      final bottomInset = MediaQuery.of(ctx).padding.bottom;

      return StatefulBuilder(
        builder: (ctx, setModalState) {
          final canSubmit = !submitting && selectedIndex != null;
          return SizedBox(
            width: double.infinity,
            height: screenHeight * 0.86,
            child: Container(
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(26),
                ),
                border: Border.all(color: palette.border),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  const AppSheetHeader(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const ReportHeaderIcon(),
                        const SizedBox(height: 14),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.title,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          reportsSelectedContent
                              ? 'The selected content will be shared with authorised KMSTRY moderators. This person won\'t know you reported it. Reporting content does not block the account.'
                              : 'This report will be sent to the KMSTRY team. This person won\'t know you reported them. Once submitted, this user will be automatically blocked and messaging will be paused.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
                      itemCount: _kReportCategories.length,
                      itemBuilder: (ctx, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ReportReasonTile(
                          label: _kReportCategories[i].label,
                          selected: selectedIndex == i,
                          onTap: submitting
                              ? null
                              : () => setModalState(() => selectedIndex = i),
                        ),
                      ),
                    ),
                  ),
                  if (submitError != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
                      child: Text(
                        submitError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFF04438),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(22, 12, 22, bottomInset + 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ReportSubmitButton(
                          label: reportsSelectedContent
                              ? 'Report'
                              : 'Report & block',
                          loading: submitting,
                          onPressed: canSubmit
                              ? () async {
                                  final category =
                                      _kReportCategories[selectedIndex!];
                                  setModalState(() {
                                    submitting = true;
                                    submitError = null;
                                  });
                                  try {
                                    await repo.reportUser(
                                      targetUserId: targetUserId,
                                      reason: category.backendReason,
                                      details: category.label,
                                      messageId: messageId,
                                      storyId: storyId,
                                      venueStoryId: venueStoryId,
                                      checkinMediaId: checkinMediaId,
                                      venueId: venueId,
                                      venuePhotoId: venuePhotoId,
                                      venuePhotoUrl: venuePhotoUrl,
                                      googlePhotoToken: googlePhotoToken,
                                      venueGalleryItemId: venueGalleryItemId,
                                      eventId: eventId,
                                      venueOfferId: venueOfferId,
                                      venueMenuItemId: venueMenuItemId,
                                      venueBenefitId: venueBenefitId,
                                    );
                                    reportSucceeded = true;
                                  } catch (error) {
                                    if (!ctx.mounted) return;
                                    if (error is ApiException &&
                                        error.data['errorCode'] ==
                                            'ALREADY_REPORTED_RECENTLY') {
                                      // Show an informational outcome, not a
                                      // submission failure or a new success.
                                      alreadyReported = true;
                                      Navigator.of(ctx).pop();
                                      return;
                                    }
                                    final errorCode = error is ApiException
                                        ? error.data['errorCode']
                                        : null;
                                    setModalState(() {
                                      submitting = false;
                                      submitError = switch (errorCode) {
                                        'REPORTED_PHOTO_CHANGED' =>
                                          'This photo has changed. Refresh the venue and try again.',
                                        'CANNOT_REPORT_SELF'
                                            when reportsVenueContent =>
                                          'You manage this venue, so you cannot report its content.',
                                        'CANNOT_REPORT_SELF' =>
                                          'You cannot report your own content.',
                                        _ =>
                                          'Could not submit report. Please try again.',
                                      };
                                    });
                                    return;
                                  }

                                  if (!reportsSelectedContent &&
                                      targetUserId != null &&
                                      targetUserId.trim().isNotEmpty) {
                                    // User-level reports retain the existing
                                    // report-and-block safety behavior.
                                    try {
                                      await repo.blockUser(targetUserId);
                                    } catch (_) {}
                                  }

                                  // Teşekkür mesajı uygulamanın standart
                                  // bilgilendirme penceresinde gösterilir.
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                }
                              : null,
                        ),
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: submitting
                              ? null
                              : () => Navigator.of(ctx).pop(),
                          style: TextButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            foregroundColor: palette.muted,
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
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
        },
      );
    },
  );

  if (reportSucceeded && !alreadyReported && context.mounted) {
    await showReportThanksDialog(
      context,
      contentReport: reportsSelectedContent,
    );
  } else if (alreadyReported && context.mounted) {
    await showPremiumPromptDialog(
      context,
      icon: Icons.info_outline_rounded,
      title: 'Already reported',
      message:
          "You've already sent a similar report for $reportTarget in the last 24 hours. No new report was sent.",
      confirmLabel: 'Done',
      showCancel: false,
    );
  }
  return reportSucceeded;
}
