import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:good_badminton_mobile/models/preview_frame.dart';
import 'package:good_badminton_mobile/pages/corner_picker_page.dart';

void main() {
  testWidgets('corner picker prefills automatic corners and can reset them',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const preview = PreviewFrame(
      sourceUploadId: 'source-1',
      imageUrl: '/preview.jpg',
      frameIndex: 1,
      timeSec: 0.1,
      selectionReason: 'auto_court_detected',
      autoCorners: [
        CourtPoint(10, 10),
        CourtPoint(90, 10),
        CourtPoint(90, 90),
        CourtPoint(10, 90),
      ],
      video: PreviewVideoInfo(
        width: 100,
        height: 100,
        durationSec: 30,
        fps: 30,
        totalFrames: 900,
      ),
      quality: {},
    );

    await tester.pumpWidget(
      const MaterialApp(home: CornerPickerPage(preview: preview)),
    );
    await tester.pump();

    expect(find.text('四个角点已设置'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('重新选择'), 200);
    await tester.tap(find.text('重新选择'));
    await tester.pump();

    expect(find.text('请点击：左上角'), findsOneWidget);
  });
}
