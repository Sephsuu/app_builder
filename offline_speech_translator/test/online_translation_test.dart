import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_speech_translator/features/translation/data/hybrid_translation_service.dart';
import 'package:offline_speech_translator/features/translation/data/openai_translation_service.dart';
import 'package:offline_speech_translator/features/translation/data/local_translation_service.dart';
import 'package:offline_speech_translator/features/translation/domain/translation.dart';

const tl = TranslationLanguage.tagalog;
const ceb = TranslationLanguage.cebuano;
Map<String, Object> responseBody(String text) => {
  'status': 'completed',
  'output': [
    {'type': 'reasoning'},
    {
      'type': 'message',
      'role': 'assistant',
      'content': [
        {'type': 'output_text', 'text': text},
      ],
    },
  ],
};

class Translator implements TranslationService {
  int calls = 0;
  int cancellations = 0;
  Object? failure;
  Completer<String>? pending;
  @override
  Future<String> translate(
    String text,
    TranslationLanguage source,
    TranslationLanguage target,
  ) async {
    calls++;
    if (failure != null) throw failure!;
    return pending?.future ?? 'Asa ta moadto unya?';
  }

  @override
  Future<void> cancel() async {
    cancellations++;
  }
}

class Headers extends Fake implements HttpHeaders {
  final values = <String, Object>{};
  @override
  set contentType(ContentType? value) {
    values['Content-Type'] = value.toString();
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value;
  }
}

class Request extends Fake implements HttpClientRequest {
  final capturedHeaders = Headers();
  final body = StringBuffer();
  int code = 200;
  bool redirects = true;
  Completer<HttpClientResponse>? pending;
  @override
  HttpHeaders get headers => capturedHeaders;
  @override
  set followRedirects(bool value) {
    redirects = value;
  }

  @override
  void write(Object? object) {
    body.write(object);
  }

  @override
  Future<HttpClientResponse> close() async => pending?.future ?? Response(code);
}

class Response extends Stream<List<int>> implements HttpClientResponse {
  Response(this.statusCode);
  @override
  final int statusCode;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream.value(
        utf8.encode(jsonEncode(responseBody('Asa ta moadto unya?'))),
      ).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Client extends Fake implements HttpClient {
  final request = Request();
  Uri? uri;
  bool closed = false;
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    uri = url;
    return request;
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}

void main() {
  test(
    'Responses request uses final text, direction, private storage flag and fixed HTTPS endpoint',
    () async {
      final client = Client();
      final service = OpenAITranslationService(
        readKey: () async => 'test-only-token',
        clientFactory: () => client,
      );
      expect(
        await service.translate('saan tayo pupunta mamaya', tl, ceb),
        'Asa ta moadto unya?',
      );
      expect(client.uri.toString(), 'https://api.openai.com/v1/responses');
      expect(client.request.redirects, false);
      final body = jsonDecode(client.request.body.toString()) as Map;
      expect(body['input'], 'saan tayo pupunta mamaya');
      expect(body['store'], false);
      expect(body['instructions'], contains('from Tagalog to Cebuano'));
      expect(
        OpenAITranslationService.requestBody('Asa?', ceb, tl)['instructions'],
        contains('from Cebuano (Bisaya) to Tagalog'),
      );
      expect(client.closed, true);
    },
  );
  for (final status in [401, 403, 429, 500, 302]) {
    test(
      'HTTP $status is rejected without returning a response body',
      () async {
        final client = Client()..request.code = status;
        final service = OpenAITranslationService(
          readKey: () async => 'test-only-token',
          clientFactory: () => client,
        );
        await expectLater(
          service.translate('Kumusta', tl, ceb),
          throwsA(isA<TranslationFailure>()),
        );
        expect(client.closed, true);
      },
    );
  }
  test('request timeout closes its socket', () async {
    final client = Client()..request.pending = Completer<HttpClientResponse>();
    final service = OpenAITranslationService(
      readKey: () async => 'test-only-token',
      clientFactory: () => client,
      timeout: const Duration(milliseconds: 5),
    );
    await expectLater(
      service.translate('Kumusta', tl, ceb),
      throwsA(isA<TranslationFailure>()),
    );
    expect(client.closed, true);
    client.request.pending!.complete(Response(200));
  });
  test('cancel rejects a late online response', () async {
    final client = Client()..request.pending = Completer<HttpClientResponse>();
    final service = OpenAITranslationService(
      readKey: () async => 'test-only-token',
      clientFactory: () => client,
    );
    final result = service.translate('Kumusta', tl, ceb);
    final assertion = expectLater(result, throwsA(isA<TranslationFailure>()));
    await Future<void>.delayed(Duration.zero);
    await service.cancel();
    client.request.pending!.complete(Response(200));
    await assertion;
    expect(client.closed, true);
  });
  test(
    'incomplete, empty and refused responses cannot become translations',
    () {
      for (final body in [
        {...responseBody('partial'), 'status': 'incomplete'},
        responseBody(''),
        {
          'status': 'completed',
          'output': [
            {
              'type': 'message',
              'role': 'assistant',
              'content': [
                {'type': 'refusal', 'refusal': 'no'},
              ],
            },
          ],
        },
      ]) {
        expect(
          () => OpenAITranslationService.parseResponse(body),
          throwsA(isA<TranslationFailure>()),
        );
      }
    },
  );
  for (final connected in [true, false]) {
    for (final configured in [true, false]) {
      test('route connected=$connected configured=$configured', () async {
        final online = Translator(), offline = Translator();
        final service = HybridTranslationService(
          offline: offline,
          online: online,
          isOnline: () async => connected,
          configured: () async => configured,
        );
        await service.translate('Kumusta', tl, ceb);
        expect(online.calls, connected && configured ? 1 : 0);
        expect(offline.calls, connected && configured ? 0 : 1);
      });
    }
  }
  test('online failure falls back; next turn retries OpenAI', () async {
    final online = Translator()
      ..failure = const TranslationFailure('OpenAI timed out.');
    final offline = Translator();
    final service = HybridTranslationService(
      offline: offline,
      online: online,
      isOnline: () async => true,
      configured: () async => true,
    );
    await service.translate('Kumusta', tl, ceb);
    expect(service.status.value, contains('Translated offline'));
    expect(offline.calls, 1);
    online.failure = null;
    await service.translate('Maayo', ceb, tl);
    expect(online.calls, 2);
    expect(service.status.value, 'Translated with OpenAI');
  });
  test('cancelled online failure never starts offline inference', () async {
    final online = Translator()..pending = Completer<String>();
    final offline = Translator();
    final service = HybridTranslationService(
      offline: offline,
      online: online,
      isOnline: () async => true,
      configured: () async => true,
    );
    final result = service.translate('Kumusta', tl, ceb);
    final assertion = expectLater(result, throwsA(isA<TranslationFailure>()));
    await Future<void>.delayed(Duration.zero);
    await service.cancel();
    online.pending!.completeError(const TranslationFailure('Disconnected'));
    await assertion;
    expect(offline.calls, 0);
    expect(online.cancellations, 1);
  });
  test(
    'cancel during connectivity check cannot send text or start fallback',
    () async {
      final connectivity = Completer<bool>();
      final online = Translator(), offline = Translator();
      final service = HybridTranslationService(
        offline: offline,
        online: online,
        configured: () async => true,
        isOnline: () => connectivity.future,
      );
      final result = service.translate('Kumusta', tl, ceb);
      final assertion = expectLater(result, throwsA(isA<TranslationFailure>()));
      await Future<void>.delayed(Duration.zero);
      await service.cancel();
      connectivity.complete(true);
      await assertion;
      expect(online.calls, 0);
      expect(offline.calls, 0);
    },
  );
  test('unavailable offline model reports actionable setup error', () async {
    final offline = Translator()
      ..failure = const TranslationFailure('Missing model');
    final service = HybridTranslationService(
      offline: offline,
      online: Translator(),
      configured: () async => true,
      isOnline: () async => false,
    );
    await expectLater(
      service.translate('Kumusta', tl, ceb),
      throwsA(
        isA<TranslationFailure>().having(
          (e) => e.message,
          'message',
          contains('offline model in settings'),
        ),
      ),
    );
  });
  test('immediate cancellation prevents sending a request', () async {
    final client = Client();
    final service = OpenAITranslationService(
      readKey: () async => 'test-only-token',
      clientFactory: () => client,
    );
    final result = service.translate('Kumusta', tl, ceb);
    final assertion = expectLater(result, throwsA(isA<TranslationFailure>()));
    await service.cancel();
    await assertion;
    expect(client.uri, isNull);
  });
}
