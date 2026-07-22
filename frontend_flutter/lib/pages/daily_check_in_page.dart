import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DailyCheckInPage extends StatefulWidget {
  const DailyCheckInPage({super.key});

  @override
  State<DailyCheckInPage> createState() => _DailyCheckInPageState();
}

class _DailyCheckInPageState extends State<DailyCheckInPage> {
  static const _lastDateKey = 'daily_check_in_last_date';
  static const _streakKey = 'daily_check_in_streak';
  static const _totalKey = 'daily_check_in_total';
  static const _stories = <({String player, String text})>[
    (
      player: '林丹',
      text: '长期保持高水平，来自一次次把基本动作练到稳定。今天也从一个清楚的小目标开始。',
    ),
    (
      player: '李宗伟',
      text: '漫长职业生涯里，真正可贵的是在困难之后继续回到训练场。稳定坚持本身就是进步。',
    ),
    (
      player: '张宁',
      text: '成熟不只是力量和速度，更是关键时刻仍能执行自己的节奏。训练时也要留意每一拍的选择。',
    ),
    (
      player: '陶菲克',
      text: '鲜明的技术风格建立在扎实手感之上。放慢一点，把击球质量做好，速度自然会回来。',
    ),
    (
      player: '安赛龙',
      text: '高水平训练不仅记录胜负，也重视恢复、复盘和长期计划。今天的报告就是下一次训练的起点。',
    ),
    (
      player: '陈雨菲',
      text: '耐心组织每一个回合，往往比急于得分更重要。先站稳位置，再寻找真正合适的机会。',
    ),
    (
      player: '郑思维与黄雅琼',
      text: '双打默契来自持续沟通和明确分工。每次训练后说清一个做得好的点和一个要改的点。',
    ),
    (
      player: '谌龙',
      text: '稳固的防守不是被动等待，而是在每次回球中重新争取主动。先提高回球质量，再寻找反攻机会。',
    ),
    (
      player: '张军与高崚',
      text: '混双需要两个人共同判断下一拍，而不是各自完成动作。训练中把轮转口令说出来，会更容易发现配合问题。',
    ),
    (
      player: '蔡赟与傅海峰',
      text: '速度和重杀之外，连续压迫更依赖合理分工。一次有效封网，往往来自搭档上一拍创造的机会。',
    ),
    (
      player: '葛菲与顾俊',
      text: '稳定的组合会把复杂回合拆成清楚的职责。今天可以专门练习一次发接发后的前三拍衔接。',
    ),
    (
      player: '戴资颖',
      text: '变化建立在对基本落点的掌控上。先让同一个动作能够打出不同线路，再追求更大胆的选择。',
    ),
    (
      player: '山口茜',
      text: '积极移动不等于每一拍都用尽全力。小步调整和及时回位，能让下一次启动更从容。',
    ),
    (
      player: '桃田贤斗',
      text: '高质量控网能让回合按照自己的节奏展开。练习时记录对手被迫起高球的次数，比只看得分更有价值。',
    ),
    (
      player: '卡罗琳娜·马林',
      text: '主动和专注会体现在每一拍之后的回位。失误后尽快准备下一球，是比赛中非常实用的能力。',
    ),
    (
      player: '王适娴',
      text: '拉吊控制需要耐心，也需要准确判断对手的位置。今天尝试在击球前多观察一次对方重心。',
    ),
    (
      player: '王仪涵',
      text: '扎实的多拍能力来自稳定训练量。不要急着增加强度，先保证每一组动作都能保持质量。',
    ),
    (
      player: '吉新鹏',
      text: '重大比赛中的发挥来自平时对细节的准备。上场前把发球、接发和第一拍落点想清楚。',
    ),
    (
      player: '赵芸蕾',
      text: '优秀双打球员会持续阅读搭档和对手。复盘时不仅看自己击球，也观察自己没有击球时站在哪里。',
    ),
    (
      player: '陈清晨与贾一凡',
      text: '顽强防守需要信任和补位。训练后一起回看丢分回合，比单独讨论最后一次失误更有效。',
    ),
    (
      player: '刘雨辰与欧烜屹',
      text: '双打进攻不只依靠力量，落点变化和前场跟进同样关键。今天尝试让每次后场进攻都有下一拍计划。',
    ),
    (
      player: '陈金',
      text: '节奏稳定能减少无谓消耗。连续训练时，先守住动作完整性，再逐渐提高移动速度。',
    ),
    (
      player: '韩爱萍',
      text: '真正可靠的技术经得起重复。选一个薄弱落点，持续完成高质量练习，比一次练很多内容更清楚。',
    ),
    (
      player: '叶钊颖',
      text: '比赛判断来自大量观察和经验积累。复盘时暂停在击球前一刻，想想是否还有更好的线路。',
    ),
    (
      player: '谢杏芳',
      text: '身高和力量只有结合步法才能转化为优势。击球后及时降低重心，准备下一次启动。',
    ),
    (
      player: '陈宏',
      text: '进攻连续性比一次漂亮重杀更难。今天记录自己杀球后能否及时跟上下一拍。',
    ),
    (
      player: '顾俊',
      text: '双打前场需要果断，也需要知道何时不抢球。明确中间球的处理原则，可以减少很多配合失误。',
    ),
    (
      player: '李玲蔚',
      text: '手上变化来自细腻的触球感觉。用较慢速度练习搓、勾、推，先让落点稳定下来。',
    ),
    (
      player: '栾劲',
      text: '训练计划要给身体留下恢复空间。疲劳时降低强度并不等于退步，而是在为下一次高质量训练准备。',
    ),
    (
      player: '拉尔斯·帕斯克与乔纳斯·拉斯姆森',
      text: '经验丰富的组合善于利用线路和站位弥补速度差异。打球时多创造容易判断的下一拍。',
    ),
    (
      player: '彼得·盖德',
      text: '主动抢点来自提前判断，而不只是跑得更快。观察对手拍面和身体朝向，可以更早开始移动。',
    ),
  ];

  bool _loading = true;
  bool _checkedToday = false;
  int _streak = 0;
  int _total = 0;

  String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  ({String player, String text}) get _todayStory {
    final now = DateTime.now();
    final dayNumber = now.difference(DateTime(now.year, 1, 1)).inDays;
    return _stories[dayNumber % _stories.length];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _checkedToday =
          preferences.getString(_lastDateKey) == _dateKey(DateTime.now());
      _streak = preferences.getInt(_streakKey) ?? 0;
      _total = preferences.getInt(_totalKey) ?? 0;
      _loading = false;
    });
  }

  Future<void> _checkIn() async {
    if (_checkedToday) return;
    final now = DateTime.now();
    final preferences = await SharedPreferences.getInstance();
    final lastDate = preferences.getString(_lastDateKey);
    final continued =
        lastDate == _dateKey(now.subtract(const Duration(days: 1)));
    final streak = continued ? (preferences.getInt(_streakKey) ?? 0) + 1 : 1;
    final total = (preferences.getInt(_totalKey) ?? 0) + 1;
    await Future.wait([
      preferences.setString(_lastDateKey, _dateKey(now)),
      preferences.setInt(_streakKey, streak),
      preferences.setInt(_totalKey, total),
    ]);
    if (!mounted) return;
    setState(() {
      _checkedToday = true;
      _streak = streak;
      _total = total;
    });
  }

  @override
  Widget build(BuildContext context) {
    final story = _todayStory;
    return Scaffold(
      appBar: AppBar(title: const Text('每日签到')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF174B2A),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.sports_tennis,
                          color: Colors.white, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        _checkedToday ? '今天已签到' : '为今天的训练留下记录',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '连续 $_streak 天  ·  累计 $_total 天',
                        style: const TextStyle(color: Color(0xDFFFFFFF)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_checkedToday)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('今日羽球故事',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 12),
                          Text(story.player,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Text(story.text, style: const TextStyle(height: 1.6)),
                        ],
                      ),
                    ),
                  )
                else
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.lock_outline),
                      title: Text('签到后解锁今日内容'),
                      subtitle: Text('每天都有一则励志寄语或羽球趣味故事'),
                    ),
                  ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _checkedToday ? null : _checkIn,
                  icon:
                      Icon(_checkedToday ? Icons.check : Icons.calendar_today),
                  label: Text(_checkedToday ? '明天再来' : '签到并领取今日故事'),
                ),
              ],
            ),
    );
  }
}
