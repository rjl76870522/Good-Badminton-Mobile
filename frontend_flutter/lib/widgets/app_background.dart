import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../services/wallpaper_storage.dart';

/// A translucent, frosted header for the three main tab pages.
class GlassAppBarBackdrop extends StatelessWidget {
  const GlassAppBarBackdrop({super.key});

  @override
  Widget build(BuildContext context) => ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.58),
                  Colors.white.withValues(alpha: 0.42),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFFFFFFFF).withValues(alpha: 0.72),
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF355B3A).withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
          ),
        ),
      );
}

class AppBackground extends StatelessWidget {
  const AppBackground({
    super.key,
    required this.child,
    this.imageAsset = 'assets/images/badminton_dashboard_bg.png',
    this.imageOpacity = 0.16,
    this.alignment = Alignment.topCenter,
    this.wallpaperTarget,
  });

  final Widget child;
  final String imageAsset;
  final double imageOpacity;
  final Alignment alignment;
  final WallpaperTarget? wallpaperTarget;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFF9FCF4),
                  Color(0xFFF0F7EC),
                  Color(0xFFE8F1E4),
                ],
              ),
            ),
          ),
          WallpaperImageLayer(
            imageAsset: imageAsset,
            imageOpacity: imageOpacity,
            alignment: alignment,
            wallpaperTarget: wallpaperTarget,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.75, -0.92),
                radius: 1.25,
                colors: [
                  Color(0x66C8E6C9),
                  Color(0x00C8E6C9),
                ],
              ),
            ),
          ),
          child,
        ],
      );
}

/// Image layer that may be independently overridden by a locally stored photo.
class WallpaperImageLayer extends StatefulWidget {
  const WallpaperImageLayer({
    super.key,
    required this.imageAsset,
    required this.imageOpacity,
    required this.alignment,
    required this.wallpaperTarget,
  });

  final String imageAsset;
  final double imageOpacity;
  final Alignment alignment;
  final WallpaperTarget? wallpaperTarget;

  @override
  State<WallpaperImageLayer> createState() => _WallpaperImageLayerState();
}

class _WallpaperImageLayerState extends State<WallpaperImageLayer> {
  final _wallpaperStorage = WallpaperStorage();
  WallpaperPresentation? _presentation;

  @override
  void initState() {
    super.initState();
    WallpaperStorage.changes.addListener(_loadWallpaper);
    _loadWallpaper();
  }

  @override
  void didUpdateWidget(covariant WallpaperImageLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wallpaperTarget != widget.wallpaperTarget ||
        oldWidget.imageOpacity != widget.imageOpacity) {
      _loadWallpaper();
    }
  }

  @override
  void dispose() {
    WallpaperStorage.changes.removeListener(_loadWallpaper);
    super.dispose();
  }

  Future<void> _loadWallpaper() async {
    final target = widget.wallpaperTarget;
    if (target == null) return;
    final presentation = await _wallpaperStorage.getPresentation(
      target,
      fallbackOpacity: widget.imageOpacity,
    );
    if (!mounted) return;
    setState(() => _presentation = presentation);
  }

  @override
  Widget build(BuildContext context) {
    final customImage = _presentation?.imagePath == null
        ? null
        : File(_presentation!.imagePath!);
    final hasCustomImage = customImage?.existsSync() ?? false;
    final opacity = _presentation?.opacity ?? widget.imageOpacity;
    final scale = _presentation?.scale ?? 1.0;
    return ClipRect(
      child: Transform.scale(
        scale: scale,
        child: hasCustomImage
            ? Image.file(
                customImage!,
                fit: BoxFit.cover,
                alignment: widget.alignment,
                opacity: AlwaysStoppedAnimation(opacity),
              )
            : Image.asset(
                widget.imageAsset,
                fit: BoxFit.cover,
                alignment: widget.alignment,
                opacity: AlwaysStoppedAnimation(opacity),
              ),
      ),
    );
  }
}
