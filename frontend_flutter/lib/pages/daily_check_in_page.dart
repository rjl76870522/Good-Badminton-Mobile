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
                        const SizedBox(height: 8),
                        Text(
                          '内容为项目团队根据公开生涯经历整理，不是运动员原话',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
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
