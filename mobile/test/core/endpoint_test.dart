import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/core/recognition/endpoint.dart';
import 'package:rafiq/core/recognition/models.dart';

void main() {
  test('addresses as people type them', () {
    for (final address in [
      '192.168.1.5:8765',
      'http://192.168.1.5:8765',
      'ws://192.168.1.5:8765/',
      ' 192.168.1.5:8765 '
    ]) {
      expect(listenUri(address).toString(), 'ws://192.168.1.5:8765/ws/listen', reason: address);
      expect(healthUri(address).toString(), 'http://192.168.1.5:8765/api/health', reason: address);
    }
  });

  test('secure schemes stay secure', () {
    expect(listenUri('https://rafiq.example.com').toString(), 'wss://rafiq.example.com/ws/listen');
    expect(healthUri('wss://rafiq.example.com').toString(), 'https://rafiq.example.com/api/health');
  });

  test('a path prefix is kept (reverse proxies)', () {
    expect(listenUri('https://example.com/rafiq/').toString(), 'wss://example.com/rafiq/ws/listen');
  });

  test('hints become query parameters', () {
    expect(listenUri('10.0.2.2:8765', hint: const SurahHint(55)).query, 'surah=55');
    expect(listenUri('10.0.2.2:8765', hint: const JuzHint(30)).query, 'juz=30');
  });

  test('validation explains what is wrong', () {
    expect(validateServerAddress('10.0.2.2:8765'), isNull);
    expect(validateServerAddress('https://rafiq.example.com'), isNull);
    expect(validateServerAddress(''), contains('Enter'));
    expect(validateServerAddress('ftp://x'), isNotNull);
  });
}
