class AnalysisReport {
  const AnalysisReport({
    required this.schemaVersion,
    required this.video,
    required this.summary,
    required this.advice,
    required this.coaching,
    required this.files,
    required this.highlightSegments,
    this.players = const [],
    this.reportSummary = '',
    this.adviceSources = const [],
    this.highlightError,
    this.taskId,
  });

  final String schemaVersion;
  final ReportVideo video;
  final ReportSummary summary;
  final List<String> advice;
  final Coaching coaching;
  final ReportFiles files;
  final List<HighlightSegment> highlightSegments;
  final List<ReportPlayer> players;
  final String reportSummary;
  final List<AdviceSource> adviceSources;
  final String? highlightError;
  final String? taskId;

  bool get usesLegacyAdvice => coaching.isEmpty && advice.isNotEmpty;

  factory AnalysisReport.fromJson(Map<String, dynamic> json) {
    final adviceJson = json['advice'];
    final segments = json['highlight_segments'];
    return AnalysisReport(
      schemaVersion: json['schema_version']?.toString() ?? '',
      video: ReportVideo.fromJson(mapValue(json['video'])),
      summary: ReportSummary.fromJson(mapValue(json['summary'])),
      advice: adviceJson is List
          ? adviceJson.map((item) => item.toString()).toList(growable: false)
          : const [],
      coaching: Coaching.fromJson(mapValue(json['coaching'])),
      files: ReportFiles.fromJson(mapValue(json['files'])),
      highlightSegments: segments is List
          ? segments
              .whereType<Map>()
              .map(
                (item) => HighlightSegment.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList(growable: false)
          : const [],
      players: _parsePlayers(json['players']),
      reportSummary: json['report_summary']?.toString() ?? '',
      adviceSources: _parseAdviceSources(json['advice_sources']),
      highlightError: nullableString(json['highlight_error']),
      taskId: nullableString(json['task_id']),
    );
  }

  static List<ReportPlayer> _parsePlayers(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (item) => ReportPlayer.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
  }

  static List<AdviceSource> _parseAdviceSources(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (item) => AdviceSource.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
  }
}

class ReportPlayer {
  const ReportPlayer({
    required this.name,
    this.totalDistanceM = 0,
    this.maxSpeedMps = 0,
    this.avgSpeedMps = 0,
    this.activeTimeSec = 0,
    this.coverageAreaM2 = 0,
    this.trackingQualityScore = 0,
  });

  final String name;
  final double totalDistanceM;
  final double maxSpeedMps;
  final double avgSpeedMps;
  final double activeTimeSec;
  final double coverageAreaM2;
  final double trackingQualityScore;

  factory ReportPlayer.fromJson(Map<String, dynamic> json) {
    return ReportPlayer(
      name: json['name']?.toString() ?? '球员',
      totalDistanceM: numberValue(json['total_distance_m']),
      maxSpeedMps: numberValue(json['max_speed_mps']),
      avgSpeedMps: numberValue(json['avg_speed_mps']),
      activeTimeSec: numberValue(json['active_time_sec']),
      coverageAreaM2: numberValue(json['coverage_area_m2']),
      trackingQualityScore: numberValue(json['tracking_quality_score']),
    );
  }
}

class ReportVideo {
  const ReportVideo({
    this.name = '',
    this.durationSec = 0,
    this.fps = 0,
    this.width = 0,
    this.height = 0,
  });

  final String name;
  final double durationSec;
  final double fps;
  final int width;
  final int height;

  factory ReportVideo.fromJson(Map<String, dynamic> json) {
    return ReportVideo(
      name: json['name']?.toString() ?? '',
      durationSec: numberValue(json['duration_sec']),
      fps: numberValue(json['fps']),
      width: integerValue(json['width']),
      height: integerValue(json['height']),
    );
  }
}

class ReportSummary {
  const ReportSummary({
    this.totalDistanceM = 0,
    this.maxSpeedMps = 0,
    this.avgSpeedMps = 0,
    this.intensityScore = 0,
    this.detectedFrames = 0,
    this.shuttlecockFrames = 0,
    this.activeTimeSec = 0,
    this.distancePerMin = 0,
    this.coverageAreaM2 = 0,
    this.courtSpanXM = 0,
    this.courtSpanYM = 0,
    this.shuttlecockRatio = 0,
    this.primaryPlayerDistanceM = 0,
    this.rawMaxSpeedMps = 0,
    this.combinedDistancePerMin = 0,
    this.frontCourtRatio = 0,
    this.backCourtRatio = 0,
    this.leftCourtRatio = 0,
    this.rightCourtRatio = 0,
    this.highIntensityMoves = 0,
    this.stablePositionFrames = 0,
    this.droppedJumpCount = 0,
    this.trackingQualityScore = 0,
  });

  final double totalDistanceM;
  final double maxSpeedMps;
  final double avgSpeedMps;
  final int intensityScore;
  final int detectedFrames;
  final int shuttlecockFrames;
  final double activeTimeSec;
  final double distancePerMin;
  final double coverageAreaM2;
  final double courtSpanXM;
  final double courtSpanYM;
  final double shuttlecockRatio;
  final double primaryPlayerDistanceM;
  final double rawMaxSpeedMps;
  final double combinedDistancePerMin;
  final double frontCourtRatio;
  final double backCourtRatio;
  final double leftCourtRatio;
  final double rightCourtRatio;
  final int highIntensityMoves;
  final int stablePositionFrames;
  final int droppedJumpCount;
  final double trackingQualityScore;

  factory ReportSummary.fromJson(Map<String, dynamic> json) {
    return ReportSummary(
      totalDistanceM: numberValue(json['total_distance_m']),
      maxSpeedMps: numberValue(json['max_speed_mps']),
      avgSpeedMps: numberValue(json['avg_speed_mps']),
      intensityScore: integerValue(json['intensity_score']),
      detectedFrames: integerValue(json['detected_frames']),
      shuttlecockFrames: integerValue(json['shuttlecock_frames']),
      activeTimeSec: numberValue(json['active_time_sec']),
      distancePerMin: numberValue(json['distance_per_min']),
      coverageAreaM2: numberValue(json['coverage_area_m2']),
      courtSpanXM: numberValue(json['court_span_x_m']),
      courtSpanYM: numberValue(json['court_span_y_m']),
      shuttlecockRatio: numberValue(json['shuttlecock_ratio']),
      primaryPlayerDistanceM: numberValue(json['primary_player_distance_m']),
      rawMaxSpeedMps: numberValue(json['raw_max_speed_mps']),
      combinedDistancePerMin: numberValue(json['combined_distance_per_min']),
      frontCourtRatio: numberValue(json['front_court_ratio']),
      backCourtRatio: numberValue(json['back_court_ratio']),
      leftCourtRatio: numberValue(json['left_court_ratio']),
      rightCourtRatio: numberValue(json['right_court_ratio']),
      highIntensityMoves: integerValue(json['high_intensity_moves']),
      stablePositionFrames: integerValue(json['stable_position_frames']),
      droppedJumpCount: integerValue(json['dropped_jump_count']),
      trackingQualityScore: numberValue(json['tracking_quality_score']),
    );
  }
}

class Coaching {
  const Coaching({
    this.strengths = const [],
    this.weaknesses = const [],
    this.improvements = const [],
  });

  final List<CoachingItem> strengths;
  final List<CoachingItem> weaknesses;
  final List<CoachingItem> improvements;

  bool get isEmpty =>
      strengths.isEmpty && weaknesses.isEmpty && improvements.isEmpty;

  factory Coaching.fromJson(Map<String, dynamic> json) {
    List<CoachingItem> parse(dynamic value) {
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map(
            (item) => CoachingItem.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(growable: false);
    }

    return Coaching(
      strengths: parse(json['strengths']),
      weaknesses: parse(json['weaknesses']),
      improvements: parse(json['improvements']),
    );
  }
}

class CoachingItem {
  const CoachingItem({
    this.id = '',
    required this.title,
    required this.basis,
    required this.detail,
    required this.trainingFocus,
    this.sourceIds = const [],
  });

  final String id;
  final String title;
  final String basis;
  final String detail;
  final String trainingFocus;
  final List<String> sourceIds;

  factory CoachingItem.fromJson(Map<String, dynamic> json) {
    return CoachingItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      basis: json['basis']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
      trainingFocus: json['training_focus']?.toString() ?? '',
      sourceIds: json['source_ids'] is List
          ? (json['source_ids'] as List)
              .map((item) => item.toString())
              .toList(growable: false)
          : const [],
    );
  }
}

class AdviceSource {
  const AdviceSource({
    required this.id,
    required this.title,
    this.url,
    this.notes = '',
  });

  final String id;
  final String title;
  final String? url;
  final String notes;

  factory AdviceSource.fromJson(Map<String, dynamic> json) {
    return AdviceSource(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      url: nullableString(json['url']),
      notes: json['notes']?.toString() ?? '',
    );
  }
}

class ReportFiles {
  const ReportFiles({
    this.analysisVideo,
    this.heatmap,
    this.trajectory,
    this.highlight,
  });

  final String? analysisVideo;
  final String? heatmap;
  final String? trajectory;
  final String? highlight;

  factory ReportFiles.fromJson(Map<String, dynamic> json) {
    return ReportFiles(
      analysisVideo: nullableString(json['analysis_video']),
      heatmap: nullableString(json['heatmap']),
      trajectory: nullableString(json['trajectory']),
      highlight: nullableString(json['highlight']),
    );
  }
}

class HighlightSegment {
  const HighlightSegment({
    required this.startSec,
    required this.endSec,
    required this.score,
    required this.reason,
    required this.metrics,
    this.reasonZh = '',
    this.tags = const [],
    this.displayMetrics = const {},
  });

  final double startSec;
  final double endSec;
  final int score;
  final String reason;
  final Map<String, double> metrics;
  final String reasonZh;
  final List<String> tags;
  final Map<String, double> displayMetrics;

  factory HighlightSegment.fromJson(Map<String, dynamic> json) {
    final rawMetrics = mapValue(json['metrics']);
    return HighlightSegment(
      startSec: numberValue(json['start_sec']),
      endSec: numberValue(json['end_sec']),
      score: integerValue(json['score']),
      reason: json['reason']?.toString() ?? '',
      metrics: rawMetrics.map(
        (key, value) => MapEntry(key, numberValue(value)),
      ),
      reasonZh: json['reason_zh']?.toString() ?? '',
      tags: json['tags'] is List
          ? (json['tags'] as List)
              .map((item) => item.toString())
              .toList(growable: false)
          : const [],
      displayMetrics: mapValue(json['display_metrics']).map(
        (key, value) => MapEntry(key, numberValue(value)),
      ),
    );
  }
}

Map<String, dynamic> mapValue(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

double numberValue(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int integerValue(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String? nullableString(dynamic value) {
  final text = value?.toString();
  return text == null || text.isEmpty || text == 'null' ? null : text;
}
