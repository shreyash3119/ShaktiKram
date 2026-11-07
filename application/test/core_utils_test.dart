import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/core/auth/uuid.dart';
import 'package:shaktikram/core/backend/backend_error.dart';
import 'package:shaktikram/core/backend/backend_gateway.dart';
import 'package:shaktikram/core/config/app_config.dart';

String _b64(String s) => base64Url.encode(utf8.encode(s)).replaceAll('=', '');
String _jwt(String role) =>
    '${_b64('{"alg":"HS256","typ":"JWT"}')}.${_b64('{"role":"$role"}')}.signature';

void main() {
  group('BackendError', () {
    test('reads the code from the message prefix', () {
      final e = BackendError.fromRaw(
        httpCode: 'PT403',
        message: 'device_revoked: this device was revoked',
      );
      expect(e.code, 'device_revoked');
      expect(e.message, 'this device was revoked');
      expect(e.isDeviceRevoked, isTrue);
    });

    test('falls back to the PostgREST status code', () {
      expect(
        BackendError.fromRaw(httpCode: 'PT401', message: 'nope').code,
        'unauthorized',
      );
      expect(
        BackendError.fromRaw(httpCode: 'PT404', message: 'nope').code,
        'not_found',
      );
      expect(
        BackendError.fromRaw(httpCode: 'PGRST301', message: 'JWT expired').code,
        'unauthorized',
      );
      expect(
        BackendError.fromRaw(httpCode: null, message: 'boom').code,
        'internal_error',
      );
    });

    test('recognises a second owner attempt', () {
      final e = BackendError.fromRaw(
        httpCode: 'PT401',
        message: 'unauthorized: this app already has an owner',
      );
      expect(e.isNotOwner, isTrue);
      expect(
        BackendError.fromRaw(
          httpCode: 'PT401',
          message: 'unauthorized: sign in first',
        ).isNotOwner,
        isFalse,
      );
    });

    test('unreachable uses the contract code', () {
      const e = BackendError.unreachable();
      expect(e.code, 'unavailable');
      expect(e.isUnreachable, isTrue);
      expect(e.userMessage, contains('Cannot reach the server'));
    });
  });

  group('DeviceRecord', () {
    test('parses a server row', () {
      final d = DeviceRecord.fromJson({
        'id': 'abc',
        'label': 'Gym phone',
        'platform': 'mobile',
        'created_at': '2026-11-07T04:00:00+00:00',
        'last_seen_at': '2026-11-07T05:00:00Z',
        'revoked_at': null,
      });
      expect(d.label, 'Gym phone');
      expect(d.lastSeenAt, DateTime.utc(2026, 11, 7, 5));
      expect(d.isRevoked, isFalse);
    });

    test('a revoked row is marked revoked', () {
      final d = DeviceRecord.fromJson({
        'id': 'abc',
        'label': 'x',
        'platform': 'web',
        'revoked_at': '2026-11-07T06:00:00Z',
      });
      expect(d.isRevoked, isTrue);
    });
  });

  group('AppConfig', () {
    test('asks for the settings when they are missing', () {
      expect(
        AppConfig.checkConfig(url: '', publishableKey: ''),
        contains('SUPABASE_URL'),
      );
    });

    test('rejects an address that is not a URL', () {
      expect(
        AppConfig.checkConfig(url: 'not a url', publishableKey: _jwt('anon')),
        contains('not a valid address'),
      );
    });

    test('accepts a public anon key', () {
      expect(
        AppConfig.checkConfig(
          url: 'https://abc.supabase.co',
          publishableKey: _jwt('anon'),
        ),
        isNull,
      );

      expect(
        AppConfig.checkConfig(
          url: 'https://abc.supabase.co',
          publishableKey: 'sb_publishable_abc123',
        ),
        isNull,
      );
    });

    test('refuses a service-role key', () {
      expect(
        AppConfig.checkPublishableKey(_jwt('service_role')),
        contains('secret'),
      );

      expect(
        AppConfig.checkPublishableKey('sb_secret_abc123'),
        contains('secret'),
      );
    });
  });

  group('newUuidV4', () {
    test('has the version 4 format', () {
      final id = newUuidV4();
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(id),
        isTrue,
        reason: id,
      );
    });

    test('differs between calls', () {
      expect(newUuidV4(), isNot(newUuidV4()));
    });
  });
}
