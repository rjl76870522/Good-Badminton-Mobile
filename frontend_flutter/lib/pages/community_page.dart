import 'package:flutter/material.dart';

import '../services/wallpaper_storage.dart';
import '../widgets/app_background.dart';
import 'navigation_page.dart';

class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('社区'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: const GlassAppBarBackdrop(),
      ),
      body: AppBackground(
        wallpaperTarget: WallpaperTarget.community,
        imageAsset: 'assets/images/history_court_bg.png',
        imageOpacity: 0.06,
        alignment: const Alignment(0.15, -0.2),
        child: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            key: const ValueKey('community-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: const [KnowledgeModules()],
          ),
        ),
      ),
    );
  }
}
