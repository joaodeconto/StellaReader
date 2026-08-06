import 'dart:io';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../data/scielo_opds_service.dart';

/// Turns a catalog failure into something a reader can act on.
///
/// The catalog is somebody else's server, so "it broke" is not enough: being
/// offline, SciELO being down, and SciELO changing the shape of its feed all
/// need different responses from the reader.
String describeCatalogError(Object error) {
  // TLS failures arrive wrapped in an unclassified DioException, so they have
  // to be recognised before the type switch below.
  final cause = error is DioException ? (error.error ?? error) : error;

  if ((error is DioException &&
          error.type == DioExceptionType.badCertificate) ||
      isCertificateRejection(cause)) {
    return 'O certificado de segurança do catálogo SciELO está vencido ou '
        'inválido, então o aplicativo se recusa a confiar na conexão. Isso é '
        'um problema no servidor do SciELO e só passa quando eles renovarem '
        'o certificado.';
  }
  if (cause is HandshakeException) {
    return 'Não foi possível estabelecer uma conexão segura com o catálogo '
        'SciELO.';
  }

  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionError || DioExceptionType.connectionTimeout =>
        'Não foi possível se conectar ao catálogo SciELO. Verifique sua '
            'conexão.',
      DioExceptionType.receiveTimeout || DioExceptionType.sendTimeout =>
        'O catálogo SciELO demorou demais para responder.',
      DioExceptionType.badResponse =>
        'O catálogo SciELO respondeu com erro '
            '${error.response?.statusCode ?? 'desconhecido'}.',
      DioExceptionType.badCertificate =>
        'O certificado de segurança do catálogo SciELO não foi aceito.',
      DioExceptionType.cancel => 'A busca no catálogo foi cancelada.',
      DioExceptionType.unknown =>
        'Não foi possível falar com o catálogo SciELO. Se você estiver usando '
            'VPN, tente desligá-la.',
    };
  }

  if (error is FormatException || error is XmlException) {
    return 'O catálogo SciELO respondeu em um formato inesperado.';
  }
  return 'Não foi possível carregar o catálogo SciELO.';
}

/// Whether the peer's certificate was rejected, as opposed to any other way a
/// TLS handshake can fail.
///
/// Dart reports a cipher mismatch and a peer hanging up mid-handshake as
/// HandshakeException too, and neither is the server operator's certificate
/// to renew. Only a verification failure earns that diagnosis.
bool isCertificateRejection(Object? cause) {
  return cause is HandshakeException &&
      cause.toString().contains('CERTIFICATE_VERIFY_FAILED');
}

/// The underlying failure, verbatim.
///
/// The friendly sentence above is a guess at what went wrong; this is what
/// actually happened. Without it a network fault Dio could not classify is
/// indistinguishable from any other, which makes the screen impossible to
/// debug from a screenshot.
String catalogErrorDetail(Object error) {
  if (error is DioException) {
    final cause = error.error ?? error.message;
    return [
      ScieloOpdsService.catalogUri.host,
      error.type.name,
      if (cause != null) '$cause',
    ].join(' · ');
  }
  return '$error';
}
