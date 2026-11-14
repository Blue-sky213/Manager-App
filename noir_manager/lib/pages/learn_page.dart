/// เมนู "การเรียน" (รอบ 8C): สลับ มหาลัย | สกิล ด้านบน · สองหน้าเก็บสถานะไว้ (สลับไปมาไม่รีเซ็ต)
library;

import 'package:flutter/material.dart';

import '../shell/app_nav.dart' show subjectJump;
import '../skills/skills_page.dart';
import '../widgets/mini_segments.dart';
import 'study_page.dart';

class LearnPage extends StatefulWidget {
  const LearnPage({super.key});

  @override
  State<LearnPage> createState() => _LearnPageState();
}

class _LearnPageState extends State<LearnPage> {
  bool _skills = false;

  @override
  void initState() {
    super.initState();
    subjectJump.addListener(_toUni);
  }

  @override
  void dispose() {
    subjectJump.removeListener(_toUni);
    super.dispose();
  }

  // เปิดวิชาจากหน้าอื่น → กลับมาฝั่งมหาลัย
  void _toUni() {
    if (_skills && mounted) setState(() => _skills = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 220,
            child: MiniSegments<bool>(
              key: const Key('learn-switch'),
              value: _skills,
              items: const [(false, 'มหาลัย'), (true, 'สกิล')],
              onChanged: (v) => setState(() => _skills = v),
            ),
          ),
        ),
      ),
      Expanded(child: IndexedStack(index: _skills ? 1 : 0, children: const [StudyPage(), SkillsPage()])),
    ]);
  }
}
