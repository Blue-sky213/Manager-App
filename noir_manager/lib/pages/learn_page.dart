/// เมนู "การเรียน" (รอบ 9A): หัวแบบเดียวกันทุกเมนู + แท็บ
/// ภาพรวม (เปิดมาเจอ) · รายวิชา · แผน 4 ปี · ตารางเรียน · เกรด · สกิลแยกไปเมนูของตัวเอง
library;

import 'package:flutter/material.dart';

import '../shell/app_nav.dart' show subjectJump;
import '../study/gpa_page.dart';
import '../study/term_overview.dart';
import '../study/week_timetable.dart';
import '../widgets/menu_header.dart';
import 'study_page.dart';

enum LearnTab { overview, subjects, plan, week, grades }

class LearnPage extends StatefulWidget {
  const LearnPage({super.key});

  @override
  State<LearnPage> createState() => _LearnPageState();
}

class _LearnPageState extends State<LearnPage> {
  LearnTab _tab = LearnTab.overview;

  @override
  void initState() {
    super.initState();
    subjectJump.addListener(_toSubjects);
    studyMapView.addListener(_sync);
  }

  @override
  void dispose() {
    subjectJump.removeListener(_toSubjects);
    studyMapView.removeListener(_sync);
    super.dispose();
  }

  // เปิดวิชาจากหน้าอื่น → แท็บรายวิชา
  void _toSubjects() {
    if (mounted) setState(() => _tab = LearnTab.subjects);
  }

  // หน้าวิชาสลับเอง (เปิดวิชาจากแผนผัง / กลับแผน 4 ปี) → แท็บตาม
  void _sync() {
    if (!mounted || (_tab != LearnTab.subjects && _tab != LearnTab.plan)) return;
    final t = studyMapView.value ? LearnTab.plan : LearnTab.subjects;
    if (t != _tab) setState(() => _tab = t);
  }

  void _open(int subjectId, String from) {
    setState(() => _tab = LearnTab.subjects);
    studyViewRequest.open(subjectId, from: from);
  }

  void _go(LearnTab t) {
    setState(() => _tab = t);
    if (t == LearnTab.subjects || t == LearnTab.plan) studyViewRequest.go(t == LearnTab.plan);
  }

  @override
  Widget build(BuildContext context) {
    final index = switch (_tab) {
      LearnTab.overview => 0,
      LearnTab.subjects || LearnTab.plan => 1,
      LearnTab.week => 2,
      LearnTab.grades => 3,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MenuHeader(
        group: 'พัฒนาตัวเอง',
        title: 'การเรียน',
        tabs: MenuTabs<LearnTab>(
          key: const Key('learn-tabs'),
          value: _tab,
          items: const [
            (LearnTab.overview, 'ภาพรวม'),
            (LearnTab.subjects, 'รายวิชา'),
            (LearnTab.plan, 'แผน 4 ปี'),
            (LearnTab.week, 'ตารางเรียน'),
            (LearnTab.grades, 'เกรด'),
          ],
          onChanged: _go,
        ),
      ),
      Expanded(
        child: IndexedStack(index: index, children: [
          TermOverview(onOpenSubject: (s) => _open(s.id, 'overview')),
          StudyPage(
            embedded: true,
            onOpenWeek: () => _go(LearnTab.week),
            onOverview: () => _go(LearnTab.overview),
          ),
          WeekTimetablePage(embedded: true, onOpenSubject: (s) => _open(s.id, 'week')),
          const GpaPage(embedded: true),
        ]),
      ),
    ]);
  }
}
