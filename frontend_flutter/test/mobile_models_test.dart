import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:good_badminton_mobile/models/history_item.dart';
import 'package:good_badminton_mobile/models/preview_frame.dart';
import 'package:good_badminton_mobile/models/report.dart';
import 'package:good_badminton_mobile/utils/corner_mapper.dart';

void main() {
  test('preview response parses auto corners and source id', () {
    final preview = PreviewFrame.fromJson({
      'source_upload_id': 'source-1',
      'image_url': '/preview-frames/source-1.jpg',
      'frame_index': 86,
      'time_sec': 2.86,
      'selection_reason': 'auto_court_detected',
      'auto_corners': [
        [100, 200],
        [900, 200],
        [900, 600],
        [100, 600],
      ],
      'quality': {'brightness': 90.04},
      'video': {
        'width': 1000,
        'height': 800,
        'duration_sec': 12.4,
        'fps': 30,
        'total_frames': 372,
      },
    });

    expect(preview.sourceUploadId, 'source-1');
    expect(preview.autoCorners, hasLength(4));
    expect(preview.video.width, 1000);
  });

  test('corner mapping preserves original video pixels', () {
    final point = CornerMapper.displayToVideo(
      displayPoint: const Offset(50, 25),
      displaySize: const Size(100, 50),
      videoSize: const Size(1920, 1080),
    );
    expect(point.x, 960);
    expect(point.y, 540);
  });

  test('coaching is primary and advice remains fallback only', () {
    final report = AnalysisReport.fromJson({
      'schema_version': 'mobile-report-v1',
      'summary': {'total_distance_m': 18.4},
      'advice': ['旧建议'],
      'coaching': {
        'strengths': [
          {
            'title': '启动快',
            'basis': '峰值速度高',
            'detail': '抢点表现好',
            'training_focus': '保持分腿垫步',
          }
        ],
      },
      'files': {'heatmap': '/outputs/heatmap.png'},
      'highlight_segments': [
        {
          'start_sec': 1,
          'end_sec': 9,
          'score': 67,
          'reason': 'fast movement',
          'metrics': {'player_peak_mps': 5.9},
        }
      ],
    });

    expect(report.coaching.strengths.single.title, '启动快');
    expect(report.usesLegacyAdvice, isFalse);
    expect(report.highlightSegments.single.score, 67);
  });

  test('history parses summary, thumbnail and media files', () {
    final item = HistoryItem.fromJson({
      'task_id': 'task-1',
      'user_id': 'guest-1',
      'status': 'completed',
      'video_name': 'match.mp4',
      'summary': {'total_distance_m': 22.59, 'intensity_score': 38},
      'thumbnail': '/outputs/heatmap.png',
      'files': {'analysis_video': '/outputs/detect.mp4'},
    });

    expect(item.summary.totalDistanceM, 22.59);
    expect(item.thumbnail, '/outputs/heatmap.png');
    expect(item.files.analysisVideo, '/outputs/detect.mp4');
  });
}
