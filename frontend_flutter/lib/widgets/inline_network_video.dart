import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class InlineNetworkVideo extends StatefulWidget {
  const InlineNetworkVideo({
    super.key,
    required this.title,
    required this.url,
  });

  final String title;
  final String url;

  @override
  State<InlineNetworkVideo> createState() => _InlineNetworkVideoState();
}

class _InlineNetworkVideoState extends State<InlineNetworkVideo> {
  VideoPlayerController? _controller;
  Future<void>? _initializing;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(covariant InlineNetworkVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _createController();
    }
  }

  void _createController() {
    final previous = _controller;
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    _initializing = controller.initialize().then((_) {
      controller.setLooping(false);
    });
    previous?.dispose();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _duration(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.ondemand_video_outlined),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
          ),
          if (controller != null)
            FutureBuilder<void>(
              future: _initializing,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _VideoError(
                    message: '视频加载失败：${snapshot.error}',
                    onRetry: _createController,
                  );
                }
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 210,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    final aspectRatio =
                        value.aspectRatio > 0 ? value.aspectRatio : 16 / 9;
                    return Column(
                      children: [
                        AspectRatio(
                          aspectRatio: aspectRatio,
                          child: ColoredBox(
                            color: Colors.black,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                VideoPlayer(controller),
                                if (value.isBuffering)
                                  const CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                Material(
                                  color: Colors.black38,
                                  shape: const CircleBorder(),
                                  child: IconButton(
                                    iconSize: 36,
                                    color: Colors.white,
                                    tooltip: value.isPlaying ? '暂停' : '播放',
                                    onPressed: () {
                                      value.isPlaying
                                          ? controller.pause()
                                          : controller.play();
                                    },
                                    icon: Icon(
                                      value.isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          padding: EdgeInsets.zero,
                          colors: VideoProgressColors(
                            playedColor: Theme.of(context).colorScheme.primary,
                            bufferedColor: Colors.green.shade100,
                            backgroundColor: Colors.black12,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: value.volume == 0 ? '打开声音' : '静音',
                                onPressed: () => controller
                                    .setVolume(value.volume == 0 ? 1 : 0),
                                icon: Icon(
                                  value.volume == 0
                                      ? Icons.volume_off_outlined
                                      : Icons.volume_up_outlined,
                                ),
                              ),
                              Text(
                                '${_duration(value.position)} / '
                                '${_duration(value.duration)}',
                              ),
                              const Spacer(),
                              if (value.hasError)
                                Flexible(
                                  child: Text(
                                    value.errorDescription ?? '播放失败',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: SelectableText(
              widget.url,
              maxLines: 2,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoError extends StatelessWidget {
  const _VideoError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_outlined, size: 34),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: onRetry, child: const Text('重试播放')),
            ],
          ),
        ),
      ),
    );
  }
}
