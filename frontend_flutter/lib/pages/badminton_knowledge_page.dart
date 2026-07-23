import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum KnowledgeSection { calendar, rankings, players, equipment }

class BadmintonKnowledgePage extends StatefulWidget {
  const BadmintonKnowledgePage({
    super.key,
    this.initialSection = KnowledgeSection.calendar,
  });

  final KnowledgeSection initialSection;

  @override
  State<BadmintonKnowledgePage> createState() => _BadmintonKnowledgePageState();
}

class _BadmintonKnowledgePageState extends State<BadmintonKnowledgePage> {
  late KnowledgeSection _section = widget.initialSection;

  static const _sections = <KnowledgeSection, ({String title, IconData icon})>{
    KnowledgeSection.calendar: (title: '大赛日历', icon: Icons.calendar_month),
    KnowledgeSection.rankings: (title: '世界排名', icon: Icons.leaderboard),
    KnowledgeSection.players: (title: '球星资料', icon: Icons.people_alt),
    KnowledgeSection.equipment: (title: '装备库', icon: Icons.sports_tennis),
  };

  Uri? get _officialUri => switch (_section) {
        KnowledgeSection.calendar =>
          Uri.parse('https://bwfbadminton.com/calendar/'),
        KnowledgeSection.rankings =>
          Uri.parse('https://bwfbadminton.com/rankings/'),
        KnowledgeSection.players =>
          Uri.parse('https://bwfbadminton.com/players/'),
        KnowledgeSection.equipment => null,
      };

  Future<void> _openOfficialPage() async {
    final uri = _officialUri;
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂时无法打开 BWF 官方页面')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_sections[_section]!.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<KnowledgeSection>(
              segments: _sections.entries
                  .map(
                    (entry) => ButtonSegment<KnowledgeSection>(
                      value: entry.key,
                      icon: Icon(entry.value.icon, size: 18),
                      label: Text(entry.value.title),
                    ),
                  )
                  .toList(),
              selected: {_section},
              showSelectedIcon: false,
              onSelectionChanged: (value) {
                setState(() => _section = value.first);
              },
            ),
          ),
          const SizedBox(height: 18),
          ...switch (_section) {
            KnowledgeSection.calendar => _calendarContent,
            KnowledgeSection.rankings => _rankingContent,
            KnowledgeSection.players => _latestPlayerContent,
            KnowledgeSection.equipment => _equipmentContent,
          },
          if (_officialUri != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _openOfficialPage,
              icon: const Icon(Icons.open_in_new),
              label: Text('前往 BWF 官方${_sections[_section]!.title}'),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> get _calendarContent => const [
        _IntroCard(
          icon: Icons.event_available_outlined,
          title: '观赛日历',
          body: '按赛事级别安排观赛，了解每类比赛的看点',
        ),
        _InfoCard(
          title: '世界巡回赛',
          badge: '全年',
          body: '从超级100到超级1000，不同级别对应不同积分和参赛阵容，年末总决赛汇集赛季表现出色的选手',
        ),
        _InfoCard(
          title: '世界锦标赛',
          badge: '年度重点',
          body: '单项世界冠军争夺，包括男子单打、女子单打、男子双打、女子双打和混合双打',
        ),
        _InfoCard(
          title: '汤姆斯杯与尤伯杯',
          badge: '团体赛',
          body: '分别为男子和女子世界团体锦标赛，适合观察各队的排兵布阵与双打组合',
        ),
        _InfoCard(
          title: '苏迪曼杯',
          badge: '混合团体',
          body: '五个单项共同决定团体胜负，最能体现一支队伍的整体阵容深度',
        ),
      ];

  List<Widget> get _rankingContent => const [
        _IntroCard(
          icon: Icons.workspace_premium_outlined,
          title: '认识世界排名',
          body: '了解五个竞赛项目、积分来源和排名用途',
        ),
        _InfoCard(title: '男子单打', badge: 'MS', body: '重视连续进攻、全场移动和多拍稳定性'),
        _InfoCard(title: '女子单打', badge: 'WS', body: '观察节奏变化、落点控制和攻守转换效率'),
        _InfoCard(title: '男子双打', badge: 'MD', body: '强调前三拍、平抽挡速度和轮转衔接'),
        _InfoCard(title: '女子双打', badge: 'WD', body: '重视防守韧性、连贯压制和搭档覆盖'),
        _InfoCard(title: '混合双打', badge: 'XD', body: '前后场分工与轮转速度是主要观察重点'),
      ];

  // Retained temporarily as legacy lesson copy; the player tab uses the
  // ranking-aware _latestPlayerContent collection below.
  // ignore: unused_element
  List<Widget> get _playerContent => const [
        _IntroCard(
          icon: Icons.person_search_outlined,
          title: '从球星学习',
          body: '从比赛中观察优秀球员的技术特点和回合处理',
        ),
        _InfoCard(
          title: '石宇奇',
          badge: '中国',
          body: '观察重点：主动变速、网前控制，以及由防守快速转入进攻的衔接',
        ),
        _InfoCard(
          title: '安赛龙',
          badge: '丹麦',
          body: '观察重点：高点击球、后场进攻覆盖，以及利用身高和步幅控制回合',
        ),
        _InfoCard(
          title: '安洗莹',
          badge: '韩国',
          body: '观察重点：多拍稳定性、防守覆盖和耐心组织下一次进攻机会',
        ),
        _InfoCard(
          title: '郑思维 / 黄雅琼',
          badge: '混双',
          body: '观察重点：前三拍压迫、连续进攻与前后场快速轮转',
        ),
      ];

  List<Widget> get _latestPlayerContent => const [
        _PlayersHeroCard(),
        _WorldNumberOneCard(
          event: '男单 MS',
          names: '石宇奇',
          country: '中国',
          icon: Icons.sports_tennis_rounded,
          imageAssets: ['assets/images/players/Shi_Yuqi_(CHN)_2018.jpg'],
          backgroundSilhouetteAsset: 'assets/images/silhouette_men_singles.png',
          accent: Color(0xFF1B5E20),
          focus: '主动变速、网前控制，以及由防守快速转入进攻的衔接。',
        ),
        _WorldNumberOneCard(
          event: '男单 MS',
          rankLabel: '世界第 2',
          names: '昆拉武特·维提讪',
          country: '泰国',
          icon: Icons.sports_tennis_rounded,
          imageAssets: [
            'assets/images/players/Kunlavut_Vitidsarn_Indonesia_Masters_2025.jpg',
          ],
          backgroundSilhouetteAsset: 'assets/images/silhouette_men_singles.png',
          accent: Color(0xFF5C7B43),
          focus: '耐心拉吊与多拍控制，观察稳定防守后突然提速的时机选择。',
        ),
        _WorldNumberOneCard(
          event: '女单 WS',
          names: '安洗莹',
          country: '韩国',
          icon: Icons.bolt_rounded,
          imageAssets: ['assets/images/players/An_Se-young.jpg'],
          backgroundSilhouetteAsset:
              'assets/images/silhouette_women_singles.png',
          accent: Color(0xFF2F6F9F),
          focus: '多拍稳定性、全场防守覆盖，以及耐心组织下一次进攻机会。',
        ),
        _WorldNumberOneCard(
          event: '女单 WS',
          rankLabel: '世界第 2',
          names: '王祉怡',
          country: '中国',
          icon: Icons.bolt_rounded,
          imageAssets: ['assets/images/players/Wang_Zhiyi_(cropped).jpeg'],
          backgroundSilhouetteAsset:
              'assets/images/silhouette_women_singles.png',
          accent: Color(0xFF83502F),
          focus: '落点控制与攻守转换，观察主动抢攻和关键分处理的节奏。',
        ),
        _WorldNumberOneCard(
          event: '男双 MD',
          names: '金元昊 / 徐承宰',
          country: '韩国',
          icon: Icons.groups_2_rounded,
          imageAssets: [
            'assets/images/players/Kim_Won-ho.jpg',
            'assets/images/players/Seo_Seung-jae_(KOR)_2024.jpg',
          ],
          backgroundSilhouetteAsset: 'assets/images/silhouette_men_doubles.png',
          accent: Color(0xFF6D4C41),
          focus: '前三区压迫、平抽挡速度与攻守转换中的轮转默契。',
        ),
        _WorldNumberOneCard(
          event: '女双 WD',
          names: '刘圣书 / 谭宁',
          country: '中国',
          icon: Icons.handshake_rounded,
          imageAssets: [
            'assets/images/players/Liu_Shengshu_-_Indonesia_Open_2026_(cropped).jpg',
            'assets/images/players/Tan_Ning_-_Indonesia_Open_2026_(cropped).jpg',
          ],
          backgroundSilhouetteAsset:
              'assets/images/silhouette_women_doubles.png',
          accent: Color(0xFF8E3A64),
          focus: '连续压制、搭档补位，以及防守反击中的落点质量。',
        ),
        _WorldNumberOneCard(
          event: '混双 XD',
          names: '冯彦哲 / 黄东萍',
          country: '中国',
          icon: Icons.hub_rounded,
          imageAssets: [
            'assets/images/players/20260303_104834_Feng_Yanzhe_Yonex_All_England_Open_Badminton_Championships_2026.jpg',
            'assets/images/players/20260303_105533_Huang_Dongping_Yonex_All_England_Open_Badminton_Championships_2026.jpg',
          ],
          backgroundSilhouetteAsset:
              'assets/images/silhouette_mixed_doubles.png',
          accent: Color(0xFF7B6517),
          focus: '前三拍抢攻、前后场分工与连续进攻中的节奏控制。',
        ),
        _PhotoAttributionCard(),
      ];

  List<Widget> get _equipmentContent => const [
        _IntroCard(
          icon: Icons.inventory_2_outlined,
          title: '按需求选择装备',
          body: '结合力量、打法和训练频率选择适合自己的装备',
        ),
        _InfoCard(
          title: '球拍',
          badge: '重量与平衡',
          body: '新手优先考虑容易挥动和容错较高的球拍，进阶后再根据进攻或控制倾向选择平衡点与中杆硬度',
        ),
        _InfoCard(
          title: '球线与磅数',
          badge: '手感与耐用',
          body: '高磅并不等于更强，磅数越高通常甜区越小，应以稳定击中和手臂舒适为前提',
        ),
        _InfoCard(
          title: '羽毛球鞋',
          badge: '保护优先',
          body: '重点查看侧向支撑、防滑、缓震和尺码贴合，不能用普通跑鞋替代频繁急停所需的支撑',
        ),
        _InfoCard(
          title: '用球',
          badge: '速度与耐打',
          body: '球速受温度、海拔和球馆环境影响，训练时应选择适合当地条件的速度型号',
        ),
      ];
}

class _PlayersHeroCard extends StatelessWidget {
  const _PlayersHeroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF195C29), Color(0xFF4F9B55)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332E7D32),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroMedal(),
          SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '世界第一 · 现役标杆',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  '按五个单项观察顶尖球员的节奏、落点与轮转。\nBWF 世界排名 · 2026 年 7 月更新',
                  style: TextStyle(
                    color: Color(0xE8FFFFFF),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMedal extends StatelessWidget {
  const _HeroMedal();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: const Icon(Icons.workspace_premium_rounded,
          color: Colors.white, size: 29),
    );
  }
}

class _WorldNumberOneCard extends StatelessWidget {
  const _WorldNumberOneCard({
    required this.event,
    required this.names,
    required this.country,
    required this.icon,
    required this.imageAssets,
    required this.backgroundSilhouetteAsset,
    required this.accent,
    required this.focus,
    this.rankLabel = '世界第 1',
  });

  final String event;
  final String names;
  final String country;
  final IconData icon;
  final List<String> imageAssets;
  final String backgroundSilhouetteAsset;
  final Color accent;
  final String focus;
  final String rankLabel;

  @override
  Widget build(BuildContext context) {
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
            ? Colors.white
            : const Color(0xFF162118);
    return Card(
      margin: const EdgeInsets.only(bottom: 11),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -10,
            bottom: -18,
            width: 180,
            height: 180,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.055,
                child: Image.asset(
                  backgroundSilhouetteAsset,
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _PlayerPhotos(imageAssets: imageAssets, accent: accent),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Row(
                        children: [
                          Icon(icon, color: accent, size: 16),
                          const SizedBox(width: 5),
                          Text(
                            event,
                            style: TextStyle(
                              color: accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        rankLabel,
                        style: TextStyle(
                          color: onAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        names,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    Text(
                      country,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.065),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '观察重点：$focus',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.48,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerPhotos extends StatelessWidget {
  const _PlayerPhotos({required this.imageAssets, required this.accent});

  final List<String> imageAssets;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: imageAssets.length == 1 ? 64 : 116,
      height: 64,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < imageAssets.length; index++) ...[
            if (index > 0) const SizedBox(width: 6),
            SizedBox(
              width: imageAssets.length == 1 ? 64 : 55,
              height: 64,
              child: _PlayerPhoto(asset: imageAssets[index], accent: accent),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlayerPhoto extends StatelessWidget {
  const _PlayerPhoto({required this.asset, required this.accent});

  final String asset;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          alignment: const Alignment(0, -0.55),
          errorBuilder: (_, __, ___) => ColoredBox(
            color: accent.withValues(alpha: 0.08),
            child: Icon(Icons.person, color: accent),
          ),
        ),
      ),
    );
  }
}

class _PhotoAttributionCard extends StatelessWidget {
  const _PhotoAttributionCard();

  static const _licenseBy = 'CC BY 4.0';
  static const _licenseBySa = 'CC BY-SA 4.0';
  static final _credits = <_PhotoCredit>[
    const _PhotoCredit(
      name: '石宇奇',
      author: 'Fauzi Ananta',
      license: _licenseBy,
      source: 'https://commons.wikimedia.org/wiki/File:Shi_Yuqi_(CHN)_2018.jpg',
      modified: true,
    ),
    const _PhotoCredit(
      name: '昆拉武特·维提讪',
      author: '请以下载图片的 Commons 文件页署名为准',
      license: _licenseBySa,
      source: 'https://commons.wikimedia.org/wiki/Category:Kunlavut_Vitidsarn',
      modified: true,
    ),
    const _PhotoCredit(
      name: '安洗莹',
      author: 'Nardisoero',
      license: _licenseBySa,
      source: 'https://commons.wikimedia.org/wiki/File:An_Se-young.jpg',
      modified: true,
    ),
    const _PhotoCredit(
      name: '王祉怡',
      author: 'BugWarp',
      license: _licenseBySa,
      source:
          'https://commons.wikimedia.org/wiki/File:Wang_Zhiyi_(cropped).jpeg',
      modified: true,
    ),
    const _PhotoCredit(
      name: '金元昊',
      author: 'Tooteroo',
      license: _licenseBySa,
      source: 'https://commons.wikimedia.org/wiki/File:Kim_Won-ho.jpg',
      modified: true,
    ),
    const _PhotoCredit(
      name: '徐承宰',
      author: 'SPOTV Media Pte Ltd',
      license: _licenseBySa,
      source:
          'https://commons.wikimedia.org/wiki/File:Seo_Seung-jae_(KOR)_2024.jpg',
      modified: true,
    ),
    const _PhotoCredit(
      name: '刘圣书',
      author: 'Griff88',
      license: _licenseBySa,
      source:
          'https://commons.wikimedia.org/wiki/File:Liu_Shengshu_-_Indonesia_Open_2026_(cropped).jpg',
      modified: true,
    ),
    const _PhotoCredit(
      name: '谭宁',
      author: 'Griff88',
      license: _licenseBySa,
      source:
          'https://commons.wikimedia.org/wiki/File:Tan_Ning_-_Indonesia_Open_2026_(cropped).jpg',
      modified: true,
    ),
    const _PhotoCredit(
      name: '冯彦哲',
      author: 'Bearas',
      license: _licenseBySa,
      source:
          'https://commons.wikimedia.org/wiki/File:20260303_104834_Feng_Yanzhe_Yonex_All_England_Open_Badminton_Championships_2026.jpg',
      modified: true,
    ),
    const _PhotoCredit(
      name: '黄东萍',
      author: 'Bearas',
      license: _licenseBySa,
      source:
          'https://commons.wikimedia.org/wiki/File:20260303_105533_Huang_Dongping_Yonex_All_England_Open_Badminton_Championships_2026.jpg',
      modified: true,
    ),
  ];

  Uri _licenseUri(String license) => Uri.parse(
        license == _licenseBy
            ? 'https://creativecommons.org/licenses/by/4.0/'
            : 'https://creativecommons.org/licenses/by-sa/4.0/',
      );

  Future<void> _open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 4, bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.copyright_outlined),
        title: const Text('球星图片署名与许可',
            style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: const Text('查看原图、作者、许可证与修改说明'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              '图片仅用于客观球星资料介绍，不表示运动员认可或代言本应用。'
              '应用内以圆角封面方式展示图片，已作展示裁剪；使用 CC BY-SA 图片的改编展示遵守相同方式共享要求。',
              style: TextStyle(height: 1.45),
            ),
          ),
          for (final credit in _credits)
            ListTile(
              dense: true,
              title: Text('${credit.name} · 摄影师：${credit.author}'),
              subtitle: Text(
                '${credit.license} · '
                '${credit.modified ? '已裁剪/已修改（应用内圆角展示）' : '未修改'}',
              ),
              trailing: Wrap(
                spacing: 0,
                children: [
                  IconButton(
                    tooltip: '打开 Wikimedia Commons 原图页',
                    onPressed: () => _open(Uri.parse(credit.source)),
                    icon: const Icon(Icons.open_in_new_rounded),
                  ),
                  IconButton(
                    tooltip: '打开许可证',
                    onPressed: () => _open(_licenseUri(credit.license)),
                    icon: const Icon(Icons.description_outlined),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoCredit {
  const _PhotoCredit({
    required this.name,
    required this.author,
    required this.license,
    required this.source,
    required this.modified,
  });

  final String name;
  final String author;
  final String license;
  final String source;
  final bool modified;
}

class _IntroCard extends StatelessWidget {
  const _IntroCard(
      {required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(body,
                    style:
                        const TextStyle(color: Color(0xEFFFFFFF), height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard(
      {required this.title, required this.badge, required this.body});

  final String title;
  final String badge;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800))),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(badge, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: const TextStyle(height: 1.5)),
          ],
        ),
      ),
    );
  }
}
