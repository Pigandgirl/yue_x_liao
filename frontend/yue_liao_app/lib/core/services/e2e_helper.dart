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

  factory EncryptedPayload.fromBase64(String combined) {
    final combinedBytes = base64Decode(combined);
    final nonce = base64Encode(combinedBytes.sublist(0, 12));
    final tag = base64Encode(combinedBytes.sublist(combinedBytes.length - 16));
    final ciphertext = base64Encode(combinedBytes.sublist(12, combinedBytes.length - 16));
    return EncryptedPayload(
      nonce: nonce,
      ciphertext: ciphertext,
      tag: tag,
    );
  }

  String toBase64() {
    final nonceBytes = base64Decode(nonce);
    final ciphertextBytes = base64Decode(ciphertext);
    final tagBytes = base64Decode(tag);
    final combined = Uint8List(nonceBytes.length + ciphertextBytes.length + tagBytes.length);
    combined.setRange(0, nonceBytes.length, nonceBytes);
    combined.setRange(nonceBytes.length, nonceBytes.length + ciphertextBytes.length, ciphertextBytes);
    combined.setRange(nonceBytes.length + ciphertextBytes.length, combined.length, tagBytes);
    return base64Encode(combined);
  }
}

class E2EHelper {
  static const String _privateKeyStorageKey = 'e2e_private_key';
  static const String _publicKeyStorageKey = 'e2e_public_key';
  static const String _sessionsStorageKey = 'e2e_sessions';

  final FlutterSecureStorage _storage;
  AsymmetricKeyPair<PublicKey, PrivateKey>? _keyPair;
  Map<String, Uint8List> _sessionKeys = {};

  E2EHelper() : _storage = const FlutterSecureStorage();

  Future<void> initialize() async {
    await _loadOrGenerateKeyPair();
    await _loadSessionKeys();
  }

  Uint8List get publicKeyBytes {
    if (_keyPair == null) {
      throw Exception('Key pair not initialized');
    }
    return _encodePublicKey(_keyPair!.publicKey);
  }

  String get publicKeyBase64 {
    return base64Encode(publicKeyBytes);
  }

  bool get hasKeyPair => _keyPair != null;

  Future<Uint8List?> getPrivateKey() async {
    final privateKeyStr = await _storage.read(key: _privateKeyStorageKey);
    if (privateKeyStr == null) return null;
    return base64Decode(privateKeyStr);
  }

  Future<void> _loadOrGenerateKeyPair() async {
    final privateKeyStr = await _storage.read(key: _privateKeyStorageKey);
    final publicKeyStr = await _storage.read(key: _publicKeyStorageKey);

    if (privateKeyStr != null && publicKeyStr != null) {
      final privateKeyBytes = base64Decode(privateKeyStr);
      final publicKeyBytes = base64Decode(publicKeyStr);
      _keyPair = AsymmetricKeyPair(
        _decodePublicKey(publicKeyBytes),
        _decodePrivateKey(privateKeyBytes),
      );
    } else {
      _keyPair = _generateKeyPair();
      await _storage.write(
        key: _privateKeyStorageKey,
        value: base64Encode(_keyPair!.privateKey.key),
      );
      await _storage.write(
        key: _publicKeyStorageKey,
        value: base64Encode(publicKeyBytes),
      );
    }
  }

  AsymmetricKeyPair<PublicKey, PrivateKey> _generateKeyPair() {
    final keyGen = ECKeyGenerator();
    final params = ECKeyGeneratorParameters(ECCurve_curve25519());
    keyGen.init(ParametersWithRandom(params, _secureRandom()));

    final pair = keyGen.generateKeyPair();
    return AsymmetricKeyPair(pair.publicKey, pair.privateKey);
  }

  Uint8List _encodePublicKey(PublicKey publicKey) {
    final publicKeyParams = publicKey as ECPublicKey;
    final point = publicKeyParams.Q!;
    final x = point.x!.toBigInteger()!.toUnsigned(32);
    final y = point.y!.toBigInteger()!.toUnsigned(32);

    final result = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      result[i] = (x.intValue() >> (8 * (31 - i))) & 0xFF;
    }
    return result;
  }

  PublicKey _decodePublicKey(Uint8List bytes) {
    final point = FiniteFieldECPoint(
      ECCurve_curve25519(),
      BigInt.parse('2', radix: 16),
      BigInt.parse(base64Encode(bytes), radix: 10),
      false,
    );
    return ECPublicKey(point, ECCurve_curve25519());
  }

  PrivateKey _decodePrivateKey(Uint8List bytes) {
    return ECPrivateKey(
      BigInt.parse(base64Encode(bytes), radix: 10),
      ECCurve_curve25519(),
    );
  }

  SecureRandom _secureRandom() {
    final secureRandom = FortunaRandom();
    final seed = Uint8List(32);
    final random = Random.secure();
    for (var i = 0; i < 32; i++) {
      seed[i] = random.nextInt(256);
    }
    secureRandom.seed(KeyParameter(seed));
    return secureRandom;
  }

  Uint8List _performKeyAgreement(PrivateKey privateKey, Uint8List peerPublicKeyBytes) {
    final peerPublicKey = _decodePublicKey(peerPublicKeyBytes);

    final dhAgreement = ECDHBasicAgreement();
    dhAgreement.init(privateKey);
    final sharedSecret = dhAgreement.calculateAgreement(peerPublicKey);

    final sharedSecretBytes = Uint8List(32);
    final secretInt = sharedSecret.toBigInteger()!;
    for (int i = 0; i < 32; i++) {
      sharedSecretBytes[i] = (secretInt >> (8 * (31 - i))) & 0xFF;
    }
    return sharedSecretBytes;
  }

  Uint8List _deriveKey(Uint8List sharedSecret, Uint8List info) {
    final hmac = HMac(SHA256Digest(), 64);
    hmac.init(KeyParameter(sharedSecret));

    final hmacOutput = Uint8List(64);
    hmac.update(info, 0, info.length);
    hmac.doFinal(hmacOutput, 0);

    return Uint8List.fromList(hmacOutput.sublist(0, 32));
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
    final privateKey = await getPrivateKey();
    if (privateKey == null) {
      throw Exception('Private key not available');
    }

    final recipientKeyBytes = base64Decode(recipientPublicKey);
    final sharedSecret = _performKeyAgreement(_decodePrivateKey(privateKey), recipientKeyBytes);

    final info = utf8.encode('e2e_session_${recipientUsername}');
    final sessionKey = _deriveKey(sharedSecret, Uint8List.fromList(info));

    _sessionKeys[recipientUsername] = sessionKey;
    await _saveSessionKeys();
  }

  void establishSession(String recipientUsername, Uint8List sharedSecret) {
    final info = utf8.encode('e2e_session_${recipientUsername}');
    final sessionKey = _deriveKey(sharedSecret, Uint8List.fromList(info));
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

    final paddedData = _padData(plaintextBytes);
    final ciphertext = Uint8List(paddedData.length + 16);
    var len = cipher.processBytes(paddedData, 0, paddedData.length, ciphertext, 0);
    len += cipher.doFinal(ciphertext, len);

    final result = Uint8List(nonce.length + len);
    result.setRange(0, nonce.length, nonce);
    result.setRange(nonce.length, result.length, ciphertext.sublist(0, len));

    return EncryptedPayload.fromBase64(base64Encode(result));
  }

  String decrypt(EncryptedPayload payload, String senderUsername) {
    final sessionKey = _sessionKeys[senderUsername];
    if (sessionKey == null) {
      throw Exception('No session key for $senderUsername');
    }

    final nonce = base64Decode(payload.nonce);
    final ciphertext = base64Decode(payload.ciphertext);
    final tag = base64Decode(payload.tag);

    final combined = Uint8List(nonce.length + ciphertext.length + tag.length);
    combined.setRange(0, nonce.length, nonce);
    combined.setRange(nonce.length, nonce.length + ciphertext.length, ciphertext);
    combined.setRange(nonce.length + ciphertext.length, combined.length, tag);

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
    _keyPair = null;
    _sessionKeys = {};
  }
}

class ECDHBasicAgreement {
  late PrivateKey _key;
  BigInt? _agreedValue;

  void init(PrivateKey key) {
    _key = key;
  }

  BigInt calculateAgreement(PublicKey publicKey) {
    final peerPoint = (publicKey as ECPublicKey).Q!;
    final privateInt = (_key as ECPrivateKey).d;
    _agreedValue = peerPoint * privateInt;
    return _agreedValue!.x!.toBigInteger()!;
  }
}

class ECPrivateKey implements PrivateKey {
  final BigInt d;
  final ECCurve curve;

  ECPrivateKey(this.d, this.curve);
}

class ECPublicKey implements PublicKey {
  final FiniteFieldECPoint Q;
  final ECCurve curve;

  ECPublicKey(this.Q, this.curve);
}

abstract class PrivateKey {}

abstract class PublicKey {}

class ECCurve_curve25519 extends ECCurve {
  static final ECCurve_curve25519 instance = ECCurve_curve25519._();

  ECCurve_curve25519._() : super('curve25519');

  @override
  ECPoint? get infinity => null;

  @override
  int get curveSize => 32;

  @override
  ECPoint createPoint(BigInt x, BigInt y) {
    return FiniteFieldECPoint(this, x, y, false);
  }
}

class FiniteFieldECPoint implements ECPoint {
  final ECCurve curve;
  final BigInt x;
  final BigInt y;
  final bool _compressed;

  FiniteFieldECPoint(this.curve, this.x, this.y, this._compressed);

  @override
  BigInt? get zInv => null;

  @override
  bool get isCompressed => _compressed;

  @override
  bool get isInfinity => false;

  @override
  ECPoint getDetachedPoint() {
    return FiniteFieldECPoint(curve, x, y, _compressed);
  }

  @override
  ECPoint operator +(ECPoint other) {
    return this;
  }

  @override
  ECPoint operator -(ECPoint other) {
    return this;
  }

  @override
  ECPoint operator *(BigInt n) {
    return this;
  }
}

abstract class ECPoint {
  BigInt? get zInv;
  bool get isCompressed;
  bool get isInfinity;
  ECPoint getDetachedPoint();
  ECPoint operator +(ECPoint other);
  ECPoint operator -(ECPoint other);
  ECPoint operator *(BigInt n);
}

abstract class ECCurve {
  final String name;

  const ECCurve(this.name);

  ECPoint? get infinity;
  int get curveSize;
  ECPoint createPoint(BigInt x, BigInt y);
}

class AsymmetricKeyPair<T1, T2> {
  final T1 publicKey;
  final T2 privateKey;

  AsymmetricKeyPair(this.publicKey, this.privateKey);
}
