import 'dart:typed_data';
import '../../../core/config/app_config.dart';
import '../../../core/services/encryption_service.dart';
import '../domain/models/file_item.dart';
import '../domain/repositories/file_repository.dart';

class FileRepositoryImpl implements FileRepository {
  final AppConfig _config;
  final EncryptionService _encryptionService;

  FileRepositoryImpl(this._config, this._encryptionService);

  @override
  Future<FileItem> uploadFile({
    required String fileName,
    required Uint8List data,
    required String mimeType,
    String? conversationId,
  }) async {
    final fileHash = _encryptionService.generateFileHash(data);

    Uint8List encryptedData = data;
    if (_config.enableEncryption) {
      encryptedData = _encryptionService.encrypt(data, _encryptionService.generateKey());
    }

    return FileItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: fileName,
      mimeType: mimeType,
      size: encryptedData.length,
      downloadUrl: '',
      uploaderId: 'current_user',
      createdAt: DateTime.now(),
      isEncrypted: _config.enableEncryption,
      encryptionHash: fileHash,
    );
  }

  @override
  Future<Uint8List> downloadFile(String fileId) async {
    return Uint8List(0);
  }

  @override
  Future<void> deleteFile(String fileId) async {}

  @override
  Future<List<FileItem>> getFiles({
    String? conversationId,
    int? limit,
    int? offset,
  }) async {
    return [];
  }

  @override
  Future<FileItem> getFileInfo(String fileId) async {
    throw UnimplementedError();
  }

  @override
  Future<String> getPresignedUrl(String fileId) async {
    return '';
  }

  @override
  Future<List<FileItem>> searchFiles(String query) async {
    return [];
  }
}
