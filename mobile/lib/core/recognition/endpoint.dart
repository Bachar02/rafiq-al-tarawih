/// Server addresses as people type them -> the URIs the app needs.
///
/// Accepts `192.168.1.5:8765`, `http://192.168.1.5:8765`, `ws://host:8765/`,
/// and the https/wss equivalents.
library;

import 'models.dart';

/// Null if [address] is usable, else a short reason to show the user.
String? validateServerAddress(String address) {
  final text = address.trim();
  if (text.isEmpty) return 'Enter the address shown by the server, e.g. 192.168.1.5:8765';
  final uri = Uri.tryParse(_withScheme(text, 'ws'));
  if (uri == null || uri.host.isEmpty) return 'That does not look like an address';
  if (!const {'ws', 'wss'}.contains(uri.scheme)) return 'Use an http(s):// or ws(s):// address';
  return null;
}

/// WebSocket URI for live listening, with the optional hint as a query.
Uri listenUri(String address, {Hint? hint}) {
  final base = Uri.parse(_withScheme(address.trim(), 'ws'));
  final query = switch (hint) {
    SurahHint(:final surah) => {'surah': '$surah'},
    JuzHint(:final juz) => {'juz': '$juz'},
    null => null,
  };
  return base.replace(path: '${_trimSlash(base.path)}/ws/listen', queryParameters: query);
}

/// HTTP URI of the health endpoint (used by "Test connection").
Uri healthUri(String address) {
  final base = Uri.parse(_withScheme(address.trim(), 'http'));
  return base.replace(path: '${_trimSlash(base.path)}/api/health');
}

String _withScheme(String text, String family) {
  final secure = text.startsWith('https://') || text.startsWith('wss://');
  final bare = text.replaceFirst(RegExp(r'^(https?|wss?)://'), '');
  if (text.contains('://') && !RegExp(r'^(https?|wss?)://').hasMatch(text)) return text; // unknown scheme
  final scheme = family == 'ws' ? (secure ? 'wss' : 'ws') : (secure ? 'https' : 'http');
  return '$scheme://$bare';
}

String _trimSlash(String path) => path.replaceAll(RegExp(r'/+$'), '');
