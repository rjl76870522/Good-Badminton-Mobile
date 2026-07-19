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
  String? _selectedCourt;
  var _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.showDemoOnOpen) {
      _videos = widget.service.getMockVideos();
      _isLoading = false;
    } else {
      _loadVideos();
    }
  }

  Future<void> _loadVideos() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _selectedCourt = null;
    });
    try {
      final videos = await widget.service.getVideos(widget.venue);
      if (mounted) setState(() => _videos = videos);
    } on VenueVideoException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDemoVideos() {
    setState(() {
      _videos = widget.service.getMockVideos();
      _error = null;
      _selectedCourt = null;
    });
  }

  void _openVideo(VenueVideo video) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoDetailPage(venue: widget.venue, video: video),
      ),
    );
  }

  int _courtOrder(String court) {
    final match = RegExp(r'\d+').firstMatch(court);
    return int.tryParse(match?.group(0) ?? '') ?? 999;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('球馆视频库')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _venueCard(context),
            const SizedBox(height: 16),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _errorCard()
            else
              _videoList(context, _videos ?? const []),
          ],
        ),
      ),
    );
  }

  Widget _venueCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.venue.name,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('球馆编号：${widget.venue.id}'),
            ],
          ),
        ),
      );

  Widget _videoList(BuildContext context, List<VenueVideo> videos) {
    final courts = videos.map((video) => video.court).toSet().toList()
      ..sort((left, right) => _courtOrder(left).compareTo(_courtOrder(right)));
    final filtered = _selectedCourt == null
        ? videos
        : videos.where((video) => video.court == _selectedCourt).toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Row(
              children: [
                Text('选择比赛视频', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('${filtered.length} 条',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text('全部 ${videos.length}'),
                  selected: _selectedCourt == null,
                  onSelected: (_) => setState(() => _selectedCourt = null),
                ),
                for (final court in courts)
                  ChoiceChip(
                    label: Text(court),
                    selected: _selectedCourt == court,
                    onSelected: (_) => setState(() => _selectedCourt = court),
                  ),
              ],
            ),
          ),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 8, 18, 22),
              child: Text('该场地暂时没有可用比赛视频。'),
            )
          else
            for (final video in filtered) ...[
              const Divider(height: 1),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                leading:
                    const CircleAvatar(child: Icon(Icons.play_arrow_rounded)),
                title: Text(video.court),
                subtitle: Text('${video.time} · ${video.duration}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openVideo(video),
              ),
            ],
        ],
      ),
    );
  }

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
}
