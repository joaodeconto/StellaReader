import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellareader/ui/catalog_error.dart';

DioException _wrapping(Object cause) => DioException(
  requestOptions: RequestOptions(path: '/opds/'),
  type: DioExceptionType.unknown,
  error: cause,
);

/// What Dart throws when the peer's certificate does not verify — the case
/// that actually is SciELO's to fix.
final _expiredCertificate = HandshakeException(
  'Handshake error in client',
  const OSError(
    'CERTIFICATE_VERIFY_FAILED: certificate has expired(handshake.cc:359)',
  ),
);

/// A handshake that failed for some other reason. Same exception type, but
/// blaming the certificate here would be a wrong diagnosis.
final _cipherMismatch = HandshakeException(
  'Handshake error in client',
  const OSError('WRONG_VERSION_NUMBER(tls_record.cc:242)'),
);

void main() {
  group('describeCatalogError', () {
    test('blames the certificate when verification failed', () {
      final message = describeCatalogError(_wrapping(_expiredCertificate));

      expect(message, contains('certificado'));
      expect(message, contains('servidor do SciELO'));
    });

    test('stays neutral for a handshake that is not about the certificate', () {
      final message = describeCatalogError(_wrapping(_cipherMismatch));

      expect(message, contains('conexão segura'));
      // The reader must not be told to wait on a certificate renewal that
      // would not fix anything.
      expect(message, isNot(contains('certificado')));
      expect(message, isNot(contains('renovarem')));
    });

    test('blames the certificate for an explicit badCertificate', () {
      final message = describeCatalogError(
        DioException(
          requestOptions: RequestOptions(path: '/opds/'),
          type: DioExceptionType.badCertificate,
        ),
      );

      expect(message, contains('certificado'));
    });

    test('reports the status code the catalog answered with', () {
      final message = describeCatalogError(
        DioException(
          requestOptions: RequestOptions(path: '/opds/'),
          type: DioExceptionType.badResponse,
          response: Response<void>(
            requestOptions: RequestOptions(path: '/opds/'),
            statusCode: 503,
          ),
        ),
      );

      expect(message, contains('503'));
    });

    test('separates being offline from the server being slow', () {
      final offline = describeCatalogError(
        DioException(
          requestOptions: RequestOptions(path: '/opds/'),
          type: DioExceptionType.connectionError,
        ),
      );
      final slow = describeCatalogError(
        DioException(
          requestOptions: RequestOptions(path: '/opds/'),
          type: DioExceptionType.receiveTimeout,
        ),
      );

      expect(offline, contains('conexão'));
      expect(slow, contains('demorou'));
      expect(offline, isNot(slow));
    });

    test('recognises a malformed feed', () {
      expect(
        describeCatalogError(const FormatException('bad')),
        contains('formato inesperado'),
      );
    });
  });

  group('catalogErrorDetail', () {
    test('names the host and the underlying failure', () {
      final detail = catalogErrorDetail(_wrapping(_expiredCertificate));

      expect(detail, contains('books.scielo.org'));
      expect(detail, contains('unknown'));
      expect(detail, contains('CERTIFICATE_VERIFY_FAILED'));
    });
  });
}
