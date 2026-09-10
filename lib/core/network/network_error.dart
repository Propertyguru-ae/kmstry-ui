import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:kmstry_frontend/core/network/api_exception.dart';

/// True when [error] is a connectivity failure (airplane mode, no signal, DNS
/// failure, timeout) rather than a real server/application error. Lets screens
/// show a calm "you're offline" state instead of a scary generic error.
bool isOfflineError(Object? error) {
  if (error == null) return false;
  if (error is SocketException) return true;
  if (error is TimeoutException) return true;
  if (error is http.ClientException) return true;
  // The API layer surfaces unreachable-host failures as status 0.
  if (error is ApiException && error.statusCode == 0) return true;
  final text = error.toString().toLowerCase();
  return text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('connection refused') ||
      text.contains('connection closed') ||
      text.contains('network is unreachable') ||
      text.contains('timed out');
}
