import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/ui/app_sheet.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'report_ui.dart';
import 'child_safety_report.dart';
import '../../checkin/data/checkin_repository.dart';
import '../../people/data/friendship_changes.dart';

/// The backend `ReportReason` enum only has coarse buckets
/// (including a dedicated child_safety reason);
/// each fine-grained UI category maps to one of these, and `details` stores the
/// exact category label for admin visibility, or the reporter's own words for
/// "Other", which the backend requires and limits to 150 characters.
class _ReportCategory {
  final String label;
  final String backendReason;
  final bool asksDetails;

  /// Bir hesabı anlatır; fotoğraf ya da mesaj gibi içerik şikayetinde gösterilmez.
  final bool accountOnly;
  const _ReportCategory(
    this.label,
    this.backendReason, {
    this.asksDetails = false,
    this.accountOnly = false,
  });
}

const _kReportCategories = <_ReportCategory>[
  _ReportCategory(childSafetyReportLabel, childSafetyReportReason),
  _ReportCategory('Fake profile', 'FAKE_PROFILE', accountOnly: true),
  _ReportCategory('Underage account', 'UNDERAGE_ACCOUNT', accountOnly: true),
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
  _ReportCategory('Other', 'OTHER', asksDetails: true),
];

/// Reusable WhatsApp/Instagram-style "Report" bottom sheet.
/// The one report flow for profiles, Friends, stories, messages and venue
/// content (`POST /reports/users`); reporting an account also blocks it.
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

  final categories = [
    for (final category in _kReportCategories)
      if (!category.accountOnly || !reportsSelectedContent) category,
  ];
  int? selectedIndex;
  String otherDetails = '';
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
      final topInset = MediaQueryData.fromView(View.of(ctx)).padding.top;

      return StatefulBuilder(
        builder: (ctx, setModalState) {
          final keyboard = MediaQuery.viewInsetsOf(ctx).bottom;
          final selected = selectedIndex == null
              ? null
              : categories[selectedIndex!];
          final canSubmit =
              !submitting &&
              selected != null &&
              (!selected.asksDetails || otherDetails.trim().isNotEmpty);
          return Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: SizedBox(
              width: double.infinity,
              // Klavye açıkken sayfa görünür alana sığar; butonlar üstünde kalır.
              height: math.min(
                screenHeight * 0.86,
                screenHeight - keyboard - topInset,
              ),
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
                    Expanded(
                      child: ListView.builder(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
                        itemCount: categories.length + 1,
                        itemBuilder: (ctx, index) {
                          // Let the introduction scroll too: on compact screens
                          // or large text it must not squeeze all reasons away.
                          if (index == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
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
                            );
                          }
                          final i = index - 1;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ReportReasonTile(
                                  label: categories[i].label,
                                  selected: selectedIndex == i,
                                  onTap: submitting
                                      ? null
                                      : () => setModalState(
                                          () => selectedIndex = i,
                                        ),
                                ),
                                if (selectedIndex == i &&
                                    categories[i].backendReason ==
                                        childSafetyReportReason)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      4,
                                      8,
                                      4,
                                      4,
                                    ),
                                    child: Text(
                                      childSafetyReportHelp,
                                      style: TextStyle(
                                        color: palette.muted,
                                        fontSize: 13,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                if (selectedIndex == i &&
                                    categories[i].asksDetails)
                                  _ReportDetailsField(
                                    initialText: otherDetails,
                                    enabled: !submitting,
                                    onChanged: (text) => setModalState(
                                      () => otherDetails = text,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
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
                      padding: EdgeInsets.fromLTRB(
                        22,
                        12,
                        22,
                        keyboard > 0 ? 8 : bottomInset + 8,
                      ),
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
                                    final category = categories[selectedIndex!];
                                    setModalState(() {
                                      submitting = true;
                                      submitError = null;
                                    });
                                    try {
                                      await repo.reportUser(
                                        targetUserId: targetUserId,
                                        reason: category.backendReason,
                                        details: category.asksDetails
                                            ? otherDetails.trim()
                                            : category.label,
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
                                        FriendshipChanges.changed(
                                          targetUserId,
                                          active: false,
                                        );
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

/// "Other" seçilince açılan açıklama alanı; denetleyicisini kendisi yönetir,
/// böylece sayfa kapanırken ya da liste kayarken yazılan metin güvende kalır.
class _ReportDetailsField extends StatefulWidget {
  const _ReportDetailsField({
    required this.initialText,
    required this.enabled,
    required this.onChanged,
  });

  final String initialText;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_ReportDetailsField> createState() => _ReportDetailsFieldState();
}

class _ReportDetailsFieldState extends State<_ReportDetailsField> {
  late final _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppSheetPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            enabled: widget.enabled,
            autofocus: true,
            maxLines: 3,
            inputFormatters: [LengthLimitingTextInputFormatter(150)],
            style: TextStyle(color: palette.title),
            decoration: InputDecoration(
              hintText: 'Help us understand what happened',
              hintStyle: TextStyle(color: palette.muted),
              filled: true,
              fillColor: palette.isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.03),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (text) {
              setState(() {});
              widget.onChanged(text);
            },
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${_controller.text.characters.length}/150',
              style: TextStyle(fontSize: 12, color: palette.muted),
            ),
          ),
        ],
      ),
    );
  }
}
