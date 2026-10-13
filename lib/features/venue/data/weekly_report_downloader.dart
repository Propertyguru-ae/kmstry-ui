import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'venue_analytics_model.dart';

class WeeklyReportDownloadCancelled implements Exception {
  const WeeklyReportDownloadCancelled();
}

class WeeklyReportOpenFailed implements Exception {
  const WeeklyReportOpenFailed();
}

/// Download storage bytes without sending the user's API token to storage.
class WeeklyReportDownloader {
  WeeklyReportDownloader({
    Future<Directory> Function()? temporaryDirectory,
    Future<void> Function(String, String, CancelToken)? download,
    Future<OpenResult> Function(String)? openFile,
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _download = download ?? _downloadPdf,
       _openFile = openFile ?? OpenFilex.open;

  final Future<Directory> Function() _temporaryDirectory;
  final Future<void> Function(String, String, CancelToken) _download;
  final Future<OpenResult> Function(String) _openFile;

  static Future<void> _downloadPdf(
    String url,
    String path,
    CancelToken cancelToken,
  ) async {
    final dio = Dio();
    try {
      await dio.download(
        url,
        path,
        cancelToken: cancelToken,
        options: Options(
          followRedirects: false,
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
    } finally {
      dio.close();
    }
  }

  Future<void> downloadAndOpen({
    required String venueId,
    required WeeklyReport report,
    required Future<String> Function() freshUrl,
    required bool Function() isCurrent,
    required CancelToken cancelToken,
  }) async {
    void checkCurrent() {
      if (!isCurrent() || cancelToken.isCancelled) {
        throw const WeeklyReportDownloadCancelled();
      }
    }

    checkCurrent();
    final dir = await _temporaryDirectory();
    checkCurrent();
    String date(DateTime value) =>
        '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    final filename =
        'KMSTRY Weekly Report (${date(report.periodStart)} - ${date(report.periodEnd)}) '
        '${Uri.encodeComponent(venueId)}_${Uri.encodeComponent(report.id)}.pdf';
    final path = '${dir.path}/$filename';

    for (var attempt = 0; attempt < 2; attempt++) {
      checkCurrent();
      final url = await freshUrl();
      checkCurrent();
      try {
        await _download(url, path, cancelToken);
      } on DioException catch (error) {
        checkCurrent();
        // A stale storage signature is retried once, with NEW authorization.
        // API authorization errors are never caught/retried here.
        if (attempt == 0 && error.response?.statusCode == 403) continue;
        rethrow;
      }
      checkCurrent();
      final result = await _openFile(path);
      if (result.type != ResultType.done) {
        throw const WeeklyReportOpenFailed();
      }
      return;
    }
  }
}

String weeklyReportDownloadMessage(Object error) {
  if (error is ApiException) {
    if (error.statusCode == 401) {
      return 'Please sign in again to download this report.';
    }
    if (error.statusCode == 403) {
      return error.data['error'] == 'PLAN_UPGRADE_REQUIRED'
          ? 'Weekly reports are not available on your current venue plan.'
          : 'You no longer have permission to download reports for this venue.';
    }
    if (error.statusCode == 404) {
      return 'This report PDF is not available. Please refresh and try again.';
    }
  }
  if (error is WeeklyReportOpenFailed) {
    return "The report was downloaded, but couldn't be opened on this device.";
  }
  if (error is DioException) {
    if (error.response?.statusCode == 404) {
      return 'This report PDF is no longer available.';
    }
    if ([
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.connectionError,
    ].contains(error.type)) {
      return "Couldn't download the report. Check your connection and try again.";
    }
  }
  return "Couldn't download the report right now. Please try again.";
}
