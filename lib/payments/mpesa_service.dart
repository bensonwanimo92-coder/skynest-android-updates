import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

/// Calls the SkyNest Google Cloud Run M-Pesa API. The base URL is injected at
/// build time; no Daraja credentials are ever stored in the Android app.
class SkyNestMpesaService {
  static const String _baseUrl = String.fromEnvironment('SKYNEST_API_BASE_URL');

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
