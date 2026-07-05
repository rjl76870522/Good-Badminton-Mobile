import 'dart:ui';

import '../models/preview_frame.dart';

class CornerMapper {
  CornerMapper._();

  static CourtPoint displayToVideo({
    required Offset displayPoint,
    required Size displaySize,
    required Size videoSize,
  }) {
    if (displaySize.width <= 0 ||
        displaySize.height <= 0 ||
        videoSize.width <= 0 ||
        videoSize.height <= 0) {
      return const CourtPoint(0, 0);
    }
    return CourtPoint(
      (displayPoint.dx / displaySize.width * videoSize.width)
          .clamp(0, videoSize.width),
      (displayPoint.dy / displaySize.height * videoSize.height)
          .clamp(0, videoSize.height),
    );
  }

  static Offset videoToDisplay({
    required CourtPoint videoPoint,
    required Size videoSize,
    required Size displaySize,
  }) {
    if (videoSize.width <= 0 || videoSize.height <= 0) return Offset.zero;
    return Offset(
      videoPoint.x / videoSize.width * displaySize.width,
      videoPoint.y / videoSize.height * displaySize.height,
    );
  }
}
