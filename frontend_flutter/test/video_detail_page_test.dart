import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_badminton_mobile/models/venue.dart';
import 'package:good_badminton_mobile/pages/video_detail_page.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoPlayerPlatform originalPlatform;
  late _FakeIosVideoPlayerPlatform fakePlatform;

  setUp(() {
    originalPlatform = VideoPlayerPlatform.instance;
    fakePlatform = _FakeIosVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fakePlatform;
  });

  tearDown(() {
    VideoPlayerPlatform.instance = originalPlatform;
  });

  testWidgets('initialized video renders clip controls and actions',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VideoDetailPage(
          venue: VenueInfo(
            id: 'example',
            name: '示例球场',
            serverUrl: 'https://example.test/venue-demo',
          ),
          video: VenueVideo(
            id: 'court1-full-recording',
            court: '1号场',
            time: '2026-07-22 录像 05',
            duration: '8 秒',
            downloadUrl: 'https://example.test/video.mp4',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('venue-clip-selector')), findsOneWidget);
    expect(find.byType(RangeSlider), findsNothing);
    expect(find.byType(Slider), findsNWidgets(3));
    expect(find.byKey(const Key('venue-clip-start-slider')), findsOneWidget);
    expect(find.byKey(const Key('venue-clip-end-slider')), findsOneWidget);
    expect(find.text('选择要分析的回合'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('venue-clip-start-slider')),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('venue-clip-start-slider')),
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();
    expect(fakePlatform.seekPositions, isNotEmpty);
    expect(fakePlatform.seekPositions.last, greaterThan(Duration.zero));
    final startAfterDrag = tester.widget<Slider>(
      find.byKey(const Key('venue-clip-start-slider')),
    );
    final endBeforeDrag = tester.widget<Slider>(
      find.byKey(const Key('venue-clip-end-slider')),
    );
    expect(startAfterDrag.max, endBeforeDrag.max);
    expect(endBeforeDrag.value - startAfterDrag.value, greaterThanOrEqualTo(5));
    final preservedStart = startAfterDrag.value;

    await tester.drag(
      find.byKey(const Key('venue-clip-end-slider')),
      const Offset(-60, 0),
    );
    await tester.pumpAndSettle();
    final startAfterEndMoved = tester.widget<Slider>(
      find.byKey(const Key('venue-clip-start-slider')),
    );
    final endAfterDrag = tester.widget<Slider>(
      find.byKey(const Key('venue-clip-end-slider')),
    );
    expect(startAfterEndMoved.value, preservedStart);
    expect(startAfterEndMoved.max, endAfterDrag.max);
    expect(
        endAfterDrag.value - startAfterEndMoved.value, greaterThanOrEqualTo(5));
    expect(find.textContaining('片段至少 5 秒'), findsOneWidget);
    expect(find.textContaining('已选择'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('获取视频'), 300);
    expect(find.text('获取视频'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clip controls remain visible while Android video is loading',
      (tester) async {
    VideoPlayerPlatform.instance = _LoadingVideoPlayerPlatform();
    await tester.pumpWidget(
      const MaterialApp(
        home: VideoDetailPage(
          venue: VenueInfo(
            id: 'example',
            name: '示例球场',
            serverUrl: 'https://example.test/venue-demo',
          ),
          video: VenueVideo(
            id: 'court1-full-recording',
            court: '1号场',
            time: '录像',
            duration: '12秒',
            downloadUrl: 'https://example.test/video.mp4',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('venue-clip-selector')), findsOneWidget);
    expect(find.byKey(const Key('venue-clip-start-slider')), findsOneWidget);
    expect(find.byKey(const Key('venue-clip-end-slider')), findsOneWidget);
    expect(find.text('视频加载完成后即可拖动选择'), findsOneWidget);
    expect(find.text('00:12'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
  });
}

class _FakeIosVideoPlayerPlatform extends VideoPlayerPlatform {
  final _events = <int, StreamController<VideoEvent>>{};
  final seekPositions = <Duration>[];
  int _nextId = 1;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _nextId++;
    final events = StreamController<VideoEvent>();
    _events[id] = events;
    scheduleMicrotask(
      () => events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(milliseconds: 8033),
          size: const Size(1280, 720),
        ),
      ),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Widget buildView(int playerId) => const ColoredBox(color: Colors.black);

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seekPositions.add(position);
  }

  @override
  Future<void> dispose(int playerId) async {
    await _events.remove(playerId)?.close();
  }
}

class _LoadingVideoPlayerPlatform extends VideoPlayerPlatform {
  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      const Stream<VideoEvent>.empty();

  @override
  Widget buildView(int playerId) => const ColoredBox(color: Colors.black);

  @override
  Future<void> dispose(int playerId) async {}
}
