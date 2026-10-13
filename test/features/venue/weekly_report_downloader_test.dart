import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_filex/open_filex.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/venue/data/venue_analytics_model.dart';
import 'package:kmstry_frontend/features/venue/data/weekly_report_downloader.dart';

void main() {
  final report = WeeklyReport(
    id: 'report-a',
    periodStart: DateTime(2026, 10, 5),
    periodEnd: DateTime(2026, 10, 12),
    pdfUrl: 'https://stale.example/report.pdf',
    totalCheckins: 3,
    uniqueVisitors: 2,
  );
  late int linkRequests;
  late List<String> downloaded;
  late List<String> opened;
  late bool current;
  late CancelToken token;
  late WeeklyReportDownloader downloader;
  late Future<String> Function() freshUrl;
  late Future<void> Function(String, String, CancelToken) transfer;
  DioException storageError(int status) => DioException(
    requestOptions: RequestOptions(
      path: 'https://storage.example/pdf?private-signature',
    ),
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: RequestOptions(), statusCode: status),
  );

  setUp(() {
    linkRequests = 0;
    downloaded = [];
    opened = [];
    current = true;
    token = CancelToken();
    freshUrl = () async =>
        'https://storage.example/pdf?fresh=${++linkRequests}';
    transfer = (url, path, cancelToken) async {
      downloaded.add(url);
    };
    downloader = WeeklyReportDownloader(
      temporaryDirectory: () async => Directory('/test-tmp'),
      download: (url, path, cancel) => transfer(url, path, cancel),
      openFile: (path) async {
        opened.add(path);
        return OpenResult(type: ResultType.done, message: 'done');
      },
    );
  });
  Future<void> run() => downloader.downloadAndOpen(
    venueId: 'venue-a',
    report: report,
    freshUrl: () => freshUrl(),
    isCurrent: () => current,
    cancelToken: token,
  );

  test(
    'gets a fresh authorized link for each click; never uses the cached report URL',
    () async {
      await run();
      await run();
      expect(linkRequests, 2);
      expect(downloaded, [
        'https://storage.example/pdf?fresh=1',
        'https://storage.example/pdf?fresh=2',
      ]);
      expect(opened, hasLength(2));
      expect(opened.first, contains('venue-a_report-a.pdf'));
    },
  );

  test(
    'renews one expired storage URL and then opens the downloaded PDF',
    () async {
      transfer = (url, path, cancel) async {
        downloaded.add(url);
        if (downloaded.length == 1) throw storageError(403);
      };
      await run();
      expect(linkRequests, 2);
      expect(opened, hasLength(1));
    },
  );

  test('does not loop when storage repeatedly denies the download', () async {
    transfer = (url, path, cancel) async {
      throw storageError(403);
    };
    await expectLater(run(), throwsA(isA<DioException>()));
    expect(linkRequests, 2);
    expect(opened, isEmpty);
  });

  test(
    'API authorization failure is not retried or bypassed with a cached URL',
    () async {
      freshUrl = () async {
        linkRequests++;
        throw ApiException(statusCode: 403, data: {});
      };
      await expectLater(run(), throwsA(isA<ApiException>()));
      expect(linkRequests, 1);
      expect(downloaded, isEmpty);
      expect(opened, isEmpty);
    },
  );

  test(
    'permission revocation during an expired-link retry prevents downloading',
    () async {
      transfer = (url, path, cancel) async {
        downloaded.add(url);
        throw storageError(403);
      };
      freshUrl = () async {
        if (++linkRequests > 1) throw ApiException(statusCode: 403, data: {});
        return 'https://storage.example/pdf?first';
      };
      await expectLater(run(), throwsA(isA<ApiException>()));
      expect(downloaded, hasLength(1));
      expect(opened, isEmpty);
    },
  );

  test(
    'account or venue change while resolving URL never downloads old data',
    () async {
      freshUrl = () async {
        current = false;
        return 'https://storage.example/old-account';
      };
      await expectLater(run(), throwsA(isA<WeeklyReportDownloadCancelled>()));
      expect(downloaded, isEmpty);
      expect(opened, isEmpty);
    },
  );

  test(
    'account change during download never opens the old account report',
    () async {
      transfer = (url, path, cancel) async {
        current = false;
      };
      await expectLater(run(), throwsA(isA<WeeklyReportDownloadCancelled>()));
      expect(opened, isEmpty);
    },
  );

  test('a cancelled screen cannot start a download', () async {
    token.cancel();
    await expectLater(run(), throwsA(isA<WeeklyReportDownloadCancelled>()));
    expect(linkRequests, 0);
    expect(downloaded, isEmpty);
  });

  test(
    'friendly error messages do not expose storage URLs, tokens or exceptions',
    () {
      expect(
        weeklyReportDownloadMessage(ApiException(statusCode: 403, data: {})),
        contains('permission'),
      );
      expect(
        weeklyReportDownloadMessage(
          ApiException(
            statusCode: 403,
            data: {'error': 'PLAN_UPGRADE_REQUIRED'},
          ),
        ),
        contains('plan'),
      );
      expect(
        weeklyReportDownloadMessage(ApiException(statusCode: 404, data: {})),
        contains('not available'),
      );
      expect(
        weeklyReportDownloadMessage(const WeeklyReportOpenFailed()),
        contains("couldn't be opened"),
      );
      expect(
        weeklyReportDownloadMessage(storageError(403)),
        "Couldn't download the report right now. Please try again.",
      );
      expect(
        weeklyReportDownloadMessage(Exception('secret signed URL')),
        isNot(contains('secret')),
      );
    },
  );
}
