// Placeholder used only when Firebase CI configuration is unavailable.
// The release workflow replaces this file using the protected google-services.json.
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Firebase is not configured. Add FIREBASE_ANDROID_CONFIG_BASE64 in GitHub Secrets.',
    );
  }
}
