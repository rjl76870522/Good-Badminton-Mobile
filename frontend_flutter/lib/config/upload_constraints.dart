class UploadConstraints {
  UploadConstraints._();

  static const int maxFileSizeBytes = 500 * 1024 * 1024;
  static const Duration minDuration = Duration(seconds: 5);
  static const Duration recommendedDuration = Duration(seconds: 30);
  static const Duration maxDuration = Duration(minutes: 3);
  static const Set<String> supportedExtensions = {'mp4', 'mov', 'm4v'};

  static bool isSupportedFileName(String fileName) {
    return supportedExtensions.contains(extensionOf(fileName));
  }

  static String extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  static UploadValidationResult validate({
    required String fileName,
    required int fileSizeBytes,
    required Duration? duration,
  }) {
    final errors = <String>[];
    final extension = extensionOf(fileName);
    if (!supportedExtensions.contains(extension)) {
      errors.add('仅支持 MP4、MOV、M4V 格式');
    }
    if (fileSizeBytes <= 0) {
      errors.add('视频文件为空');
    } else if (fileSizeBytes > maxFileSizeBytes) {
      errors.add('视频不能超过 500 MB');
    }
    if (duration == null || duration <= Duration.zero) {
      errors.add('无法读取视频时长，文件可能已损坏');
    } else {
      if (duration < minDuration) {
        errors.add('视频不能短于 5 秒');
      }
      if (duration > maxDuration) {
        errors.add('视频不能超过 3 分钟');
      }
    }
    final warnings = <String>[];
    if (duration != null &&
        duration >= minDuration &&
        duration < recommendedDuration) {
      warnings.add('建议上传 30 秒以上的视频，以获得更完整的分析结果');
    }
    return UploadValidationResult(errors, warnings: warnings);
  }

  static String formatBytes(int bytes) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  static String formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class UploadValidationResult {
  const UploadValidationResult(this.errors, {this.warnings = const []});

  final List<String> errors;
  final List<String> warnings;

  bool get isValid => errors.isEmpty;
}
