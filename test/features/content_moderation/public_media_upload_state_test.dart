import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/content_moderation/data/public_media_upload_state.dart';

void main() {
  test(
    'a gallery batch does not multiply status polls beyond the read budget',
    () {
      expect(
        publicMediaPollDelay(
          isVideo: true,
          elapsed: const Duration(seconds: 60),
          state: PendingPublicMediaState.checking,
          activeUploads: 6,
        ),
        const Duration(seconds: 6),
      );
      expect(
        publicMediaPollDelay(
          isVideo: true,
          elapsed: Duration.zero,
          state: PendingPublicMediaState.underReview,
          activeUploads: 30,
        ),
        const Duration(seconds: 30),
      );
    },
  );
  test('normal video analysis is not treated as a 30-second image timeout', () {
    for (final seconds in [30, 60, 89]) {
      expect(
        resolvePublicMediaState(
          moderation: const MediaModerationSnapshot(status: 'PROCESSING'),
          elapsed: Duration(seconds: seconds),
          isVideo: true,
        ),
        PendingPublicMediaState.checking,
      );
    }
    expect(
      resolvePublicMediaState(
        moderation: const MediaModerationSnapshot(status: 'PROCESSING'),
        elapsed: const Duration(seconds: 90),
        isVideo: true,
      ),
      PendingPublicMediaState.delayed,
    );
  });

  test(
    'video budget never suppresses decisions, connection errors or publication delays',
    () {
      for (final entry in {
        'REJECTED': PendingPublicMediaState.rejected,
        'ERROR': PendingPublicMediaState.failed,
        'NEEDS_REVIEW': PendingPublicMediaState.underReview,
        'APPROVED': PendingPublicMediaState.delayed,
      }.entries) {
        expect(
          resolvePublicMediaState(
            moderation: MediaModerationSnapshot(status: entry.key),
            elapsed: const Duration(seconds: 60),
            isVideo: true,
          ),
          entry.value,
        );
      }
      expect(
        resolvePublicMediaState(
          moderation: const MediaModerationSnapshot(status: 'PROCESSING'),
          elapsed: const Duration(seconds: 60),
          isVideo: true,
          connectionIssue: true,
        ),
        PendingPublicMediaState.connectionIssue,
      );
    },
  );

  test(
    'video polling stays responsive through normal analysis, then backs off',
    () {
      expect(
        publicMediaPollDelay(
          isVideo: true,
          elapsed: const Duration(seconds: 60),
          state: PendingPublicMediaState.checking,
        ),
        const Duration(seconds: 2),
      );
      expect(
        publicMediaPollDelay(
          isVideo: false,
          elapsed: const Duration(seconds: 60),
          state: PendingPublicMediaState.delayed,
        ),
        const Duration(seconds: 15),
      );
      for (final state in [
        PendingPublicMediaState.underReview,
        PendingPublicMediaState.connectionIssue,
      ]) {
        expect(
          publicMediaPollDelay(
            isVideo: true,
            elapsed: Duration.zero,
            state: state,
          ),
          const Duration(seconds: 15),
        );
      }
      expect(
        publicMediaPollDelay(
          isVideo: true,
          elapsed: const Duration(seconds: 90),
          state: PendingPublicMediaState.delayed,
        ),
        const Duration(seconds: 15),
      );
    },
  );
  test('time alone never changes a pending upload to manual review', () {
    for (final status in [null, 'PENDING', 'PROCESSING', 'FUTURE_STATUS']) {
      expect(
        resolvePublicMediaState(
          moderation: MediaModerationSnapshot(status: status),
          elapsed: const Duration(minutes: 10),
        ),
        PendingPublicMediaState.delayed,
      );
    }
  });

  test('separates content review from provider processing failure', () {
    expect(
      resolvePublicMediaState(
        moderation: const MediaModerationSnapshot(status: 'NEEDS_REVIEW'),
        elapsed: Duration.zero,
      ),
      PendingPublicMediaState.underReview,
    );
    expect(
      resolvePublicMediaState(
        moderation: const MediaModerationSnapshot(
          status: 'NEEDS_REVIEW',
          processingIssue: true,
        ),
        elapsed: Duration.zero,
      ),
      PendingPublicMediaState.underReview,
    );
  });

  test('approval awaits actual publication confirmation', () {
    expect(
      resolvePublicMediaState(
        moderation: const MediaModerationSnapshot(status: 'APPROVED'),
        elapsed: const Duration(seconds: 2),
      ),
      PendingPublicMediaState.publishing,
    );
    expect(
      resolvePublicMediaState(
        moderation: const MediaModerationSnapshot(status: 'APPROVED'),
        elapsed: const Duration(minutes: 1),
        isPublished: true,
      ),
      PendingPublicMediaState.published,
    );
  });

  test(
    'approved but unpublished upload exposes a delay instead of endless sharing',
    () {
      expect(
        resolvePublicMediaState(
          moderation: const MediaModerationSnapshot(status: 'APPROVED'),
          elapsed: const Duration(minutes: 1),
        ),
        PendingPublicMediaState.delayed,
      );
    },
  );

  test('connection failure is neither rejection nor manual review', () {
    expect(
      resolvePublicMediaState(
        moderation: const MediaModerationSnapshot(status: 'PROCESSING'),
        elapsed: const Duration(minutes: 1),
        connectionIssue: true,
      ),
      PendingPublicMediaState.connectionIssue,
    );
    expect(
      resolvePublicMediaState(
        moderation: const MediaModerationSnapshot(status: 'PROCESSING'),
        elapsed: const Duration(minutes: 1),
      ),
      PendingPublicMediaState.delayed,
    );
  });

  test('known decisions survive unrelated status connection failures', () {
    for (final entry in {
      'REJECTED': PendingPublicMediaState.rejected,
      'ERROR': PendingPublicMediaState.failed,
      'NEEDS_REVIEW': PendingPublicMediaState.underReview,
    }.entries) {
      expect(
        resolvePublicMediaState(
          moderation: MediaModerationSnapshot(status: entry.key),
          elapsed: const Duration(minutes: 2),
          connectionIssue: true,
        ),
        entry.value,
      );
    }
  });
}
