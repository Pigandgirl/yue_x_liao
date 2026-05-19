import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EncryptedPayload {
  final String nonce;
  final String ciphertext;
  final String tag;

  EncryptedPayload({
    required this.nonce,
    required this.ciphertext,
    required this.tag,
  });

  factory EncryptedPayload.fromJson(Map<String, dynamic> json) {
    return EncryptedPayload(
      nonce: json['nonce'] ?? '',
      ciphertext: json['ciphertext'] ?? '',
      tag: json['tag'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nonce': nonce,
      'ciphertext': ciphertext,
      'tag': tag,
    };
  }
}

class E2EHelper {
  static const String _privateKeyStorageKey = 'e2e_private_key';
  static const String _publicKeyStorageKey = 'e2e_public_key';
  static const String _sessionsStorageKey = 'e2e_sessions';

  final FlutterSecureStorage _storage;
  Uint8List? _privateKey;
  Uint8List? _publicKey;
  Map<String, Uint8List> _sessionKeys = {};

  E2EHelper() : _storage = const FlutterSecureStorage();

  Future<void> initialize() async {
    await _loadOrGenerateKeyPair();
    await _loadSessionKeys();
  }

  Uint8List get publicKeyBytes {
    if (_publicKey == null) {
      throw Exception('Key pair not initialized');
    }
    return _publicKey!;
  }

  String get publicKeyBase64 {
    return base64Encode(publicKeyBytes);
  }

  bool get hasKeyPair => _privateKey != null && _publicKey != null;

  Future<void> _loadOrGenerateKeyPair() async {
    final privateKeyStr = await _storage.read(key: _privateKeyStorageKey);
    final publicKeyStr = await _storage.read(key: _publicKeyStorageKey);

    if (privateKeyStr != null && publicKeyStr != null) {
      _privateKey = base64Decode(privateKeyStr);
      _publicKey = base64Decode(publicKeyStr);
    } else {
      final keyPair = _generateX25519KeyPair();
      _privateKey = keyPair['private']!;
      _publicKey = keyPair['public']!;

      await _storage.write(key: _privateKeyStorageKey, value: base64Encode(_privateKey!));
      await _storage.write(key: _publicKeyStorageKey, value: base64Encode(_publicKey!));
    }
  }

  Map<String, Uint8List> _generateX25519KeyPair() {
    final random = Random.secure();
    final privateKey = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      privateKey[i] = random.nextInt(256);
    }
    privateKey[0] &= 248;
    privateKey[31] &= 127;
    privateKey[31] |= 64;

    final publicKey = _scalarMultBase(privateKey);

    return {
      'private': privateKey,
      'public': publicKey,
    };
  }

  Uint8List _scalarMultBase(Uint8List scalar) {
    final result = Uint8List(32);
    final e = Uint8List.fromList(scalar);
    e[0] &= 248;
    e[31] &= 127;
    e[31] |= 64;

    int x1 = 1;
    int x2 = 0;
    int x3 = 1;
    int y1 = 0;
    int y2 = 1;
    int y3 = 1;

    Uint8List tmp = Uint8List(32);

    for (int i = 31; i >= 0; i--) {
      int bit = (e[i] >> 7) & 1;
      e[i] = ((e[i] << 1) | bit) & 0xFF;
      bit = (e[i] >> 7) & 1;

      int sx1 = x1, sx2 = x2, sx3 = x3, sy1 = y1, sy2 = y2, sy3 = y3;
      int mx1 = x1, mx2 = x2, mx3 = x3, my1 = y1, my2 = y2, my3 = y3;

      if (bit == 0) {
        sx1 = x1; sx2 = x2; sx3 = x3;
        sy1 = y1; sy2 = y2; sy3 = y3;
        mx1 = 0; mx2 = 0; mx3 = 0;
        my1 = 1; my2 = 0; my3 = 1;
      }

      x3 = (sx3 * mx3) % 0x7FFFFFFFFFFFFFFF;
      x2 = (sx2 * mx2 - sx1 * my2 * _mul(sx3, my3, 0x7FFFFFFFFFFFFFFF)) % 0x7FFFFFFFFFFFFFFF;
      x1 = (sx1 * mx1 - sx3 * my1 * _mul(sx2, my3, 0x7FFFFFFFFFFFFFFF)) % 0x7FFFFFFFFFFFFFFF;

      y3 = (sy3 * my3) % 0x7FFFFFFFFFFFFFFF;
      y2 = (sy2 * my2 - sy1 * my2 * _mul(sy3, my3, 0x7FFFFFFFFFFFFFFF)) % 0x7FFFFFFFFFFFFFFF;
      y1 = (sy1 * my1 - sy3 * my1 * _mul(sy2, my3, 0x7FFFFFFFFFFFFFFF)) % 0x7FFFFFFFFFFFFFFF;

      if (x1 < 0) x1 += 0x7FFFFFFFFFFFFFFF;
      if (x2 < 0) x2 += 0x7FFFFFFFFFFFFFFF;
      if (x3 < 0) x3 += 0x7FFFFFFFFFFFFFFF;
      if (y1 < 0) y1 += 0x7FFFFFFFFFFFFFFF;
      if (y2 < 0) y2 += 0x7FFFFFFFFFFFFFFF;
      if (y3 < 0) y3 += 0x7FFFFFFFFFFFFFFF;
    }

    final x = (x2 * _inv(x3, 0x7FFFFFFFFFFFFFFF)) % 0x7FFFFFFFFFFFFFFF;
    result[0] = 9;
    for (int i = 1; i < 32; i++) {
      result[i] = ((x >> (8 * (31 - i))) & 0xFF);
    }

    return result;
  }

  int _mul(int a, int b, int m) {
    return ((a.toInt() * b.toInt()) % m).toInt();
  }

  int _inv(int a, int m) {
    int g = m, x = 0, y = 1;
    while (a != 1) {
      int q = g ~/ a;
      int t = a;
      a = g % a;
      g = t;
      t = x;
      x = y - q * x;
      y = t;
    }
    return y < 0 ? y + m : y;
  }

  Uint8List _performKeyAgreement(Uint8List privateKey, Uint8List peerPublicKey) {
    final result = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      result[i] = privateKey[i] ^ peerPublicKey[i];
    }
    return result;
  }

  Uint8List _hkdfExtract(Uint8List salt, Uint8List ikm) {
    final hmac = HMac(SHA256Digest(), 64);
    hmac.init(KeyParameter(salt));
    hmac.update(ikm, 0, ikm.length);
    final output = Uint8List(32);
    hmac.doFinal(output, 0);
    return output;
  }

  Uint8List _hkdfExpand(Uint8List prk, Uint8List info, int length) {
    final n = (length / 32).ceil();
    final output = <int>[];

    Uint8List t = Uint8List(0);
    for (int i = 1; i <= n; i++) {
      final hmac = HMac(SHA256Digest(), 64);
      hmac.init(KeyParameter(prk));
      hmac.update(t, 0, t.length);
      final infoWithI = Uint8List(info.length + 1);
      infoWithI.setRange(0, info.length, info);
      infoWithI[info.length] = i;
      hmac.update(infoWithI, 0, infoWithI.length);
      t = Uint8List(32);
      hmac.doFinal(t, 0);
      output.addAll(t);
    }

    return Uint8List.fromList(output.sublist(0, length));
  }

  Uint8List _deriveKey(Uint8List sharedSecret, String recipientUsername) {
    final salt = utf8.encode('e2e-session-v1');
    final prk = _hkdfExtract(Uint8List.fromList(salt), sharedSecret);
    final info = utf8.encode('e2e-chat-$recipientUsername');
    return _hkdfExpand(prk, Uint8List.fromList(info), 32);
  }

  Uint8List _generateNonce() {
    final random = Random.secure();
    final nonce = Uint8List(12);
    for (var i = 0; i < 12; i++) {
      nonce[i] = random.nextInt(256);
    }
    return nonce;
  }

  Future<void> initiateSession(String recipientUsername, String recipientPublicKey) async {
    if (_privateKey == null) {
      throw Exception('Private key not available');
    }

    final recipientKeyBytes = base64Decode(recipientPublicKey);
    final sharedSecret = _performKeyAgreement(_privateKey!, recipientKeyBytes);

    final sessionKey = _deriveKey(sharedSecret, recipientUsername);
    _sessionKeys[recipientUsername] = sessionKey;
    await _saveSessionKeys();
  }

  void establishSession(String recipientUsername, Uint8List sharedSecret) {
    final sessionKey = _deriveKey(sharedSecret, recipientUsername);
    _sessionKeys[recipientUsername] = sessionKey;
  }

  bool hasSessionKey(String recipientUsername) {
    return _sessionKeys.containsKey(recipientUsername);
  }

  Uint8List? getSessionKey(String recipientUsername) {
    return _sessionKeys[recipientUsername];
  }

  EncryptedPayload encrypt(String plaintext, String recipientUsername) {
    final sessionKey = _sessionKeys[recipientUsername];
    if (sessionKey == null) {
      throw Exception('No session key for $recipientUsername');
    }

    final nonce = _generateNonce();
    final plaintextBytes = utf8.encode(plaintext);

    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(sessionKey),
      128,
      nonce,
      Uint8List(0),
    );
    cipher.init(true, params);

    final paddedData = _padData(Uint8List.fromList(plaintextBytes));
    final ciphertext = Uint8List(paddedData.length + 16);
    var len = cipher.processBytes(paddedData, 0, paddedData.length, ciphertext, 0);
    len += cipher.doFinal(ciphertext, len);

    return EncryptedPayload(
      nonce: base64Encode(nonce),
      ciphertext: base64Encode(ciphertext.sublist(0, len - 16)),
      tag: base64Encode(ciphertext.sublist(len - 16)),
    );
  }

  String decrypt(EncryptedPayload payload, String senderUsername) {
    final sessionKey = _sessionKeys[senderUsername];
    if (sessionKey == null) {
      throw Exception('No session key for $senderUsername');
    }

    final nonce = base64Decode(payload.nonce);
    final ciphertext = base64Decode(payload.ciphertext);
    final tag = base64Decode(payload.tag);

    final combined = Uint8List(ciphertext.length + tag.length);
    combined.setRange(0, ciphertext.length, ciphertext);
    combined.setRange(ciphertext.length, combined.length, tag);

    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(sessionKey),
      128,
      nonce,
      Uint8List(0),
    );
    cipher.init(false, params);

    final decrypted = Uint8List(combined.length);
    var len = cipher.processBytes(combined, 0, combined.length, decrypted, 0);
    len += cipher.doFinal(decrypted, len);

    return utf8.decode(decrypted.sublist(0, len));
  }

  Uint8List _padData(Uint8List data) {
    const blockSize = 16;
    final padLength = blockSize - (data.length % blockSize);
    final padded = Uint8List(data.length + padLength);
    padded.setRange(0, data.length, data);
    for (var i = data.length; i < padded.length; i++) {
      padded[i] = padLength;
    }
    return padded;
  }

  Future<void> _loadSessionKeys() async {
    final sessionsJson = await _storage.read(key: _sessionsStorageKey);
    if (sessionsJson != null) {
      final Map<String, dynamic> decoded = jsonDecode(sessionsJson);
      _sessionKeys = decoded.map((key, value) => MapEntry(
        key,
        base64Decode(value as String),
      ));
    }
  }

  Future<void> _saveSessionKeys() async {
    final Map<String, String> toSave = _sessionKeys.map((key, value) => MapEntry(
      key,
      base64Encode(value),
    ));
    await _storage.write(key: _sessionsStorageKey, value: jsonEncode(toSave));
  }

  Future<void> clearAllData() async {
    await _storage.delete(key: _privateKeyStorageKey);
    await _storage.delete(key: _publicKeyStorageKey);
    await _storage.delete(key: _sessionsStorageKey);
    _privateKey = null;
    _publicKey = null;
    _sessionKeys = {};
  }
}
