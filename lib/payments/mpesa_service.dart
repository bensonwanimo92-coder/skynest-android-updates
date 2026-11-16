import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

/// Calls the SkyNest Cloudflare Worker M-Pesa API. The base URL is injected at
/// build time; no Daraja credentials are ever stored in the Android app.
class SkyNestMpesaService {
  static const String _baseUrl = String.fromEnvironment(
    'SKYNEST_API_BASE_URL',
    defaultValue: 'https://mpesaapi.bensonwanimo92.workers.dev',
  );

  static Future<Map<String, dynamic>> _call(String path, {String method = 'GET', Map<String, dynamic>? body}) async {
    if (_baseUrl.isEmpty) throw StateError('M-Pesa service is not configured in this app build yet.');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to SkyNest first.');
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) throw StateError('Could not verify your SkyNest session. Sign in again.');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.openUrl(method, Uri.parse(_baseUrl).resolve(path));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
      request.headers.contentType = ContentType.json;
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 45));
      final raw = await response.transform(utf8.decoder).join();
      final data = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(data['error']?.toString() ?? 'M-Pesa request failed. Try again.');
      }
      return data;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>> getLandlordAccount() => _call('/api/mpesa/account');

  static Future<Map<String, dynamic>> saveLandlordAccount({
    required String accountType,
    required String registeredBusinessName,
    required String accountNumber,
  }) => _call('/api/mpesa/account', method: 'POST', body: {
    'accountType': accountType,
    'registeredBusinessName': registeredBusinessName,
    'accountNumber': accountNumber,
  });

  static Future<Map<String, dynamic>> getPaymentRecipient({required String houseId}) =>
      _call('/api/mpesa/recipient?houseId=${Uri.encodeQueryComponent(houseId)}');


  static Future<Map<String, dynamic>> verifyLandlordAccount(String phone) =>
      _call('/api/mpesa/account/verify', method: 'POST', body: {'phone': phone});

  static Future<String> requestStkPush({
    required int amountKes,
    required String phone,
  }) async {
    if (_baseUrl.isEmpty) {
      throw StateError('M-Pesa service is not configured in this app build yet.');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to SkyNest before paying rent.');
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Could not verify your SkyNest session. Sign in again.');
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final uri = Uri.parse(_baseUrl).resolve('/api/mpesa/stkpush');
      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'amountKes': amountKes, 'phone': phone}));
      final response = await request.close().timeout(const Duration(seconds: 45));
      final body = await response.transform(utf8.decoder).join();
      final data = body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(data['error']?.toString() ?? 'M-Pesa request failed. Try again.');
      }
      return data['message']?.toString() ?? 'Check your phone for the M-Pesa prompt.';
    } finally {
      client.close(force: true);
    }
  }
}
