import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

class EncryptionService {
  static const int keyLength = 32;
  static const int ivLength = 16;
  static const int blockSize = 16;

  final SecureRandom _secureRandom = FortunaRandom();

  EncryptionService() {
    final seed = Uint8List(32);
    final random = Random.secure();
    for (var i = 0; i < 32; i++) {
      seed[i] = random.nextInt(256);
    }
    _secureRandom.seed(KeyParameter(seed));
  }

  Uint8List generateKey() {
    return _secureRandom.nextBytes(keyLength);
  }

  Uint8List generateIV() {
    return _secureRandom.nextBytes(ivLength);
  }

  Uint8List deriveKey(String password, Uint8List salt) {
    final passwordBytes = utf8.encode(password);
    final hash = Hmac(sha256, passwordBytes);
    final digest = hash.convert(salt);
    return Uint8List.fromList(digest.bytes);
  }

  Uint8List encrypt(Uint8List data, Uint8List key) {
    final iv = generateIV();
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(key),
      128,
      iv,
      Uint8List(0),
    );
    cipher.init(true, params);

    final paddedData = _padData(data);
    final encrypted = Uint8List(paddedData.length);
    var len = cipher.processBytes(paddedData, 0, paddedData.length, encrypted, 0);
    cipher.doFinal(encrypted, len);

    final result = Uint8List(iv.length + encrypted.length);
    result.setRange(0, iv.length, iv);
    result.setRange(iv.length, result.length, encrypted);

    return result;
  }

  Uint8List decrypt(Uint8List encryptedData, Uint8List key) {
    final iv = Uint8List.fromList(encryptedData.sublist(0, ivLength));
    final data = Uint8List.fromList(encryptedData.sublist(ivLength));

    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(key),
      128,
      iv,
      Uint8List(0),
    );
    cipher.init(false, params);

    final decrypted = Uint8List(data.length);
    var len = cipher.processBytes(data, 0, data.length, decrypted, 0);
    len += cipher.doFinal(decrypted, len);

    return Uint8List.fromList(decrypted.sublist(0, len));
  }

  Uint8List _padData(Uint8List data) {
    final padLength = blockSize - (data.length % blockSize);
    final padded = Uint8List(data.length + padLength);
    padded.setRange(0, data.length, data);
    for (var i = data.length; i < padded.length; i++) {
      padded[i] = padLength;
    }
    return padded;
  }

  String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  String generateFileHash(Uint8List data) {
    final digest = sha256.convert(data);
    return digest.toString();
  }
}
