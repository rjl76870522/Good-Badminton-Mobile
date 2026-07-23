import 'package:flutter/material.dart';

import '../models/venue.dart';
import '../services/venue_library_storage.dart';
import '../services/venue_service.dart';
import '../viewmodels/venue_library_view_model.dart';
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
  late final VenueLibraryViewModel _viewModel;
  final TextEditingController _searchController = TextEditingController();
  bool _mapMode = true;
  String? _selectedCourt;

  @override
  void initState() {
    super.initState();
    _viewModel = VenueLibraryViewModel(
      venue: widget.venue,
      service: widget.service,
      storage: VenueLibraryStorage(),
    )..addListener(_onModelChanged);
    if (widget.showDemoOnOpen) {
      _viewModel.showDemoVideos();
    } else {
      _viewModel.load();
    }
  }

  @override
  void dispose() {
    _viewModel
      ..removeListener(_onModelChanged)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onModelChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openVideo(VenueVideo video) async {
    await _viewModel.markOpened(video);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoDetailPage(venue: widget.venue, video: video),
      ),
    );
  }

  Future<void> _openCourtSheet(String court) async {
    final videos = _viewModel.videosFor(court);
    if (videos.isEmpty) return;
    setState(() => _selectedCourt = court);
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _CourtVideoSheet(
        court: court,
        videos: videos,
        isFavorite: _viewModel.isFavorite,
        onFavorite: _viewModel.toggleFavorite,
        onOpen: (video) {
          Navigator.of(context).pop();
          _openVideo(video);
        },
      ),
    );
    if (mounted) setState(() => _selectedCourt = null);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF7F9F4),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF7F9F4),
          surfaceTintColor: Colors.transparent,
          title: const Text('球馆视频库'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _ViewSwitch(
                mapMode: _mapMode,
                onChanged: (value) => setState(() => _mapMode = value),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0.85, -0.55),
                        radius: 1.12,
                        colors: [Color(0x1A74B679), Color(0x00F7F9F4)],
                      ),
                    ),
                    child: CustomPaint(painter: _VenueAtmospherePainter()),
                  ),
                ),
              ),
              RefreshIndicator(
                onRefresh: _viewModel.load,
                child: _buildBody(),
              ),
            ],
          ),
        ),
      );

  Widget _buildBody() {
    if (_viewModel.isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: const [_LibrarySkeleton()],
      );
    }
    if (_viewModel.error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _VenueHero(venue: widget.venue, videoCount: 0),
          const SizedBox(height: 16),
          _ErrorState(
            message: _viewModel.error!,
            onRetry: _viewModel.load,
            onDemo: _viewModel.showDemoVideos,
          ),
        ],
      );
    }

    final videos = _viewModel.filteredVideos;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _VenueHero(
            venue: widget.venue, videoCount: _viewModel.allVideos.length),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 7,
              child: TextField(
                key: const Key('venue-search-field'),
                controller: _searchController,
                onChanged: _viewModel.setQuery,
                decoration: InputDecoration(
                  hintText: '搜索场地或时间',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _viewModel.query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchController.clear();
                            _viewModel.setQuery('');
                          },
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Color(0xFFE0E5DD)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Color(0xFFE0E5DD)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: _FavoritePill(
                selected: _viewModel.favoritesOnly,
                onChanged: _viewModel.setFavoritesOnly,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: _mapMode
              ? _FloorplanView(
                  key: const ValueKey('map-mode'),
                  courts: _viewModel.floorplanCourts,
                  countFor: _viewModel.videoCountFor,
                  selectedCourt: _selectedCourt,
                  onTap: _openCourtSheet,
                )
              : _ListModeView(
                  key: const ValueKey('list-mode'),
                  videos: videos,
                  isFavorite: _viewModel.isFavorite,
                  isRecent: _viewModel.isRecent,
                  onFavorite: _viewModel.toggleFavorite,
                  onOpen: _openVideo,
                ),
        ),
      ],
    );
  }
}

class _VenueAtmospherePainter extends CustomPainter {
  const _VenueAtmospherePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0x0A2E7D32)
      ..strokeWidth = 1;
    for (var x = 8.0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 18.0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final courtPaint = Paint()
      ..color = const Color(0x102E7D32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final court = Rect.fromCenter(
      center: Offset(size.width * .91, size.height * .55),
      width: size.width * .7,
      height: size.height * .42,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(court, const Radius.circular(22)),
      courtPaint,
    );
    canvas.drawLine(
      Offset(court.left, court.center.dy),
      Offset(court.right, court.center.dy),
      courtPaint,
    );
    canvas.drawLine(
      Offset(court.left + court.width * .2, court.top),
      Offset(court.left + court.width * .2, court.bottom),
      courtPaint,
    );
    canvas.drawLine(
      Offset(court.right - court.width * .2, court.top),
      Offset(court.right - court.width * .2, court.bottom),
      courtPaint,
    );

    final pathPaint = Paint()
      ..color = const Color(0x182E7D32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final trajectory = Path()
      ..moveTo(-20, size.height * .78)
      ..quadraticBezierTo(
        size.width * .32,
        size.height * .58,
        size.width * .58,
        size.height * .84,
      )
      ..quadraticBezierTo(
        size.width * .77,
        size.height * .98,
        size.width + 24,
        size.height * .74,
      );
    canvas.drawPath(trajectory, pathPaint);
    final dotPaint = Paint()..color = const Color(0x244D9A54);
    for (var index = 0; index < 16; index++) {
      final x = 12.0 + (index * 53.0) % size.width;
      final y = size.height * .16 + ((index * 47.0) % (size.height * .55));
      canvas.drawCircle(Offset(x, y), index.isEven ? 2.2 : 1.4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _VenueAtmospherePainter oldDelegate) => false;
}

class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({required this.mapMode, required this.onChanged});

  final bool mapMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: mapMode ? '切换到列表模式' : '切换到地图模式',
        child: InkWell(
          key: const Key('venue-view-switch'),
          borderRadius: BorderRadius.circular(24),
          onTap: () => onChanged(!mapMode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color:
                  mapMode ? const Color(0x1F2E7D32) : const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFCAE0CB)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(mapMode ? Icons.map_outlined : Icons.view_list_outlined,
                    color: const Color(0xFF2E7D32), size: 18),
                const SizedBox(width: 6),
                Text(mapMode ? '地图模式' : '列表模式',
                    style: const TextStyle(
                      color: Color(0xFF245A28),
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
          ),
        ),
      );
}

class _FavoritePill extends StatelessWidget {
  const _FavoritePill({required this.selected, required this.onChanged});

  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onChanged(!selected),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF2E7D32) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFFE0E5DD),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 18,
                  color: selected ? Colors.white : const Color(0xFF2E7D32),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '收藏',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : const Color(0xFF245A28),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _VenueHero extends StatelessWidget {
  const _VenueHero({required this.venue, required this.videoCount});

  final VenueInfo venue;
  final int videoCount;

  @override
  Widget build(BuildContext context) => Container(
        height: 102,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFF1D5D25), Color(0xFF3F9147)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x332E7D32), blurRadius: 18, offset: Offset(0, 8)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            const Positioned.fill(
              child: CustomPaint(painter: _HeroCourtPatternPainter()),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: const BoxDecoration(
                        color: Color(0x33FFFFFF), shape: BoxShape.circle),
                    child: const Icon(Icons.stadium_outlined,
                        color: Colors.white, size: 23),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(venue.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                )),
                        const SizedBox(height: 3),
                        Text('数字孪生场馆 · $videoCount 段录像',
                            style: const TextStyle(
                              color: Color(0xDFFFFFFF),
                              fontSize: 13,
                            )),
                      ],
                    ),
                  ),
                  const _OnlineBadge(),
                ],
              ),
            ),
          ],
        ),
      );
}

class _HeroCourtPatternPainter extends CustomPainter {
  const _HeroCourtPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x19FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final court = Rect.fromCenter(
      center: Offset(size.width * .8, size.height * .5),
      width: size.width * .72,
      height: size.height * 1.48,
    );
    canvas.drawRect(court, paint);
    canvas.drawLine(Offset(court.left, court.center.dy),
        Offset(court.right, court.center.dy), paint);
    canvas.drawLine(
      Offset(court.left + court.width * .23, court.top),
      Offset(court.left + court.width * .23, court.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(court.right - court.width * .23, court.top),
      Offset(court.right - court.width * .23, court.bottom),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HeroCourtPatternPainter oldDelegate) => false;
}

class _MiniCourtPainter extends CustomPainter {
  const _MiniCourtPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x99FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final bounds = Rect.fromLTWH(6, 6, size.width - 12, size.height - 12);
    canvas.drawRect(bounds, paint);
    final innerLeft = bounds.left + bounds.width * .16;
    final innerRight = bounds.right - bounds.width * .16;
    canvas.drawLine(
        Offset(innerLeft, bounds.top), Offset(innerLeft, bounds.bottom), paint);
    canvas.drawLine(Offset(innerRight, bounds.top),
        Offset(innerRight, bounds.bottom), paint);
    final netY = bounds.center.dy;
    canvas.drawLine(
        Offset(bounds.left, netY), Offset(bounds.right, netY), paint);
    final shortService = bounds.height * .18;
    canvas.drawLine(
      Offset(bounds.left, netY - shortService),
      Offset(bounds.right, netY - shortService),
      paint,
    );
    canvas.drawLine(
      Offset(bounds.left, netY + shortService),
      Offset(bounds.right, netY + shortService),
      paint,
    );
    final longService = bounds.height * .1;
    canvas.drawLine(
      Offset(bounds.left, bounds.top + longService),
      Offset(bounds.right, bounds.top + longService),
      paint,
    );
    canvas.drawLine(
      Offset(bounds.left, bounds.bottom - longService),
      Offset(bounds.right, bounds.bottom - longService),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniCourtPainter oldDelegate) => false;
}

class _OnlineBadge extends StatelessWidget {
  const _OnlineBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0x33FFFFFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: Color(0xFFB9F6CA)),
            SizedBox(width: 4),
            Text('在线', style: TextStyle(fontSize: 12, color: Colors.white)),
          ],
        ),
      );
}

class _FloorplanView extends StatelessWidget {
  const _FloorplanView({
    super.key,
    required this.courts,
    required this.countFor,
    required this.selectedCourt,
    required this.onTap,
  });

  final List<String> courts;
  final int Function(String court) countFor;
  final String? selectedCourt;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('场馆地图', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              const Icon(Icons.touch_app_outlined,
                  size: 18, color: Color(0xFF58705A)),
              const SizedBox(width: 4),
              const Text('点选场地查看录像',
                  style: TextStyle(color: Color(0xFF58705A))),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE0E5DD)),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 16,
                    offset: Offset(0, 7)),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final splitIndex = (courts.length / 2).ceil();
                final leftCourts = courts.take(splitIndex).toList();
                final rightCourts = courts.skip(splitIndex).toList();
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _CourtColumn(
                        courts: leftCourts,
                        countFor: countFor,
                        selectedCourt: selectedCourt,
                        onTap: onTap,
                      ),
                    ),
                    const _AisleDivider(),
                    Expanded(
                      child: _CourtColumn(
                        courts: rightCourts,
                        countFor: countFor,
                        selectedCourt: selectedCourt,
                        onTap: onTap,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      );
}

class _CourtColumn extends StatelessWidget {
  const _CourtColumn({
    required this.courts,
    required this.countFor,
    required this.selectedCourt,
    required this.onTap,
  });

  final List<String> courts;
  final int Function(String court) countFor;
  final String? selectedCourt;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (var index = 0; index < courts.length; index++) ...[
            AspectRatio(
              aspectRatio: 1.4,
              child: _CourtTile(
                court: courts[index],
                videoCount: countFor(courts[index]),
                selected: selectedCourt == courts[index],
                onTap: () => onTap(courts[index]),
              ),
            ),
            if (index != courts.length - 1) const SizedBox(height: 10),
          ],
        ],
      );
}

class _AisleDivider extends StatelessWidget {
  const _AisleDivider();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 34,
        child: Column(
          children: [
            const SizedBox(height: 8),
            const Icon(Icons.arrow_downward_rounded,
                size: 15, color: Color(0xFFB2B9B1)),
            const SizedBox(height: 4),
            RotatedBox(
              quarterTurns: 3,
              child: const Text('走廊 / 过道',
                  style: TextStyle(fontSize: 10, color: Color(0xFFB2B9B1))),
            ),
            const SizedBox(height: 4),
            const Icon(Icons.arrow_upward_rounded,
                size: 15, color: Color(0xFFB2B9B1)),
            Container(
              width: 1,
              height: 280,
              margin: const EdgeInsets.only(top: 7),
              color: const Color(0xFFD7DDD6),
            ),
          ],
        ),
      );
}

class _CourtTile extends StatelessWidget {
  const _CourtTile({
    required this.court,
    required this.videoCount,
    required this.selected,
    required this.onTap,
  });

  final String court;
  final int videoCount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = videoCount > 0;
    return AnimatedScale(
      duration: const Duration(milliseconds: 180),
      scale: selected ? 1.035 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('court-tile-$court'),
          onTap: active ? onTap : null,
          borderRadius: BorderRadius.circular(17),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: active ? null : const Color(0xFFF0F1EF),
              gradient: active
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF246B2B), Color(0xFF4D9A54)],
                    )
                  : null,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: selected
                    ? const Color(0xFF2E7D32)
                    : active
                        ? const Color(0xFFB9E1BD)
                        : const Color(0xFFE0E0E0),
                width: selected ? 2 : 1,
              ),
              boxShadow: active
                  ? const [
                      BoxShadow(
                          color: Color(0x1F2E7D32),
                          blurRadius: 10,
                          offset: Offset(0, 4))
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                const Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _MiniCourtPainter()),
                  ),
                ),
                Positioned(
                  top: 2,
                  left: 1,
                  child: Text(
                    court,
                    style: TextStyle(
                      color: active ? Colors.white : const Color(0xFF838A83),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      shadows: const [
                        Shadow(
                            color: Color(0x55000000),
                            blurRadius: 2,
                            offset: Offset(0, 1)),
                      ],
                    ),
                  ),
                ),
                if (active)
                  const Center(
                    child: Icon(Icons.play_arrow_rounded,
                        size: 34, color: Color(0xBFFFFFFF)),
                  ),
                Visibility(
                  visible: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam_rounded,
                          color: active
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFF9CA39D)),
                      const SizedBox(height: 5),
                      Text(court,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: active
                                ? const Color(0xFF1E4A22)
                                : const Color(0xFF838A83),
                          )),
                      Text(active ? '点击查看录像' : '暂无录像',
                          style: TextStyle(
                            fontSize: 11,
                            color: active
                                ? const Color(0xFF4E7351)
                                : const Color(0xFF969C96),
                          )),
                    ],
                  ),
                ),
                if (active)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: const BoxDecoration(
                          color: Color(0xFF2E7D32), shape: BoxShape.circle),
                      child: Text('$videoCount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ListModeView extends StatelessWidget {
  const _ListModeView({
    super.key,
    required this.videos,
    required this.isFavorite,
    required this.isRecent,
    required this.onFavorite,
    required this.onOpen,
  });

  final List<VenueVideo> videos;
  final bool Function(VenueVideo) isFavorite;
  final bool Function(VenueVideo) isRecent;
  final Future<void> Function(VenueVideo) onFavorite;
  final Future<void> Function(VenueVideo) onOpen;

  @override
  Widget build(BuildContext context) {
    if (videos.isEmpty) return const _EmptyVideoState();
    final grouped = <String, List<VenueVideo>>{};
    for (final video in videos) {
      grouped.putIfAbsent(video.court, () => []).add(video);
    }
    final courts = grouped.keys.toList()
      ..sort((a, b) {
        final left =
            int.tryParse(RegExp(r'\d+').firstMatch(a)?.group(0) ?? '') ?? 999;
        final right =
            int.tryParse(RegExp(r'\d+').firstMatch(b)?.group(0) ?? '') ?? 999;
        return left.compareTo(right);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('全部录像 · ${videos.length} 段',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        for (final court in courts) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Text('$court · ${grouped[court]!.length} 段录像',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: Color(0xFF315835))),
          ),
          ...grouped[court]!.map(
            (video) => _VideoMediaCard(
              video: video,
              favorite: isFavorite(video),
              recent: isRecent(video),
              onFavorite: () => onFavorite(video),
              onTap: () => onOpen(video),
            ),
          ),
        ],
      ],
    );
  }
}

class _CourtVideoSheet extends StatelessWidget {
  const _CourtVideoSheet({
    required this.court,
    required this.videos,
    required this.isFavorite,
    required this.onFavorite,
    required this.onOpen,
  });

  final String court;
  final List<VenueVideo> videos;
  final bool Function(VenueVideo) isFavorite;
  final Future<void> Function(VenueVideo) onFavorite;
  final ValueChanged<VenueVideo> onOpen;

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        initialChildSize: .56,
        minChildSize: .35,
        maxChildSize: .9,
        builder: (context, controller) => Container(
          decoration: const BoxDecoration(
            color: Color(0xF9FFFFFF),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                    color: const Color(0xFFBCC8BC),
                    borderRadius: BorderRadius.circular(4)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('$court 录像列表（共 ${videos.length} 条）',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  itemCount: videos.length,
                  itemBuilder: (context, index) {
                    final video = videos[index];
                    return _VideoMediaCard(
                      video: video,
                      favorite: isFavorite(video),
                      onFavorite: () => onFavorite(video),
                      onTap: () => onOpen(video),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
}

class _VideoMediaCard extends StatelessWidget {
  const _VideoMediaCard({
    required this.video,
    required this.favorite,
    required this.onFavorite,
    required this.onTap,
    this.recent = false,
  });

  final VenueVideo video;
  final bool favorite;
  final bool recent;
  final Future<void> Function() onFavorite;
  final VoidCallback onTap;

  String get _durationBadge {
    final seconds =
        int.tryParse(RegExp(r'\d+').firstMatch(video.duration)?.group(0) ?? '');
    if (seconds == null) return video.duration;
    final minutes = seconds ~/ 60;
    return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE0E5DD)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 5))
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  _VideoPlaceholder(duration: _durationBadge),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(video.court,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16)),
                            ),
                            if (recent)
                              const Text('最近浏览',
                                  style: TextStyle(
                                      fontSize: 11, color: Color(0xFF4D7D50))),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(video.time,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF667066))),
                        const SizedBox(height: 5),
                        const Text('点击查看与截取片段',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF2E7D32))),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: favorite ? '取消收藏' : '收藏视频',
                    onPressed: onFavorite,
                    icon: Icon(
                        favorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: favorite
                            ? Colors.redAccent
                            : const Color(0xFF557657)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder({required this.duration});

  final String duration;

  @override
  Widget build(BuildContext context) => Container(
        width: 118,
        height: 74,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF102E18), Color(0xFF487E4E)]),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Stack(
          children: [
            const Center(
                child: Icon(Icons.play_circle_fill_rounded,
                    color: Colors.white, size: 36)),
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(5)),
                child: Text(duration,
                    style: const TextStyle(fontSize: 10, color: Colors.white)),
              ),
            ),
          ],
        ),
      );
}

class _LibrarySkeleton extends StatelessWidget {
  const _LibrarySkeleton();

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Container(height: 112, decoration: _box()),
          const SizedBox(height: 16),
          Container(height: 56, decoration: _box()),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.45,
            children: List.generate(8, (_) => Container(decoration: _box())),
          ),
        ],
      );

  BoxDecoration _box() => BoxDecoration(
      color: const Color(0xFFE7ECE5), borderRadius: BorderRadius.circular(18));
}

class _ErrorState extends StatelessWidget {
  const _ErrorState(
      {required this.message, required this.onRetry, required this.onDemo});

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          children: [
            const Icon(Icons.wifi_off_outlined,
                size: 38, color: Color(0xFF9E4B47)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新加载')),
                FilledButton(onPressed: onDemo, child: const Text('查看演示视频')),
              ],
            ),
          ],
        ),
      );
}

class _EmptyVideoState extends StatelessWidget {
  const _EmptyVideoState();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            const Icon(Icons.video_library_outlined,
                size: 46, color: Color(0xFF8FA08F)),
            const SizedBox(height: 10),
            Text('没有符合条件的录像', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('可尝试清除搜索或取消“仅看收藏”'),
          ],
        ),
      );
}
