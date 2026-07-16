import 'package:flutter/material.dart';

import '../models/venue.dart';
import '../services/venue_service.dart';
import 'video_detail_page.dart';

class VenueVideoPage extends StatefulWidget {
  const VenueVideoPage(
      {super.key, required this.venue, this.service = const VenueService()});

  final VenueInfo venue;
  final VenueService service;

  @override
  State<VenueVideoPage> createState() => _VenueVideoPageState();
}

class _VenueVideoPageState extends State<VenueVideoPage> {
  late final Future<List<VenueVideo>> _videos =
      widget.service.getVideos(widget.venue.id);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('球馆视频库')),
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<VenueVideo>>(
          future: _videos,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final videos = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.venue.name,
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text('球馆编号：${widget.venue.id}'),
                        const SizedBox(height: 4),
                        const Text('当前为演示视频库，后续将接入球馆服务器。'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('可用比赛视频', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                ...videos.map(
                  (video) => Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const CircleAvatar(
                              child: Icon(Icons.videocam_outlined)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(video.court,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Text(video.time),
                                Text('时长：${video.duration}'),
                              ],
                            ),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => VideoDetailPage(
                                  venue: widget.venue,
                                  video: video,
                                ),
                              ),
                            ),
                            child: const Text('选择'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
