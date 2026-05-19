import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import '../config/app_config.dart';
import 'e2e_helper_simple.dart';

class UploadProgress {
  final String uploadId;
  final int totalChunks;
  final int uploadedChunks;
  final double progress;
  final bool isComplete;
  final String? error;

  UploadProgress({
    required this.uploadId,
    required this.totalChunks,
    required this.uploadedChunks,
    required this.progress,
    required this.isComplete,
    this.error,
  });
}

class FileUploadService {
  static const int chunkSize = 16 * 1024 * 1024;

  final AppConfig _config;
  final E2EHelper _e2eHelper;

  FileUploadService(this._config, this._e2eHelper);

  String get _baseUrl => _config.apiBaseUrl;

  Future<UploadProgress> uploadFile({
    required String filePath,
    required String fileName,
    required int fileSize,
    required String mimeType,
    required String recipientUsername,
    Function(UploadProgress)? onProgress,
  }) async {
    if (!_e2eHelper.hasSessionKey(recipientUsername)) {
      throw Exception('No encryption session with $recipientUsername');
    }

    final sessionKey = _e2eHelper.getSessionKey(recipientUsername);
    if (sessionKey == null) {
      throw Exception('No session key available');
    }

    final chunkCount = _calculateChunkCount(fileSize);
    final initResponse = await _initUpload(
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      chunkCount: chunkCount,
    );

    final uploadId = initResponse['upload_id'] as String;

    final file = File(filePath);
    final randomAccessFile = await file.open();

    try {
      int uploadedChunks = 0;

      for (int i = 0; i < chunkCount; i++) {
        final start = i * chunkSize;
        final end = (start + chunkSize > fileSize) ? fileSize : start + chunkSize;

        await randomAccessFile.setPosition(start);
        final chunkData = await randomAccessFile.read(end - start);

        final encryptedChunk = _encryptChunk(Uint8List.fromList(chunkData), sessionKey);

        await _uploadChunk(
          uploadId: uploadId,
          chunkIndex: i,
          data: encryptedChunk,
        );

        uploadedChunks++;

        onProgress?.call(UploadProgress(
          uploadId: uploadId,
          totalChunks: chunkCount,
          uploadedChunks: uploadedChunks,
          progress: uploadedChunks / chunkCount,
          isComplete: uploadedChunks == chunkCount,
        ));
      }

      await _completeUpload(
        uploadId: uploadId,
        filename: fileName,
        fileSize: fileSize,
        mimeType: mimeType,
        chunkCount: chunkCount,
        recipientUsername: recipientUsername,
      );

      return UploadProgress(
        uploadId: uploadId,
        totalChunks: chunkCount,
        uploadedChunks: chunkCount,
        progress: 1.0,
        isComplete: true,
      );
    } catch (e) {
      return UploadProgress(
        uploadId: uploadId,
        totalChunks: chunkCount,
        uploadedChunks: 0,
        progress: 0,
        isComplete: false,
        error: e.toString(),
      );
    } finally {
      await randomAccessFile.close();
    }
  }

  Future<Map<String, dynamic>> _initUpload({
    required String fileName,
    required int fileSize,
    required String mimeType,
    required int chunkCount,
  }) async {
    final token = await _getToken();

    final response = await http.post(
      Uri.parse('$_baseUrl/file/init-upload'),
      headers: _headers(token),
      body: jsonEncode({
        'filename': fileName,
        'file_size': fileSize,
        'mime_type': mimeType,
        'chunk_count': chunkCount,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to init upload: ${response.body}');
    }
  }

  Future<void> _uploadChunk({
    required String uploadId,
    required int chunkIndex,
    required Uint8List data,
  }) async {
    final token = await _getToken();

    final response = await http.post(
      Uri.parse('$_baseUrl/file/upload-chunk/$uploadId/$chunkIndex'),
      headers: {
        ..._headers(token),
        'Content-Type': 'application/octet-stream',
      },
      body: data,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to upload chunk $chunkIndex: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> _completeUpload({
    required String uploadId,
    required String filename,
    required int fileSize,
    required String mimeType,
    required int chunkCount,
    required String recipientUsername,
  }) async {
    final token = await _getToken();

    final response = await http.post(
      Uri.parse('$_baseUrl/file/complete-upload/$uploadId?to=$recipientUsername'),
      headers: _headers(token),
      body: jsonEncode({
        'filename': filename,
        'file_size': fileSize,
        'mime_type': mimeType,
        'chunk_count': chunkCount,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to complete upload: ${response.body}');
    }
  }

  Uint8List _encryptChunk(Uint8List data, Uint8List sessionKey) {
    final nonce = _generateNonce();

    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(sessionKey),
      128,
      nonce,
      Uint8List(0),
    );
    cipher.init(true, params);

    final paddedData = _padData(data);
    final ciphertext = Uint8List(paddedData.length + 16);
    var len = cipher.processBytes(paddedData, 0, paddedData.length, ciphertext, 0);
    len += cipher.doFinal(ciphertext, len);

    final result = Uint8List(nonce.length + len);
    result.setRange(0, nonce.length, nonce);
    result.setRange(nonce.length, result.length, ciphertext.sublist(0, len));

    return result;
  }

  Uint8List _generateNonce() {
    final random = Random.secure();
    final nonce = Uint8List(12);
    for (var i = 0; i < 12; i++) {
      nonce[i] = random.nextInt(256);
    }
    return nonce;
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

  int _calculateChunkCount(int fileSize) {
    return (fileSize / chunkSize).ceil();
  }

  Map<String, String> _headers(String? token) {
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<String?> _getToken() async {
    return null;
  }
}
