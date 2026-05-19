import 'dart:typed_data';
import '../models/file_item.dart';

abstract class FileRepository {
  Future<FileItem> uploadFile({
    required String fileName,
    required Uint8List data,
    required String mimeType,
    String? conversationId,
  });

  Future<Uint8List> downloadFile(String fileId);

  Future<void> deleteFile(String fileId);

  Future<List<FileItem>> getFiles({String? conversationId, int? limit, int? offset});

  Future<FileItem> getFileInfo(String fileId);

  Future<String> getPresignedUrl(String fileId);

  Future<List<FileItem>> searchFiles(String query);
}
