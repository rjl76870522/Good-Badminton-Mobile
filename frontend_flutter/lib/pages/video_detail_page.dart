import 'package:flutter/material.dart';

import '../models/venue.dart';

class VideoDetailPage extends StatelessWidget {
  const VideoDetailPage({super.key, required this.venue, required this.video});

  final VenueInfo venue;
  final VenueVideo video;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('视频详情')),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.sports_tennis_outlined, size: 42),
                      const SizedBox(height: 16),
                      Text('球馆：${venue.name}'),
                      const SizedBox(height: 8),
                      Text('视频：${video.court}'),
                      const SizedBox(height: 8),
                      Text('时间：${video.time}'),
                      const SizedBox(height: 8),
                      Text('时长：${video.duration}'),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('视频下载任务已创建，等待后端接口接入。')),
                  );
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text('下载视频'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
