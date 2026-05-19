class FileItem {
  final String id;
  final String name;
  final String mimeType;
  final int size;
  final String? thumbnailUrl;
  final String downloadUrl;
  final String uploaderId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isEncrypted;
  final String? encryptionHash;

  const FileItem({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    this.thumbnailUrl,
    required this.downloadUrl,
    required this.uploaderId,
    required this.createdAt,
    this.updatedAt,
    this.isEncrypted = true,
    this.encryptionHash,
  });

  factory FileItem.fromJson(Map<String, dynamic> json) {
    return FileItem(
      id: json['id'] as String,
      name: json['name'] as String,
      mimeType: json['mime_type'] as String,
      size: json['size'] as int,
      thumbnailUrl: json['thumbnail_url'] as String?,
      downloadUrl: json['download_url'] as String,
      uploaderId: json['uploader_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      isEncrypted: json['is_encrypted'] as bool? ?? true,
      encryptionHash: json['encryption_hash'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'mime_type': mimeType,
      'size': size,
      'thumbnail_url': thumbnailUrl,
      'download_url': downloadUrl,
      'uploader_id': uploaderId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'is_encrypted': isEncrypted,
      'encryption_hash': encryptionHash,
    };
  }

  String get formattedSize {
    if (size < 1024) {
      return '$size B';
    } else if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    } else if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  bool get isImage {
    return mimeType.startsWith('image/');
  }

  bool get isVideo {
    return mimeType.startsWith('video/');
  }

  bool get isAudio {
    return mimeType.startsWith('audio/');
  }
}
