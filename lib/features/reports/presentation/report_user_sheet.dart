import 'package:flutter/material.dart';
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
  required String targetUserId,
  String title = 'What do you want to report?',
}) async {
  final repo = CheckinRepository();

  int? selectedIndex;
  bool submitting = false;
  bool submitted = false;
  String? submitError;
  var reportSucceeded = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final colors = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
      final screenHeight = MediaQuery.of(ctx).size.height;
      final bottomInset = MediaQuery.of(ctx).padding.bottom;
      const destructive = Color(0xFFEF4444);

      return StatefulBuilder(
        builder: (ctx, setModalState) {
          final canSubmit = !submitting && selectedIndex != null;
          return SizedBox(
            width: double.infinity,
            height: screenHeight * 0.86,
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF161C28) : colors.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.onSurface.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  if (!submitted) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                color: colors.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.close_rounded,
                              color: colors.onSurface.withValues(alpha: 0.6),
                            ),
                            onPressed: submitting
                                ? null
                                : () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.onSurface.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'This report will be sent to the KMSTRY team. This person won\'t know you reported them. Once submitted, this user will be automatically blocked and your chat will be closed.',
                          style: TextStyle(
                            color: colors.onSurface.withValues(alpha: 0.72),
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                        itemCount: _kReportCategories.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          indent: 20,
                          endIndent: 20,
                          color: colors.onSurface.withValues(alpha: 0.08),
                        ),
                        itemBuilder: (ctx, i) {
                          final selected = selectedIndex == i;
                          return InkWell(
                            onTap: submitting
                                ? null
                                : () => setModalState(() => selectedIndex = i),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _kReportCategories[i].label,
                                      style: TextStyle(
                                        color: colors.onSurface,
                                        fontSize: 14.5,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    selected
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    size: 20,
                                    color: selected
                                        ? colors.primary
                                        : colors.onSurface.withValues(
                                            alpha: 0.3,
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (submitError != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                        child: Text(
                          submitError!,
                          style: TextStyle(color: colors.error, fontSize: 13),
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomInset + 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: destructive.withValues(
                              alpha: canSubmit ? 1 : 0.4,
                            ),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
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
                                    );
                                    reportSucceeded = true;
                                  } catch (_) {
                                    setModalState(() {
                                      submitting = false;
                                      submitError =
                                          'Could not submit report. Please try again.';
                                    });
                                    return;
                                  }

                                  // Best-effort block after a successful report.
                                  try {
                                    await repo.blockUser(targetUserId);
                                  } catch (_) {}

                                  setModalState(() {
                                    submitting = false;
                                    submitted = true;
                                  });
                                }
                              : null,
                          child: submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.flag_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Report',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ] else
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          24,
                          24,
                          bottomInset + 16,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF22C55E,
                                ).withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.verified_user_rounded,
                                color: Color(0xFF22C55E),
                                size: 28,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Thanks for your report',
                              style: TextStyle(
                                color: colors.onSurface,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'This user has been blocked automatically, and your chat has been closed for your safety.',
                              style: TextStyle(
                                color: colors.onSurface.withValues(alpha: 0.7),
                                fontSize: 13.5,
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text(
                                  'Done',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ],
                        ),
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

  return reportSucceeded;
}
