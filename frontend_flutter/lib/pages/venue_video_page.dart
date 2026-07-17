import 'package:flutter/material.dart';

import '../models/venue.dart';
import '../services/venue_service.dart';
import 'video_detail_page.dart';

class VenueVideoPage extends StatefulWidget {
  const VenueVideoPage({
    super.key,
    required this.venue,
    this.service = const VenueService(),
    this.showDemoOnOpen = false,
  });

  final VenueInfo venue;
  final VenueService service;
  final bool showDemoOnOpen;

  @override
  State<VenueVideoPage> createState() => _VenueVideoPageState();
}

class _VenueVideoPageState extends State<VenueVideoPage> {
  List<VenueVideo>? _videos;
  String? _error;
  var _isLoading = true;
  var _isDemoData = false;

  @override
  void initState() {
    super.initState();
    if (widget.showDemoOnOpen) {
      _videos = widget.service.getMockVideos();
      _isLoading = false;
      _isDemoData = true;
    } else {
      _loadVideos();
    }
  }

  Future<void> _loadVideos() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _isDemoData = false;
    });
    try {
      final videos = await widget.service.getVideos(widget.venue);
      if (!mounted) return;
      setState(() => _videos = videos);
    } on VenueVideoException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDemoVideos() {
    setState(() {
      _videos = widget.service.getMockVideos();
      _error = null;
      _isDemoData = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('球馆视频库')),
      body: SafeArea(
        top: false,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _venueHeader(context),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _venueHeader(context),
          const SizedBox(height: 16),
          _errorCard()
        ],
      );
    }

    final videos =
        _videos?.isNotEmpty == true ? _videos! : widget.service.getMockVideos();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _venueHeader(context, videos: videos),
          const SizedBox(height: 16),
          if (_isDemoData)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('当前显示演示视频，球馆网络恢复后可重新加载。'),
            ),
          Text('可用比赛视频', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Text('共 ${videos.length} 条',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (videos.isNotEmpty) _videoCard(videos[0]),
          if (videos.length > 1) _videoCard(videos[1]),
          if (videos.length > 2)
            for (final video in videos.skip(2)) _videoCard(video),
        ],
      ),
    );
  }

  void _openVideo(VenueVideo video) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoDetailPage(venue: widget.venue, video: video),
      ),
    );
  }

  Widget _venueHeader(BuildContext context, {List<VenueVideo>? videos}) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.venue.name,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('球馆编号：${widget.venue.id}'),
              if (videos != null && videos.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Divider(),
                const SizedBox(height: 8),
                const Text('已加载比赛视频，可直接预览：'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final video in videos.take(2))
                      FilledButton.icon(
                        onPressed: () => _openVideo(video),
                        icon: const Icon(Icons.play_circle_outline),
                        label: Text('预览 ${video.court}'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );

  Widget _errorCard() => Card(
        color: const Color(0xFFFFF7F5),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_error!, style: const TextStyle(color: Color(0xFFB42318))),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton(
                      onPressed: _loadVideos, child: const Text('重新加载')),
                  FilledButton(
                      onPressed: _showDemoVideos, child: const Text('查看演示视频')),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _videoCard(VenueVideo video) => Container(
        key: ValueKey('venue-video-${video.id}'),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFD5DDD2)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.videocam_outlined),
                const SizedBox(width: 8),
                Text(video.court,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 10),
            Text('时间：${video.time}'),
            Text('时长：${video.duration}'),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
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
            ),
          ],
        ),
      );
}
