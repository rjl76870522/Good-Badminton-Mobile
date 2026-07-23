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
            KnowledgeSection.players => _playerContent,
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

  List<Widget> get _playerContent => [
        const _IntroCard(
          icon: Icons.person_search_outlined,
          title: '现役球员观察',
          body: '从不同风格的现役球员身上观察移动、节奏与回合处理',
        ),
        ..._activePlayers.map(_PlayerProfileCard.new),
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

const _activePlayers = <_PlayerProfile>[
  _PlayerProfile(
    name: '石宇奇',
    englishName: 'SHI Yu Qi',
    country: '中国',
    event: '男子单打',
    imageAsset: 'assets/images/players/shi_yuqi.jpg',
    focus: '主动变速与网前控制，观察他如何通过节奏变化创造后场进攻机会',
  ),
  _PlayerProfile(
    name: '安赛龙',
    englishName: 'Viktor AXELSEN',
    country: '丹麦',
    event: '男子单打',
    imageAsset: 'assets/images/players/viktor_axelsen.jpg',
    focus: '高点击球与大范围覆盖，观察身高、步幅和连续进攻如何形成压迫',
  ),
  _PlayerProfile(
    name: '昆拉武特',
    englishName: 'Kunlavut VITIDSARN',
    country: '泰国',
    event: '男子单打',
    imageAsset: 'assets/images/players/kunlavut_vitidsarn.jpg',
    focus: '耐心拉吊与多拍控制，观察稳定防守后突然提速的时机选择',
  ),
  _PlayerProfile(
    name: '安洗莹',
    englishName: 'AN Se Young',
    country: '韩国',
    event: '女子单打',
    imageAsset: 'assets/images/players/an_seyoung.jpg',
    focus: '全场防守覆盖与多拍稳定性，观察她如何消耗对手并重新组织进攻',
  ),
  _PlayerProfile(
    name: '陈雨菲',
    englishName: 'CHEN Yu Fei',
    country: '中国',
    event: '女子单打',
    imageAsset: 'assets/images/players/chen_yufei.jpg',
    focus: '均衡的攻守转换与落点控制，观察回中、连贯和关键分处理',
  ),
  _PlayerProfile(
    name: '山口茜',
    englishName: 'Akane YAMAGUCHI',
    country: '日本',
    event: '女子单打',
    imageAsset: 'assets/images/players/akane_yamaguchi.jpg',
    focus: '快速启动与低重心移动，观察连续突击和被动状态下的回球质量',
  ),
];

class _PlayerProfile {
  const _PlayerProfile({
    required this.name,
    required this.englishName,
    required this.country,
    required this.event,
    required this.imageAsset,
    required this.focus,
  });

  final String name;
  final String englishName;
  final String country;
  final String event;
  final String imageAsset;
  final String focus;
}

class _PlayerProfileCard extends StatelessWidget {
  const _PlayerProfileCard(this.player);

  final _PlayerProfile player;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  player.imageAsset,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, __, ___) => ColoredBox(
                    color: colors.primaryContainer,
                    child: Icon(
                      Icons.person,
                      size: 64,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xB0000000)],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 13,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              player.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              player.englishName,
                              style: const TextStyle(
                                color: Color(0xE6FFFFFF),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _PlayerTag(text: player.country),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.sports_tennis, size: 17, color: colors.primary),
                    const SizedBox(width: 7),
                    Text(
                      '${player.event} · 现役',
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  player.focus,
                  style: const TextStyle(height: 1.55),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerTag extends StatelessWidget {
  const _PlayerTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xDFFFFFFF),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF162118),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
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
