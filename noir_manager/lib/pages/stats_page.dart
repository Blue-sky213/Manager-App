import 'package:flutter/material.dart';

import '../calendar/achievements.dart';
import '../calendar/calendar_listener.dart';
import '../calendar/calendar_models.dart';
import '../data/study_scope.dart';
import '../study/tutor_plan.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/page_scaffold.dart';

/// หน้า "สถิติ": สตรีคทำครบทุกวัน + เหรียญความสำเร็จ (สรุป 3/6/9/12 เดือน = Phase 2)
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

/// เหรียญ 1 อัน · [done] = ได้แล้ว (ยังไม่ได้ = จาง + บอกว่าขาดอีกเท่าไหร่)
class _Badge {
  const _Badge(this.mark, this.title, this.detail, {this.done = true});
  final String mark;
  final String title;
  final String detail;
  final bool done;
}

class _StatsPageState extends State<StatsPage> with CalendarListener<StatsPage> {
  StreakInfo? _streak;
  List<_Badge> _badges = [];

  @override
  Future<void> reload() async {
    final study = StudyScope.of(context);
    final today = dayOnly(DateTime.now());
    final streak = await loadStreak(calendar!, today);
    final pass = int.tryParse(await study.getSetting(tutorPassKey) ?? '') ?? defaultTutorPass;
    final badges = <_Badge>[];
    if (streak.completeDays.isNotEmpty) {
      final last = streak.completeDays.first;
      badges.add(_Badge('✓', 'ครบทั้งวัน', '${thaiShortDate(last)} · ใน 60 วันครบ ${streak.completeDays.length} วัน'));
    }
    for (final goal in [7, 30]) {
      badges.add(_Badge('$goal', 'สตรีค $goal วัน',
          streak.best >= goal ? 'ทำได้แล้ว · ดีที่สุด ${streak.best} วัน' : 'อีก ${goal - streak.current} วัน',
          done: streak.best >= goal));
    }
    for (final s in await study.subjects()) {
      final logs = await study.classLogs(s.id);
      if (logs.isEmpty) continue;
      final chapters = await study.chapters(s.id);
      final finished = logs.where((l) => l.finished).length;
      if (finished > 0) badges.add(_Badge('บท', 'จบ $finished บท · ${s.name}', 'จากบันทึกเรียน'));
      final scope = tutorScope(chapters, logs);
      if (scopePassed(scope, pass)) {
        badges.add(_Badge('$pass', 'ทวนผ่าน $pass% · ${s.name}', 'บทที่เรียนแล้วเฉลี่ย ${scopeAverage(scope)!.round()}%'));
      }
    }
    if (!mounted) return;
    setState(() {
      _streak = streak;
      _badges = badges;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final s = _streak;
    return PageScaffold(
      overline: 'Stats',
      title: 'สถิติ',
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('สตรีคทำครบทุกวัน', style: TextStyle(fontSize: 13, color: c.muted)),
                  const SizedBox(height: 4),
                  Text(s == null ? '—' : '${s.current} วัน',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: c.text)),
                  Text(s == null ? '' : 'ดีที่สุด ${s.best} วัน · วันว่างไม่ตัดสตรีค',
                      style: TextStyle(fontSize: 13, color: c.muted)),
                ]),
              ),
              Icon(Icons.local_fire_department_outlined, size: 36, color: (s?.current ?? 0) > 0 ? c.good : c.line2),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Text('เหรียญ', style: TextStyle(fontSize: 13, color: c.muted)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              for (final b in _badges)
                Opacity(
                  opacity: b.done ? 1 : 0.45,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: b.done ? c.greenBg : c.surface2,
                      foregroundColor: b.done ? c.greenText : c.muted,
                      child: Text(b.mark, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    title: Text(b.title),
                    subtitle: Text(b.detail),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Text('สรุป 3 / 6 / 9 / 12 เดือน — มาใน Phase 2', style: TextStyle(fontSize: 12, color: c.muted)),
      ],
    );
  }
}
