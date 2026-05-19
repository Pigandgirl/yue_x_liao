import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';
import 'e2e_helper_simple.dart';

class DownloadProgress {
  final int totalChunks;
  final int downloadedChunks;
  final double progress;
  final bool isComplete;
  final String? error;
  final String? filePath;

  DownloadProgress({
    required this.totalChunks,
    required this.downloadedChunks,
    required this.progress,
    required this.isComplete,
    this.error,
    this.filePath,
  });
}

class FileDownloadService {
  final AppConfig _config;
  final E2EHelper _e2eHelper;

  FileDownloadService(this._config, this._e2eHelper);

  String get _baseUrl => _config.apiBaseUrl;

  Future<DownloadProgress> downloadFile({
    required String uploadId,
    required int chunkCount,
    required String senderUsername,
    required String filename,
    Function(DownloadProgress)? onProgress,
  }) async {
    final sessionKey = _e2eHelper.getSessionKey(senderUsername);
    if (sessionKey == null) {
      return DownloadProgress(
        totalChunks: chunkCount,
        downloadedChunks: 0,
        progress: 0,
        isComplete: false,
        error: 'No session key for $senderUsername',
      );
    }

    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/$uploadId');
    final output = IOSink(tempFile.openWrite());

    try {
      for (int i = 0; i < chunkCount; i++) {
        final chunkData = await _downloadChunk(
          uploadId: uploadId,
          chunkIndex: i,
          senderUsername: senderUsername,
          sessionKey: sessionKey,
        );

        output.add(chunkData);

        onProgress?.call(DownloadProgress(
          totalChunks: chunkCount,
          downloadedChunks: i + 1,
          progress: (i + 1) / chunkCount,
          isComplete: i + 1 == chunkCount,
        ));
      }

      await output.close();

      final appDir = await getApplicationDocumentsDirectory();
      final filePath = '${appDir.path}/files/$uploadId';
      final fileDir = Directory('${appDir.path}/files');
      if (!await fileDir.exists()) {
        await fileDir.create(recursive: true);
      }

      final savedFile = File(filePath);
      await tempFile.copy(savedFile.path);
      await tempFile.delete();

      return DownloadProgress(
        totalChunks: chunkCount,
        downloadedChunks: chunkCount,
        progress: 1.0,
        isComplete: true,
        filePath: savedFile.path,
      );
    } catch (e) {
      await output.close();
      await tempFile.delete();

      return DownloadProgress(
        totalChunks: chunkCount,
        downloadedChunks: 0,
        progress: 0,
        isComplete: false,
        error: e.toString(),
      );
    }
  }

  Future<Uint8List> _downloadChunk({
    required String uploadId,
    required int chunkIndex,
    required String senderUsername,
    required Uint8List sessionKey,
  }) async {
    final senderID = await _getUserId(senderUsername);

    final response = await http.get(
      Uri.parse('$_baseUrl/file/download/$senderID/$uploadId/$chunkIndex'),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to download chunk $chunkIndex: ${response.bodyBytes}');
    }

    return _decryptChunk(Uint8List.fromList(response.bodyBytes), sessionKey);
  }

  Uint8List _decryptChunk(Uint8List encryptedData, Uint8List sessionKey) {
    if (encryptedData.length < 12) {
      return encryptedData;
    }

    final nonce = Uint8List.fromList(encryptedData.sublist(0, 12));
    final ciphertext = Uint8List.fromList(encryptedData.sublist(12));

    try {
      final cipher = GCMBlockCipher(AESEngine());
      final params = AEADParameters(
        KeyParameter(sessionKey),
        128,
        nonce,
        Uint8List(0),
      );
      cipher.init(false, params);

      final decrypted = Uint8List(ciphertext.length);
      var len = cipher.processBytes(ciphertext, 0, ciphertext.length, decrypted, 0);
      len += cipher.doFinal(decrypted, len);

      return Uint8List.fromList(decrypted.sublist(0, len));
    } catch (e) {
      return ciphertext;
    }
  }

  Future<String> _getUserId(String username) async {
    return username.hashCode.toString();
  }

  Future<bool> isFileDownloaded(String uploadId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/files/$uploadId');
    return file.exists();
  }

  Future<File?> getDownloadedFile(String uploadId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/files/$uploadId');
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  Future<void> deleteFile(String uploadId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/files/$uploadId');
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class GCMBlockCipher {
  final AESEngine _engine;
  bool _forEncryption = false;
  int _macSize = 0;
  Uint8List _nonce = Uint8List(0);
  Uint8List _forMac = Uint8List(0);

  GCMBlockCipher(this._engine);

  void init(bool forEncryption, AEADParameters params) {
    _forEncryption = forEncryption;
    _macSize = params.macSize ~/ 8;
    _nonce = params.nonce;
    _forMac = Uint8List.fromList(params.mac);
  }

  int processBytes(
    Uint8List inp,
    int inpOff,
    int len,
    Uint8List out,
    int outOff,
  ) {
    for (var i = 0; i < len && (inpOff + i) < inp.length; i++) {
      if (outOff + i < out.length) {
        out[outOff + i] = inp[inpOff + i];
      }
    }
    return len;
  }

  int doFinal(Uint8List out, int outOff) {
    return 0;
  }
}

class AEADParameters {
  final KeyParameter keyParameter;
  final int macSize;
  final Uint8List nonce;
  final Uint8List mac;

  AEADParameters(this.keyParameter, this.macSize, this.nonce, this.mac);
}

class KeyParameter {
  final Uint8List key;

  KeyParameter(this.key);
}
