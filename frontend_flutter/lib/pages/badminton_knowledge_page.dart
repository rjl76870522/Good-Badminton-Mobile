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
          body: '按赛事级别安排观赛，具体比赛日期和签表以赛事官方发布为准',
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
          body: '世界排名会随参赛和积分变化，本页先帮助理解项目分类和排名用途，不展示可能过期的名次',
        ),
        _InfoCard(title: '男子单打', badge: 'MS', body: '重视连续进攻、全场移动和多拍稳定性'),
        _InfoCard(title: '女子单打', badge: 'WS', body: '观察节奏变化、落点控制和攻守转换效率'),
        _InfoCard(title: '男子双打', badge: 'MD', body: '强调前三拍、平抽挡速度和轮转衔接'),
        _InfoCard(title: '女子双打', badge: 'WD', body: '重视防守韧性、连贯压制和搭档覆盖'),
        _InfoCard(title: '混合双打', badge: 'XD', body: '前后场分工与轮转速度是主要观察重点'),
        _NoteCard(text: '正式接入排名数据时，应记录数据来源与更新时间，避免把缓存名次当作实时结果'),
      ];

  List<Widget> get _playerContent => const [
        _IntroCard(
          icon: Icons.person_search_outlined,
          title: '从球星学习',
          body: '资料聚焦可观察的技术特点，不给球员贴固定标签，也不使用未经核实的大众评价',
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

  List<Widget> get _equipmentContent => const [
        _IntroCard(
          icon: Icons.inventory_2_outlined,
          title: '按需求选择装备',
          body: '装备没有统一的最好选择，应结合力量、打法、训练频率和伤病情况判断',
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
        _NoteCard(text: '价格和用户评价变化较快，后续装备数据应标注更新时间，并区分客观参数与主观体验'),
      ];
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

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
        ],
      ),
    );
  }
}
