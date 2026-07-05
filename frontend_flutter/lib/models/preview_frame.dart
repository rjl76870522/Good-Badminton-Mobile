class CourtPoint {
  const CourtPoint(this.x, this.y);

  final double x;
  final double y;

  List<int> toJson() => [x.round(), y.round()];

  factory CourtPoint.fromJson(dynamic value) {
    if (value is! List || value.length < 2) {
      throw const FormatException('角点格式不正确');
    }
    return CourtPoint(_number(value[0]), _number(value[1]));
  }
}

class PreviewFrame {
  const PreviewFrame({
    required this.sourceUploadId,
    required this.imageUrl,
    required this.frameIndex,
    required this.timeSec,
    required this.selectionReason,
    required this.autoCorners,
    required this.video,
    required this.quality,
    this.score = 0,
    this.sceneOk = true,
    this.sceneWarning,
  });

  final String sourceUploadId;
  final String imageUrl;
  final int frameIndex;
  final double timeSec;
  final String selectionReason;
  final List<CourtPoint> autoCorners;
  final PreviewVideoInfo video;
  final Map<String, double> quality;
  final double score;
  final bool sceneOk;
  final String? sceneWarning;

  factory PreviewFrame.fromJson(Map<String, dynamic> json) {
    final sourceUploadId = json['source_upload_id']?.toString() ?? '';
    final imageUrl = json['image_url']?.toString() ?? '';
    if (sourceUploadId.isEmpty || imageUrl.isEmpty) {
      throw const FormatException('预览接口缺少 source_upload_id 或 image_url');
    }
    final corners = json['auto_corners'];
    final quality = _map(json['quality']);
    return PreviewFrame(
      sourceUploadId: sourceUploadId,
      imageUrl: imageUrl,
      frameIndex: _integer(json['frame_index']),
      timeSec: _number(json['time_sec']),
      selectionReason: json['selection_reason']?.toString() ?? '',
      autoCorners: corners is List
          ? corners.map(CourtPoint.fromJson).toList(growable: false)
          : const [],
      video: PreviewVideoInfo.fromJson(_map(json['video'])),
      quality: quality.map(
        (key, value) => MapEntry(key, _number(value)),
      ),
      score: _number(json['score']),
      sceneOk: json['scene_ok'] is bool ? json['scene_ok'] as bool : true,
      sceneWarning: _nullableString(json['scene_warning']),
    );
  }
}

class PreviewVideoInfo {
  const PreviewVideoInfo({
    required this.width,
    required this.height,
    required this.durationSec,
    required this.fps,
    required this.totalFrames,
  });

  final int width;
  final int height;
  final double durationSec;
  final double fps;
  final int totalFrames;

  factory PreviewVideoInfo.fromJson(Map<String, dynamic> json) {
    return PreviewVideoInfo(
      width: _integer(json['width']),
      height: _integer(json['height']),
      durationSec: _number(json['duration_sec']),
      fps: _number(json['fps']),
      totalFrames: _integer(json['total_frames']),
    );
  }
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _integer(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String? _nullableString(dynamic value) {
  final text = value?.toString();
  return text == null || text.isEmpty || text == 'null' ? null : text;
}
