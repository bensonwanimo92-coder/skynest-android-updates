import 'package:chuka/security/biometric_security.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

class _FakeLocalAuthentication extends LocalAuthentication {
  _FakeLocalAuthentication({
    required this.biometricHardware,
    required this.deviceCredential,
  });

  final bool biometricHardware;
  final bool deviceCredential;

  @override
  Future<bool> get canCheckBiometrics async => biometricHardware;

  @override
  Future<bool> isDeviceSupported() async => deviceCredential;
}

void main() {
  group('SkyNest App Lock capability detection', () {
    test('supports a biometric-capable device', () async {
      final biometrics = SkyNestBiometrics.forTesting(
        _FakeLocalAuthentication(
          biometricHardware: true,
          deviceCredential: false,
        ),
      );

      expect(await biometrics.supported, isTrue);
    });

    test('supports a secure device-credential-only device', () async {
      final biometrics = SkyNestBiometrics.forTesting(
        _FakeLocalAuthentication(
          biometricHardware: false,
          deviceCredential: true,
        ),
      );

      expect(await biometrics.supported, isTrue);
    });

    test('rejects devices with neither authentication method', () async {
      final biometrics = SkyNestBiometrics.forTesting(
        _FakeLocalAuthentication(
          biometricHardware: false,
          deviceCredential: false,
        ),
      );

      expect(await biometrics.supported, isFalse);
    });
  });
}
