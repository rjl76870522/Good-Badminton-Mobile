import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum WallpaperTarget {
  global,
  home,
  discover,
  profile,
  upload,
  taskStatus,
  report,
  history,
  venueLibrary,
  videoDetail,
}

extension WallpaperTargetInfo on WallpaperTarget {
  String get storageKey => switch (this) {
        WallpaperTarget.global => 'global',
        WallpaperTarget.home => 'home',
        WallpaperTarget.discover => 'discover',
        WallpaperTarget.profile => 'profile',
        WallpaperTarget.upload => 'upload',
        WallpaperTarget.taskStatus => 'task_status',
        WallpaperTarget.report => 'report',
        WallpaperTarget.history => 'history',
        WallpaperTarget.venueLibrary => 'venue_library',
        WallpaperTarget.videoDetail => 'video_detail',
      };

  String get label => switch (this) {
        WallpaperTarget.global => '全局默认背景',
        WallpaperTarget.home => '首页',
        WallpaperTarget.discover => '发现',
        WallpaperTarget.profile => '我的',
        WallpaperTarget.upload => '上传视频',
        WallpaperTarget.taskStatus => '任务状态',
        WallpaperTarget.report => '报告页',
        WallpaperTarget.history => '历史记录',
        WallpaperTarget.venueLibrary => '球馆视频库',
        WallpaperTarget.videoDetail => '视频详情',
      };

  double get defaultOpacity => switch (this) {
        WallpaperTarget.home => 0.52,
        WallpaperTarget.discover => 0.06,
        WallpaperTarget.profile => 0.12,
        WallpaperTarget.report => 0.11,
        WallpaperTarget.history => 0.55,
        WallpaperTarget.venueLibrary || WallpaperTarget.videoDetail => 0.16,
        WallpaperTarget.global ||
        WallpaperTarget.upload ||
        WallpaperTarget.taskStatus =>
          0.16,
      };

  String get defaultImageAsset => switch (this) {
        WallpaperTarget.discover ||
        WallpaperTarget.profile =>
          'assets/images/history_court_bg.png',
        WallpaperTarget.global ||
        WallpaperTarget.home ||
        WallpaperTarget.upload ||
        WallpaperTarget.taskStatus ||
        WallpaperTarget.report =>
          'assets/images/badminton_dashboard_bg.png',
        WallpaperTarget.history => 'assets/images/history_court_bg.png',
        WallpaperTarget.venueLibrary ||
        WallpaperTarget.videoDetail =>
          'assets/images/badminton_dashboard_bg.png',
      };
}

class WallpaperPresentation {
  const WallpaperPresentation({
    required this.imagePath,
    required this.opacity,
    required this.scale,
  });

  final String? imagePath;
  final double opacity;
  final double scale;
}

/// Stores wallpaper paths locally. Images never leave the device.
class WallpaperStorage {
  static const _prefix = 'custom_wallpaper_';
  static const _opacityPrefix = 'custom_wallpaper_opacity_';
  static const _scalePrefix = 'custom_wallpaper_scale_';
  static final changes = ValueNotifier<int>(0);

  Future<String?> getSpecificPath(WallpaperTarget target) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString('$_prefix${target.storageKey}');
  }

  Future<String?> getEffectivePath(WallpaperTarget target) async {
    final specific = await getSpecificPath(target);
    if (specific != null && specific.isNotEmpty) return specific;
    if (target == WallpaperTarget.global) return null;
    return getSpecificPath(WallpaperTarget.global);
  }

  Future<void> setPath(WallpaperTarget target, String path) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('$_prefix${target.storageKey}', path);
    _notifyChanged();
  }

  Future<void> clear(WallpaperTarget target) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('$_prefix${target.storageKey}');
    _notifyChanged();
  }

  Future<WallpaperPresentation> getPresentation(
    WallpaperTarget target, {
    required double fallbackOpacity,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final globalOpacity = preferences.getDouble(
      '$_opacityPrefix${WallpaperTarget.global.storageKey}',
    );
    final globalScale = preferences.getDouble(
      '$_scalePrefix${WallpaperTarget.global.storageKey}',
    );
    final ownOpacity =
        preferences.getDouble('$_opacityPrefix${target.storageKey}');
    final ownScale = preferences.getDouble('$_scalePrefix${target.storageKey}');
    return WallpaperPresentation(
      imagePath: await getEffectivePath(target),
      opacity: ownOpacity ?? globalOpacity ?? fallbackOpacity,
      scale: ownScale ?? globalScale ?? 1,
    );
  }

  Future<void> setAppearance(
    WallpaperTarget target, {
    required double opacity,
    required double scale,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble('$_opacityPrefix${target.storageKey}', opacity);
    await preferences.setDouble('$_scalePrefix${target.storageKey}', scale);
    _notifyChanged();
  }

  Future<void> clearAppearance(WallpaperTarget target) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('$_opacityPrefix${target.storageKey}');
    await preferences.remove('$_scalePrefix${target.storageKey}');
    _notifyChanged();
  }

  /// Clears every page override in one preferences write cycle.
  Future<List<String>> clearAll() async {
    final preferences = await SharedPreferences.getInstance();
    final paths = <String>[];
    for (final target in WallpaperTarget.values) {
      final path = preferences.getString('$_prefix${target.storageKey}');
      if (path != null && path.isNotEmpty) paths.add(path);
      await preferences.remove('$_prefix${target.storageKey}');
      await preferences.remove('$_opacityPrefix${target.storageKey}');
      await preferences.remove('$_scalePrefix${target.storageKey}');
    }
    _notifyChanged();
    return paths;
  }

  static void _notifyChanged() => changes.value++;
}
