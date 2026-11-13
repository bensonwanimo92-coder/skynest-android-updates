import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Client-side encryption for SkyNest group messages.
///
/// Plaintext is encrypted on the sender's device with AES-256-GCM. The
/// one-message content key is separately wrapped for each group member using
/// X25519 + HKDF-SHA256 + AES-256-GCM. Private identity keys stay in Android
/// Keystore-backed secure storage and are never written to Firestore.
class SkyNestMessageEncryption {
  SkyNestMessageEncryption._();

  static final SkyNestMessageEncryption instance = SkyNestMessageEncryption._();
  static final FlutterSecureStorage _storage = FlutterSecureStorage();
  static final X25519 _x25519 = X25519();
  static final AesGcm _aes = AesGcm.with256bits();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  String _privateStorageKey(String uid) => 'skynest_e2ee_x25519_private_$uid';
  String _publicStorageKey(String uid) => 'skynest_e2ee_x25519_public_$uid';

  Future<SimpleKeyPairData> _loadOrCreateIdentity(String uid) async {
    final privateEncoded = await _storage.read(key: _privateStorageKey(uid));
    final publicEncoded = await _storage.read(key: _publicStorageKey(uid));
    if (privateEncoded != null && publicEncoded != null) {
      final publicKey = SimplePublicKey(
        base64Decode(publicEncoded),
        type: KeyPairType.x25519,
      );
      final identityRef = FirebaseFirestore.instance
          .collection('users').doc(uid).collection('security').doc('identity');
      final registered = await identityRef.get();
      final registeredKey = registered.data()?['publicKey']?.toString();
      if (!registered.exists || registeredKey != publicEncoded ||
          registered.data()?['algorithm'] != 'X25519' ||
          registered.data()?['keyVersion'] != 1) {
        throw StateError(
          'This device encryption key does not match the registered account identity. '
          'Secure device recovery or identity verification is required.',
        );
      }
      return SimpleKeyPairData(
        base64Decode(privateEncoded),
        publicKey: publicKey,
        type: KeyPairType.x25519,
      );
    }

    final identityRef = FirebaseFirestore.instance
        .collection('users').doc(uid).collection('security').doc('identity');
    final existing = await identityRef.get();
    if (existing.exists) {
      throw StateError(
        'This account already has an encryption identity on another device. '
        'Secure key recovery or device linking is required before sending encrypted messages.',
      );
    }

    final generated = await _x25519.newKeyPair();
    final privateBytes = await generated.extractPrivateKeyBytes();
    final publicKey = await generated.extractPublicKey();
    await _storage.write(
      key: _privateStorageKey(uid),
      value: base64Encode(privateBytes),
    );
    await _storage.write(
      key: _publicStorageKey(uid),
      value: base64Encode(publicKey.bytes),
    );
    await identityRef.set({
      'algorithm': 'X25519',
      'keyVersion': 1,
      'publicKey': base64Encode(publicKey.bytes),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return SimpleKeyPairData(
      privateBytes,
      publicKey: publicKey,
      type: KeyPairType.x25519,
    );
  }

  Future<void> prepareDevice(String uid) async {
    await _loadOrCreateIdentity(uid);
  }

  Future<SecretKey> _deriveWrappingKey({
    required SimpleKeyPairData localKeyPair,
    required SimplePublicKey remotePublicKey,
    required String groupId,
    required String senderId,
    required String recipientId,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: remotePublicKey,
    );
    return _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode(groupId),
      info: utf8.encode('skynest-e2ee-v1:$senderId:$recipientId'),
    );
  }

  Future<Map<String, dynamic>> encryptGroupMessage({
    required String groupId,
    required String senderId,
    required String plaintext,
    required List<String> memberIds,
  }) async {
    final localKeyPair = await _loadOrCreateIdentity(senderId);
    final senderPublicKey = await localKeyPair.extractPublicKey();
    final uniqueMembers = memberIds.toSet()..add(senderId);
    if (uniqueMembers.isEmpty) {
      throw StateError('No group members are available for encrypted delivery.');
    }

    final contentKeyBytes = List<int>.generate(
      32, (_) => math.Random.secure().nextInt(256),
    );
    final contentKey = SecretKey(contentKeyBytes);
    final encryptedMessage = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: contentKey,
      aad: utf8.encode('skynest-message-v1:$groupId:$senderId'),
    );

    final envelopes = <String, dynamic>{};
    for (final recipientId in uniqueMembers) {
      final identitySnapshot = await FirebaseFirestore.instance
          .collection('users').doc(recipientId)
          .collection('security').doc('identity').get();
      final identity = identitySnapshot.data();
      final encodedPublicKey = identity?['publicKey']?.toString();
      if (!identitySnapshot.exists || encodedPublicKey == null || encodedPublicKey.isEmpty) {
        throw StateError(
          'A group member has not activated secure messaging yet. '
          'Ask every member to open the app once, then retry.',
        );
      }
      final recipientPublicKey = SimplePublicKey(
        base64Decode(encodedPublicKey),
        type: KeyPairType.x25519,
      );
      final wrappingKey = await _deriveWrappingKey(
        localKeyPair: localKeyPair,
        remotePublicKey: recipientPublicKey,
        groupId: groupId,
        senderId: senderId,
        recipientId: recipientId,
      );
      final wrapped = await _aes.encrypt(
        contentKeyBytes,
        secretKey: wrappingKey,
        aad: utf8.encode('skynest-key-v1:$groupId:$senderId:$recipientId'),
      );
      envelopes[recipientId] = {
        'nonce': base64Encode(wrapped.nonce),
        'ciphertext': base64Encode(wrapped.cipherText),
        'mac': base64Encode(wrapped.mac.bytes),
      };
    }

    return {
      'encryptionVersion': 1,
      'encryptionAlgorithm': 'X25519-HKDF-SHA256-AES-256-GCM',
      'senderPublicKey': base64Encode(senderPublicKey.bytes),
      'nonce': base64Encode(encryptedMessage.nonce),
      'ciphertext': base64Encode(encryptedMessage.cipherText),
      'mac': base64Encode(encryptedMessage.mac.bytes),
      'keyEnvelopes': envelopes,
    };
  }

  Future<String> decryptGroupMessage({
    required String groupId,
    required String senderId,
    required String recipientId,
    required Map<String, dynamic> message,
  }) async {
    if (message['encryptionVersion'] != 1) {
      throw StateError('This is a legacy message and was not end-to-end encrypted.');
    }
    final localKeyPair = await _loadOrCreateIdentity(recipientId);
    final envelopes = Map<String, dynamic>.from(message['keyEnvelopes'] as Map? ?? const {});
    final envelope = Map<String, dynamic>.from(envelopes[recipientId] as Map? ?? const {});
    if (envelope.isEmpty) {
      throw StateError('This message was not encrypted for this device.');
    }
    final senderPublicEncoded = message['senderPublicKey']?.toString();
    if (senderPublicEncoded == null || senderPublicEncoded.isEmpty) {
      throw StateError('The sender encryption key is missing.');
    }
    // Never trust a sender key supplied only by the message document. Compare
    // it with the sender's authenticated public identity registered in Firestore
    // before deriving any shared secret; this blocks simple key substitution.
    final senderIdentity = await FirebaseFirestore.instance
        .collection('users').doc(senderId)
        .collection('security').doc('identity').get();
    final registeredSenderKey = senderIdentity.data()?['publicKey']?.toString();
    if (!senderIdentity.exists || registeredSenderKey != senderPublicEncoded ||
        senderIdentity.data()?['algorithm'] != 'X25519' ||
        senderIdentity.data()?['keyVersion'] != 1) {
      throw StateError(
        'The sender encryption identity could not be verified. '
        'The message was not decrypted.',
      );
    }
    final senderPublicKey = SimplePublicKey(
      base64Decode(senderPublicEncoded),
      type: KeyPairType.x25519,
    );
    final wrappingKey = await _deriveWrappingKey(
      localKeyPair: localKeyPair,
      remotePublicKey: senderPublicKey,
      groupId: groupId,
      senderId: senderId,
      recipientId: recipientId,
    );
    final contentKeyBox = SecretBox(
      base64Decode(envelope['ciphertext'].toString()),
      nonce: base64Decode(envelope['nonce'].toString()),
      mac: Mac(base64Decode(envelope['mac'].toString())),
    );
    final contentKeyBytes = await _aes.decrypt(
      contentKeyBox,
      secretKey: wrappingKey,
      aad: utf8.encode('skynest-key-v1:$groupId:$senderId:$recipientId'),
    );
    final messageBox = SecretBox(
      base64Decode(message['ciphertext'].toString()),
      nonce: base64Decode(message['nonce'].toString()),
      mac: Mac(base64Decode(message['mac'].toString())),
    );
    final clearBytes = await _aes.decrypt(
      messageBox,
      secretKey: SecretKey(contentKeyBytes),
      aad: utf8.encode('skynest-message-v1:$groupId:$senderId'),
    );
    return utf8.decode(clearBytes);
  }
}
