import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/recognition/endpoint.dart';

/// Result of "Test connection" in settings.
class ServerHealth {
  const ServerHealth.ok({required this.latency, required this.asr, this.device})
      : reachable = true,
        error = null;

  const ServerHealth.failed(this.error)
      : reachable = false,
        latency = null,
        asr = false,
        device = null;

  final bool reachable;
  final Duration? latency;

  /// The server has speech recognition installed.
  final bool asr;
  final String? device;
  final String? error;
}

typedef HealthChecker = Future<ServerHealth> Function(String address);

/// GET /api/health with a short timeout.
Future<ServerHealth> checkServerHealth(String address) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  final watch = Stopwatch()..start();
  try {
    final request = await client.getUrl(healthUri(address));
    final response = await request.close().timeout(const Duration(seconds: 5));
    final body = await response.transform(utf8.decoder).join();
    watch.stop();
    if (response.statusCode != 200) return ServerHealth.failed('Server answered ${response.statusCode}');
    final json = jsonDecode(body) as Map<String, dynamic>;
    return ServerHealth.ok(
      latency: watch.elapsed,
      asr: json['asr'] == true,
      device: json['asr_device'] as String?,
    );
  } on SocketException {
    return const ServerHealth.failed('Cannot reach the server. Is it running, and on the same Wi-Fi?');
  } on TimeoutException {
    return const ServerHealth.failed('The server did not answer in time.');
  } on FormatException {
    return const ServerHealth.failed('Something answered, but it is not the Rafiq server.');
  } catch (e) {
    return ServerHealth.failed('Connection failed: $e');
  } finally {
    client.close(force: true);
  }
}
