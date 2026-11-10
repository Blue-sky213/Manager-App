import 'package:flutter/material.dart';

import '../calendar/calendar_repository.dart';
import '../calendar/calendar_models.dart';
import '../calendar/calendar_ui.dart';
import '../calendar/terms_page.dart';
import '../data/demo_term.dart';
import '../data/study_models.dart';
import '../data/study_repository.dart';
import '../data/study_scope.dart';
import '../shell/app_nav.dart';
import '../study/gpa_page.dart';
import '../study/grade_card.dart';
import '../study/advanced_rules.dart';
import '../study/class_schedule_card.dart';
import '../study/credit_hours.dart';
import '../study/curriculum_map.dart';
import '../study/week_timetable.dart';
import '../study/subject_colors.dart';
import '../study/tutor_card.dart';
import '../study/mastery.dart';
import '../study/score_history_dialog.dart';
import '../study/subtopic_dialog.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/mini_dropdown.dart';
import '../widgets/dialogs.dart';

/// หน้า "วิชา": Study Tree + Mastery Score
/// วิชา → บท → หัวข้อย่อย · แตะหัวข้อย่อยเพื่อบันทึกคะแนน / ติดธง / ลบ
class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  StudyRepository? _repo;
  bool _loading = true;
  List<Subject> _subjects = [];
  int? _subjectId; // วิชาที่เลือกอยู่
  List<ChapterWithTopics> _chapters = [];
  GradingMode _mode = GradingMode.ez;

  /// มุมมองหน้าวิชา: แผนผังแผนการเรียน หรือ รายละเอียดวิชา (จำไว้ใน setting)
  bool _mapView = true;

  /// วิชาที่เลือก "ไฮไลต์สาย" ในแผนผัง (คลิกขวา) · ล้างทุกครั้งที่ออกจากแผนผัง
  int? _mapSelectedId;

  /// เปิดรายละเอียดวิชามาจากไหน → ปุ่ม "กลับ" / เมาส์ปุ่ม 4 พากลับไปที่เดิม · null = ไม่มีที่ให้กลับ
  String? _returnTo; // 'map' | 'week' | 'jump' (มาจากเมนูอื่น)

  /// ปีที่ดูในแผนผัง (แตะหัวปี/เทอม) · null = ทั้งหลักสูตร · คงไว้ตอนกลับจากหน้าวิชา
  int? _mapYear;

  /// ภาคที่ดูในแผนผัง (แตะหัวภาค) · null = ทุกภาคของปีนั้น
  int? _mapTerm;

  /// ปีที่ดูอยู่ในหน้ารายวิชา (0 = ยังไม่จัดปี) · null = ตามปีของวิชาที่เปิด
  int? _yearView;

  /// แท็บในหน้าวิชา: 0 ภาพรวม · 1 บทเรียน · 2 ตารางเรียน · 3 ติว
  int _tab = 0;

  /// ขอบเขตรายชื่อวิชาด้านซ้าย: 'term' เทอมนี้ · 'year' ปีการศึกษา · 'all' ทั้งหมด
  String _scope = 'term';
  String _sidebarQuery = '';

  /// เทอมที่มีวันนี้อยู่ (จากปฏิทิน → เทอมและวันหยุด) · null = ยังไม่ได้ตั้งเทอม
  ({int year, int term})? _currentTerm;

  /// ป้ายบนหัววิชา: คาบถัดไป / สอบถัดไป
  String? _nextClass;

  /// แผนผัง: กล่องสีเริ่มต้น หรือสีประจำวิชา (จำไว้ใน setting)
  bool _mapColorBySubject = false;
  static const _mapColorKey = 'map_color';
  String? _nextExam;
  static const _viewKey = 'study_view';
  Map<int, SubjectProgress> _progress = {};

  /// เส้นวิชาที่ต้องเรียนก่อน (วาดในแผนผัง)
  List<SubjectLink> _links = [];

  /// ส่วนที่ "ยุบ" อยู่ (จำไว้ในฐานข้อมูล): 'ch<id>' = การ์ดบท · 'review' / 'exam' = กล่องท้ายหน้า
  Set<String> _collapsed = {};
  static const _collapsedKey = 'collapsed_sections';

  Subject? get _subject {
    for (final s in _subjects) {
      if (s.id == _subjectId) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    subjectJump.addListener(_onSubjectJump);
    appBack.add(_onAppBack);
  }

  @override
  void dispose() {
    subjectJump.removeListener(_onSubjectJump);
    appBack.remove(_onAppBack);
    super.dispose();
  }

  /// หน้าอื่นขอเปิดวิชา (คลิกคาบในปฏิทิน / วันนี้) → เปิดรายละเอียด · ย้อนกลับ = กลับหน้าเดิม
  void _onSubjectJump() {
    final s = _subjects.where((s) => s.id == subjectJump.subjectId).firstOrNull;
    if (s != null && mounted) _openSubject(s, from: 'jump');
  }

  /// เมาส์ปุ่ม 4 ตอนหน้าวิชาโชว์อยู่: กลับแผนผัง / ตารางเรียน · มาจากเมนูอื่น → ให้ shell พากลับ
  bool _onAppBack() {
    if (currentTab.value != 'การเรียน' || _mapView || _returnTo == null) return false;
    if (_returnTo == 'jump') {
      setState(() => _returnTo = null);
      return false;
    }
    _goBack();
    return true;
  }

  // ใช้ didChangeDependencies แทน initState เพราะต้องอ่าน StudyScope จาก context
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = StudyScope.of(context);
    if (repo != _repo) {
      _repo = repo;
      _reload();
    }
  }

  /// โหลดข้อมูลใหม่ทั้งหน้า (เรียกหลังทุกการเปลี่ยนแปลง)
  Future<void> _reload() async {
    final repo = _repo!;
    final subjects = await repo.subjects();
    final selected = subjects.any((s) => s.id == _subjectId)
        ? _subjectId
        : (subjects.isEmpty ? null : subjects.first.id);
    final mode = await repo.gradingMode();
    final collapsedRaw = await repo.getSetting(_collapsedKey) ?? '';
    final chapters =
        selected == null ? <ChapterWithTopics>[] : await repo.chapters(selected);
    final view = await repo.getSetting(_viewKey);
    final mapColor = await repo.getSetting(_mapColorKey);
    final links = await repo.subjectLinks();
    // ความคืบหน้าทุกวิชา (ใช้วาดแถบสีในแผนผัง)
    final progress = <int, SubjectProgress>{};
    for (final s in subjects) {
      final topics = [for (final ch in await repo.chapters(s.id)) ...ch.subtopics];
      final scores = [for (final t in topics) if (t.latestScore != null) t.latestScore!];
      progress[s.id] = SubjectProgress(
        assessed: scores.length,
        total: topics.length,
        average: scores.isEmpty ? null : scores.reduce((a, b) => a + b) / scores.length,
      );
    }
    if (!mounted) return; // ผู้ใช้ปิดหน้าไปแล้วระหว่างรอ → ไม่ต้องวาด
    final cal = CalendarScope.of(context);
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final term = (await cal.terms()).where((t) => !day.isBefore(t.start) && !day.isAfter(t.end)).firstOrNull;
    final upcoming = selected == null ? null : _upcoming(await cal.activitiesForSubject(selected), day);
    if (!mounted) return;
    refreshSubjectColors(repo);
    setState(() {
      _mapColorBySubject = mapColor == 'subject';
      _currentTerm = term == null ? null : (year: term.year, term: term.termNo);
      _nextClass = upcoming?.$1;
      _nextExam = upcoming?.$2;
      _subjects = subjects;
      _subjectId = selected;
      _chapters = chapters;
      _mode = mode;
      _mapView = view != 'detail';
      _progress = progress;
      _links = links;
      _collapsed = collapsedRaw.split(',').where((k) => k.isNotEmpty).toSet();
      _loading = false;
    });
  }

  Future<void> _addSubject() async {
    final name = await askText(context,
        title: 'เพิ่มวิชา', label: 'ชื่อวิชา', hint: 'เช่น DataCOM');
    if (name == null || !mounted) return;
    final importance = await askImportance(context, current: 2);
    if (importance == null) return; // ยกเลิกตอนเลือกความสำคัญ = ไม่เพิ่มวิชา
    final id = await _repo!.addSubject(name, importance: importance);
    _subjectId = id;
    await _reload();
  }

  Future<void> _renameSubject(Subject subject) async {
    final name = await askText(context,
        title: 'เปลี่ยนชื่อวิชา',
        label: 'ชื่อวิชา',
        initial: subject.name,
        confirmLabel: 'บันทึก');
    if (name == null) return;
    await _repo!.renameSubject(subject.id, name);
    await _reload();
  }

  Future<void> _changeImportance(Subject subject) async {
    final importance = await askImportance(context, current: subject.importance);
    if (importance == null) return;
    await _repo!.setSubjectImportance(subject.id, importance);
    await _reload();
  }

  /// เลือกรอบติวต่อสัปดาห์ภายในช่วงของความสำคัญ (น้อย 1–2 · กลาง 2–3 · สูง 3–7)
  Future<void> _changeSessions(Subject subject) async {
    final (lo, hi) = sessionRange(subject.importance);
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('รอบติวต่อสัปดาห์'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ความสำคัญ${subject.importanceLabel} เลือกได้ $lo–$hi รอบ'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var n = lo; n <= hi; n++)
                  ChoiceChip(
                    label: Text('$n'),
                    selected: n == subject.sessionsPerWeek,
                    onSelected: (_) => Navigator.pop(ctx, n),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('อยากได้มากกว่านี้ → เปลี่ยนความสำคัญของวิชาก่อน',
                style: TextStyle(fontSize: 12, color: ctx.noir.muted)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ปิด')),
        ],
      ),
    );
    if (picked == null) return;
    await _repo!.setSessionsPerWeek(subject.id, picked);
    await _reload();
  }

  /// ใส่ข้อมูลตัวอย่าง ปี 1 เทอม 1 (6 วิชา + บท + คาบเรียน + วันสอบ)
  Future<void> _loadDemo() async {
    final added = await loadDemoCurriculum(_repo!, CalendarScope.of(context));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(added > 0
          ? 'ใส่แผน 4 ปีแล้ว: เพิ่ม $added วิชา · ปี 1 เทอม 1 มีบท + คาบ + วันสอบ'
          : 'มีแผนตัวอย่างครบแล้ว'),
    ));
    await _reload();
  }

  /// เมนูทั้งหน้า (ใช้ทั้งในแผนผังและหน้ารายละเอียดวิชา)
  static const List<PopupMenuEntry<String>> _pageMenuItems = [
    PopupMenuItem(value: 'terms', child: Text('ภาคเรียน & วันหยุด')),
    PopupMenuItem(value: 'dupes', child: Text('ลบคาบเรียน/วันสอบที่ซ้ำ')),
    PopupMenuItem(value: 'demo', child: Text('ใส่ตัวอย่าง: แผน 4 ปี')),
    PopupMenuItem(value: 'links', child: Text('ใส่เส้นเชื่อมตามหลักสูตร 2567')),
    PopupMenuItem(value: 'enrich', child: Text('เติมรายละเอียดตัวอย่างให้ครบ (ทดสอบ)')),
  ];

  void _onPageMenu(String v) {
    switch (v) {
      case 'terms':
        openTermsPage(context);
      case 'dupes':
        _removeDuplicates();
      case 'links':
        _loadLinks();
      case 'enrich':
        _enrichDemo();
      default:
        _loadDemo();
    }
  }

  /// เติมรายละเอียดให้วิชาตัวอย่าง (คะแนน ห้อง คาบที่เรียนแล้ว ติว งานหมวดอื่น วันหยุด)
  /// แตะข้อมูลเดิม → ถามก่อน และแนะนำให้สำรองข้อมูลก่อน
  Future<void> _enrichDemo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เติมรายละเอียดตัวอย่าง'),
        content: const Text('เพิ่มให้วิชาตัวอย่างปี 1 ภาค 1:\n'
            '• คะแนนหัวข้อ · ห้องเรียน · สถานะบท\n'
            '• คาบที่ผ่านมา = ทำแล้ว + เวลาเลิกจริง (ยกเลิก 1 คาบ)\n'
            '• รอบติว · วิ่ง / สตรีม / ส่งงาน · Updates · วันหยุด\n\n'
            'ของที่มีอยู่แล้วไม่ถูกทับ · ลบทีละรายการได้ · แนะนำให้สำรองข้อมูลก่อน'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('เติมเลย')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final summary = await enrichDemoTerm(_repo!, CalendarScope.of(context));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(summary)));
    await _reload();
  }

  /// เส้นตามหลักสูตร: จับคู่จากรหัสวิชา · เพิ่มอย่างเดียว เส้นที่ทำเองไม่หาย
  Future<void> _loadLinks() async {
    final n = await loadCurriculumLinks(_repo!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(n == 0
          ? 'ไม่มีเส้นใหม่ให้เพิ่ม (มีครบแล้ว หรือรหัสวิชาไม่ตรงหลักสูตร)'
          : 'เพิ่มเส้นเชื่อม $n เส้น'),
    ));
    await _reload();
  }

  /// แก้เส้นของวิชาเดียว: ติ๊กวิชาที่ต้องเรียนก่อน / วิชาที่ต่อยอด
  Future<void> _editLinks(Subject subject) async {
    // ลำดับในแผน: ปี/เทอม · วิชายังไม่จัดเทอมไม่อยู่ในรายการ (ไม่รู้ว่ามาก่อนหรือหลัง)
    int? order(Subject s) =>
        s.planYear == null || s.planTerm == null ? null : s.planYear! * 10 + s.planTerm!;
    final me = order(subject);
    if (me == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('จัดปี / เทอม ของวิชานี้ก่อน แล้วค่อยต่อเส้น')));
      return;
    }
    final others = [for (final s in _subjects) if (s.id != subject.id && order(s) != null) s]
      ..sort((a, b) => order(a)!.compareTo(order(b)!));
    final before = [for (final s in others) if (order(s)! < me) s];
    final after = [for (final s in others) if (order(s)! > me) s];
    final pre = {for (final l in _links) if (l.to == subject.id) l.from};
    final post = {for (final l in _links) if (l.from == subject.id) l.to};
    final newPre = {...pre}, newPost = {...post};

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final c = ctx.noir;
        Widget section(String title, List<Subject> items, Set<int> picked) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                  child: Text(title,
                      style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                ),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text('ไม่มีวิชาในช่วงนี้', style: TextStyle(color: c.muted)),
                  ),
                for (final s in items)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: picked.contains(s.id),
                    title: Text(s.name),
                    subtitle: Text('ปี ${s.planYear} · ${s.planTerm == 3 ? 'ฤดูร้อน' : 'ภาค ${s.planTerm}'}'
                        '${s.code == null ? '' : ' · ${s.code}'}'),
                    onChanged: (v) => setLocal(() {
                      if (v == true) {
                        picked.add(s.id);
                      } else {
                        picked.remove(s.id);
                      }
                    }),
                  ),
              ],
            );
        return AlertDialog(
          title: Text('เส้นเชื่อม · ${subject.name}'),
          content: SizedBox(
            width: 480,
            child: ListView(
              shrinkWrap: true,
              children: [
                section('ต้องเรียนก่อนวิชานี้', before, newPre),
                section('วิชานี้ต่อยอดไปที่', after, newPost),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('บันทึก')),
          ],
        );
      }),
    );
    if (ok != true) return;
    final repo = _repo!;
    for (final id in newPre.difference(pre)) {
      await repo.addSubjectLink(id, subject.id);
    }
    for (final id in pre.difference(newPre)) {
      await repo.removeSubjectLink(id, subject.id);
    }
    for (final id in newPost.difference(post)) {
      await repo.addSubjectLink(subject.id, id);
    }
    for (final id in post.difference(newPost)) {
      await repo.removeSubjectLink(subject.id, id);
    }
    await _reload();
  }

  Future<void> _removeDuplicates() async {
    final n = await CalendarScope.of(context).removeDuplicateActivities();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(n == 0 ? 'ไม่มีคาบเรียน/วันสอบซ้ำ' : 'ลบรายการที่ซ้ำแล้ว $n รายการ'),
    ));
  }

  Widget _yearPicker(BuildContext context, Subject? subject) {
    final c = context.noir;
    int yearOf(Subject s) => s.planYear ?? 0;
    final years = {for (final s in _subjects) yearOf(s)}.toList()
      ..sort((a, b) => a == 0 ? 1 : (b == 0 ? -1 : a - b)); // "ยังไม่จัดปี" ไว้ท้าย
    var year = _yearView ?? (subject == null ? null : yearOf(subject));
    if (year == null || !years.contains(year)) year = years.isEmpty ? 0 : years.first;
    final inYear = _subjects.where((s) => yearOf(s) == year).toList();
    final terms = {for (final s in inYear) s.planTerm ?? 0}.toList()
      ..sort((a, b) => a == 0 ? 1 : (b == 0 ? -1 : a - b));
    String termLabel(int t) => switch (t) { 0 => 'ไม่ระบุเทอม', 3 => 'ฤดูร้อน', _ => 'เทอม $t' };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (years.isNotEmpty)
            MiniDropdown<int>(
              width: 200,
              value: year,
              items: [
                for (final y in years)
                  (y, '${y == 0 ? 'ยังไม่จัดปี' : 'ปี $y'} · ${_subjects.where((s) => yearOf(s) == y).length} วิชา'),
              ],
              onChanged: (y) => setState(() => _yearView = y),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('เพิ่มวิชา'),
            onPressed: _addSubject,
          ),
        ]),
        const SizedBox(height: 10),
        for (final t in terms)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 76,
                child: Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Text(termLabel(t), style: TextStyle(color: c.muted, fontSize: 13)),
                ),
              ),
              Expanded(
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in inYear.where((s) => (s.planTerm ?? 0) == t))
                    // คลิกขวา / กดค้างที่ชิปวิชา = เมนูเดียวกับในแผนผัง
                    GestureDetector(
                      onSecondaryTapUp: (d) => _subjectMenu(s, d.globalPosition, inDetail: true),
                      onLongPressStart: (d) => _subjectMenu(s, d.globalPosition, inDetail: true),
                      child: ChoiceChip(
                        label: Text(s.name),
                        selected: s.id == _subjectId,
                        onSelected: (_) {
                          _subjectId = s.id;
                          _yearView = year;
                          _reload();
                        },
                      ),
                    ),
                ]),
              ),
            ]),
          ),
      ],
    );
  }

  void _setMapView(bool map) {
    setState(() {
      _mapView = map;
      _mapSelectedId = null; // ไม่ให้กรอบเลือกค้างตอนกลับมา
      if (map) _returnTo = null;
    });
    _repo!.setSetting(_viewKey, map ? 'map' : 'detail');
  }

  /// คาบถัดไป (ภายใน 2 สัปดาห์) และสอบถัดไปของวิชา → ข้อความสั้นบนหัววิชา
  (String?, String?) _upcoming(List<Activity> acts, DateTime day) {
    String? nextClass;
    for (var k = 0; k < 14 && nextClass == null; k++) {
      final d = day.add(Duration(days: k));
      final hits = [
        for (final a in acts)
          if (a.kind == ActivityKind.classSession &&
              a.repeat == RepeatKind.weekly &&
              a.weekdays.contains(d.weekday) &&
              !d.isBefore(dayOnly(a.startDate)) &&
              (a.endDate == null || !d.isAfter(a.endDate!)))
            a
      ]..sort((x, y) => (x.startMinute ?? 0).compareTo(y.startMinute ?? 0));
      if (hits.isEmpty) continue;
      final a = hits.first;
      nextClass = '${k == 0 ? 'วันนี้' : thaiWeekdayShort[d.weekday - 1]} ${fmtMinute(a.startMinute ?? 0)}'
          '${a.classInfo.room == null ? '' : ' ห้อง ${a.classInfo.room}'}';
    }
    final exams = [
      for (final a in acts)
        if (a.kind == ActivityKind.exam && !dayOnly(a.startDate).isBefore(day)) a
    ]..sort((x, y) => x.startDate.compareTo(y.startDate));
    final nextExam = exams.isEmpty
        ? null
        : '${exams.first.name.split(' · ').first} · ${thaiShortDate(exams.first.startDate)}';
    return (nextClass, nextExam);
  }

  // ---------- หน้ารายวิชา: รายชื่อซ้าย · หัววิชา · แท็บ ----------

  /// รายชื่อวิชาด้านซ้าย + ตัวกรองขอบเขต เทอมนี้ / ปีการศึกษา / ทั้งหมด
  Widget _subjectSidebar(BuildContext context, Subject? subject) {
    final c = context.noir;
    final cur = _currentTerm ??
        (subject?.planYear == null ? null : (year: subject!.planYear!, term: subject.planTerm ?? 1));
    int yearOf(Subject s) => s.planYear ?? 0;
    final years = {for (final s in _subjects) yearOf(s)}.toList()
      ..sort((a, b) => a == 0 ? 1 : (b == 0 ? -1 : a - b));
    var year = _yearView ?? (subject == null ? null : yearOf(subject));
    if (year == null || !years.contains(year)) year = years.isEmpty ? 0 : years.first;

    final q = _sidebarQuery.trim().toLowerCase();
    bool match(Subject s) =>
        q.isEmpty || s.name.toLowerCase().contains(q) || (s.code ?? '').toLowerCase().contains(q);
    final inScope = switch (_scope) {
      'term' => [for (final s in _subjects) if (cur != null && s.planYear == cur.year && s.planTerm == cur.term) s],
      'year' => [for (final s in _subjects) if (yearOf(s) == year) s],
      _ => [..._subjects],
    }.where(match).toList();
    // กลุ่ม: ปี·ภาค (ทั้งหมด / ปี) · เทอมนี้ = กลุ่มเดียว
    // ขอบเขตปี: ปีอยู่บนชิปแล้ว หัวกลุ่มบอกแค่ภาค
    String termText(Subject s) => s.planTerm == 3 ? 'ฤดูร้อน' : 'ภาค ${s.planTerm ?? '-'}';
    String groupOf(Subject s) => s.planYear == null
        ? 'ยังไม่จัดปี'
        : (_scope == 'year' ? termText(s) : 'ปี ${s.planYear} · ${termText(s)}');
    int order(Subject s) => (s.planYear ?? 9) * 10 + (s.planTerm ?? 9);
    inScope.sort((a, b) => order(a).compareTo(order(b)));
    final groups = <String, List<Subject>>{};
    for (final s in inScope) {
      (groups[groupOf(s)] ??= []).add(s);
    }

    Widget item(Subject s) {
      final color = subjectColorOf(s);
      final avg = _progress[s.id]?.average;
      final level = masteryOf(avg?.round());
      final pctColor = switch (level) {
        MasteryLevel.good => c.good,
        MasteryLevel.warn => c.warn,
        MasteryLevel.bad => c.bad,
        MasteryLevel.none => c.muted,
      };
      final on = s.id == _subjectId;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: GestureDetector(
          onSecondaryTapUp: (d) => _subjectMenu(s, d.globalPosition, inDetail: true),
          onLongPressStart: (d) => _subjectMenu(s, d.globalPosition, inDetail: true),
          child: Material(
            color: on ? Color.alphaBlend(color.withValues(alpha: 0.14), c.surface) : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: on ? color : Colors.transparent),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                _subjectId = s.id;
                _reload();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(children: [
                  Container(width: 5, height: 34, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: c.text)),
                      Text('${s.code ?? 'ไม่มีรหัส'} · ${s.credits ?? '—'}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Text(avg == null ? '—' : '${avg.round()}%',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pctColor)),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: c.side,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 28, 12, 24),
        children: [
          SegmentedButton<String>(
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'term', label: Text('เทอมนี้')),
              ButtonSegment(value: 'year', label: Text('ปีการศึกษา')),
              ButtonSegment(value: 'all', label: Text('ทั้งหมด')),
            ],
            selected: {_scope},
            onSelectionChanged: (v) => setState(() => _scope = v.first),
          ),
          if (_scope == 'year') ...[
            const SizedBox(height: 8),
            // ปีการศึกษาเป็นดรอปดาวน์ แทนชิปหลายอัน
            if (years.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: MiniDropdown<int>(
                  width: double.infinity,
                  value: year,
                  items: [
                    for (final y in years)
                      (y, '${y == 0 ? 'ยังไม่จัดปี' : 'ปี $y'} · ${_subjects.where((s) => yearOf(s) == y).length} วิชา'),
                  ],
                  onChanged: (y) => setState(() => _yearView = y),
                ),
              ),
          ],
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: 'ค้นหาชื่อหรือรหัส (ในขอบเขตนี้)',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _sidebarQuery = v),
          ),
          const SizedBox(height: 8),
          if (_scope == 'term' && cur == null)
            Text('ยังไม่ได้ตั้งเทอม · ปฏิทิน → เทอมและวันหยุด', style: TextStyle(color: c.muted, fontSize: 13)),
          for (final MapEntry(key: title, value: list) in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
              child: Text(_scope == 'term' ? '$title (เทอมนี้)' : title,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.muted)),
            ),
            for (final s in list) item(s),
          ],
          if (groups.isEmpty && !(_scope == 'term' && cur == null))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('ไม่มีวิชาในขอบเขตนี้', style: TextStyle(color: c.muted, fontSize: 13)),
            ),
          const SizedBox(height: 12),
          Text('คลิก = เปิด · คลิกขวา = ตัวเลือก', style: TextStyle(color: c.muted, fontSize: 12)),
        ],
      ),
    );
  }

  /// หัววิชา: แถบสีวิชา · รหัส หน่วยกิต ชั่วโมง · ชื่อ · ป้ายคาบ/สอบถัดไป · วงกลม % ความเข้าใจ
  Widget _subjectHeader(BuildContext context, Subject subject, List<Widget> actions) {
    final c = context.noir;
    final color = subjectColorOf(subject);
    final h = parseCreditHours(subject.credits);
    final avg = _progress[subject.id]?.average;
    final level = masteryOf(avg?.round());
    final (ringColor, levelText) = switch (level) {
      MasteryLevel.good => (c.good, 'ดี'),
      MasteryLevel.warn => (c.warn, 'พอได้'),
      MasteryLevel.bad => (c.bad, 'ยังไม่ได้'),
      MasteryLevel.none => (c.muted, 'ยังไม่ประเมิน'),
    };
    Widget pill(String text, {VoidCallback? onTap}) => Material(
          color: c.surface2,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(text, style: TextStyle(fontSize: 13, color: c.text)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.10), c.surface),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(width: 6, height: 76, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6))),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                [
                  subject.code ?? 'ไม่มีรหัส',
                  subject.credits ?? 'ยังไม่มีหน่วยกิต',
                  if (h != null) 'ทฤษฎี ${h.theory} + ปฏิบัติ ${h.lab} ชม./สัปดาห์',
                ].join(' · '),
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
              const SizedBox(height: 4),
              Text(subject.name, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (_nextClass != null) pill('คาบถัดไป · $_nextClass', onTap: () => setState(() => _tab = 2)),
                if (_nextExam != null) pill(_nextExam!, onTap: () => setState(() => _tab = 2)),
                pill('ความสำคัญ: ${subject.importanceLabel} · ${subject.sessionsPerWeek} รอบ/สัปดาห์ ✎',
                    onTap: () => _changeSessions(subject)),
              ]),
            ]),
          ),
          const SizedBox(width: 12),
          // วงกลม % ความเข้าใจเฉลี่ย (สีตามระดับ ดี / พอได้ / ยังไม่ได้)
          SizedBox(
            width: 84,
            height: 84,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 84,
                height: 84,
                child: CircularProgressIndicator(
                  value: (avg ?? 0) / 100,
                  strokeWidth: 8,
                  color: ringColor,
                  backgroundColor: c.surface2,
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(avg == null ? '—' : '${avg.round()}%',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
                Text(levelText, style: TextStyle(fontSize: 10, color: c.muted)),
              ]),
            ]),
          ),
          ...actions,
        ],
      ),
    );
  }

  /// แท็บ ภาพรวม / บทเรียน / ตารางเรียน / ติว (เส้นใต้สีวิชา)
  Widget _tabStrip(BuildContext context, Subject subject) {
    final c = context.noir;
    final color = subjectColorOf(subject);
    const labels = ['ภาพรวม', 'บทเรียน', 'เวลาเรียน', 'ติว', 'เกรด'];
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      child: Wrap(children: [
        for (final (i, label) in labels.indexed)
          InkWell(
            onTap: () => setState(() => _tab = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: _tab == i ? color : Colors.transparent, width: 2)),
              ),
              child: Text(label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: _tab == i ? FontWeight.w600 : FontWeight.w400,
                    color: _tab == i ? c.text : c.muted,
                  )),
            ),
          ),
      ]),
    );
  }

  /// แท็บภาพรวม: 3 ช่องสรุป (บทเรียน · หน่วยกิต · ติว)
  Widget _overviewTiles(BuildContext context, Subject subject, List<Subtopic> topics) {
    final c = context.noir;
    final h = parseCreditHours(subject.credits);
    final assessed = topics.where((t) => t.scores.isNotEmpty).length;
    final flags = topics.where((t) => t.examFlag).length;
    Widget tile(String label, String value, String sub, {VoidCallback? onTap}) => Material(
          color: c.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.line)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 13, color: c.muted)),
                const SizedBox(height: 4),
                Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 4),
                Text(sub, style: TextStyle(fontSize: 13, color: c.muted)),
              ]),
            ),
          ),
        );
    final tiles = [
      tile('บทเรียน', '${_chapters.length} บท · ${topics.length} หัวข้อ', 'ประเมินแล้ว $assessed · ธงออกสอบ $flags',
          onTap: () => setState(() => _tab = 1)),
      tile('หน่วยกิต', subject.credits ?? '—',
          h == null ? 'ยังไม่มีหน่วยกิต · แตะเพื่อใส่' : 'ทฤษฎี ${h.theory} · ปฏิบัติ ${h.lab} · ศึกษาเอง ${h.self} ชม./สัปดาห์',
          onTap: h == null ? () => _editPlan(subject) : () => setState(() => _tab = 2)),
      tile('รอบติว', '${subject.sessionsPerWeek} รอบ/สัปดาห์', 'ความสำคัญ ${subject.importanceLabel} · ดูแผนติว',
          onTap: () => setState(() => _tab = 3)),
    ];
    return LayoutBuilder(builder: (context, size) {
      if (size.maxWidth < 640) {
        return Column(children: [
          for (final t in tiles) Padding(padding: const EdgeInsets.only(bottom: 10), child: t),
        ]);
      }
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, t) in tiles.indexed) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: t),
          ],
        ]),
      );
    });
  }

  /// คลิกกล่องวิชาในแผนผัง → เปิดรายละเอียดวิชานั้น
  void _openSubject(Subject s, {String from = 'map'}) {
    _subjectId = s.id;
    _yearView = null; // เปิดจากแผนผัง → ไปที่ปีของวิชานั้น
    _scope = 'year'; // รายชื่อซ้ายโชว์ทั้งปีของวิชานั้น
    _returnTo = from;
    _setMapView(false);
    _reload();
  }

  /// ย้อนกลับจากรายละเอียดวิชา: ไปแผนผัง (ปี/ภาคเดิม) หรือเปิดตารางเรียนทั้งสัปดาห์อีกครั้ง
  void _goBack() {
    final to = _returnTo;
    _returnTo = null;
    if (to == 'jump') {
      setState(() {});
      appBack.handle(); // shell พากลับเมนูเดิม (ปฏิทิน / วันนี้)
    } else if (to == 'week') {
      setState(() {});
      _openWeek();
    } else {
      _setMapView(true);
    }
  }

  /// คลิกขวา / กดค้างที่กล่องวิชา → เมนูตรงตำแหน่งเมาส์
  Future<void> _subjectMenu(Subject s, Offset at, {bool inDetail = false}) async {
    final chain = _mapSelectedId == s.id;
    final pick = await showContextMenuAt<String>(context, at, [
      ctxItem('open', Icons.open_in_new, 'เปิดวิชา'),
      if (!inDetail) ctxItem('chain', Icons.timeline, chain ? 'เลิกไฮไลต์สายวิชา' : 'ไฮไลต์สายวิชานี้'),
      ctxItem('color', Icons.palette_outlined, 'เปลี่ยนสีวิชา'),
      ctxItem('links', Icons.share_outlined, 'แก้เส้นเชื่อม'),
      ctxItem('plan', Icons.edit_calendar_outlined, 'แก้ รหัส / หน่วยกิต / ปี / ภาค'),
      ctxItem('rename', Icons.drive_file_rename_outline, 'เปลี่ยนชื่อ'),
      ctxItem('delete', Icons.delete_outline, 'ลบวิชา', danger: true),
    ]);
    if (!mounted) return;
    switch (pick) {
      case 'open':
        if (inDetail) {
          _subjectId = s.id;
          await _reload();
        } else {
          _openSubject(s);
        }
      case 'color':
        await _pickColor(s);
      case 'chain':
        setState(() => _mapSelectedId = chain ? null : s.id);
      case 'links':
        await _editLinks(s);
      case 'plan':
        await _editPlan(s);
      case 'rename':
        await _renameSubject(s);
      case 'delete':
        await _deleteSubject(s);
    }
  }

  /// ย้ายวิชาไปปี/เทอมในแผน + รหัส/หน่วยกิต
  Future<void> _editPlan(Subject subject) async {
    var year = subject.planYear ?? 1;
    var term = subject.planTerm ?? 1;
    final code = TextEditingController(text: subject.code ?? '');
    final credits = TextEditingController(text: subject.credits ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('จัดในแผน 4 ปี'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ปีที่'),
                Wrap(spacing: 6, children: [
                  for (var y = 1; y <= 6; y++)
                    ChoiceChip(
                        label: Text('$y'),
                        selected: y == year,
                        onSelected: (_) => setLocal(() => year = y)),
                ]),
                const SizedBox(height: 8),
                const Text('ภาคเรียน'),
                Wrap(spacing: 6, children: [
                  for (var t = 1; t <= 3; t++)
                    ChoiceChip(
                        label: Text(termLabel(t)),
                        selected: t == term,
                        onSelected: (_) => setLocal(() => term = t)),
                ]),
                TextField(
                    controller: code,
                    decoration: const InputDecoration(labelText: 'รหัสวิชา', hintText: '060233115')),
                TextField(
                    controller: credits,
                    decoration: const InputDecoration(labelText: 'หน่วยกิต', hintText: '3(2-2-5)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('บันทึก')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _repo!.setSubjectPlan(subject.id,
        code: code.text.trim(), credits: credits.text.trim(), year: year, term: term);
    await _reload();
  }

  /// สีประจำวิชา (ใช้ในไทม์ไลน์หาเวลาติว)
  Future<void> _pickColor(Subject subject) async {
    final current = subject.colorIndex ?? subject.id;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('สีวิชา · ${subject.name}'),
        content: Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 0; i < subjectPalette.length; i++)
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.pop(ctx, i),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: subjectPalette[i],
                  shape: BoxShape.circle,
                  border: i == current % subjectPalette.length
                      ? Border.all(color: Colors.white, width: 3)
                      : null,
                ),
              ),
            ),
        ]),
      ),
    );
    if (picked == null) return;
    await _repo!.setSubjectColor(subject.id, picked);
    await _reload();
  }

  Future<void> _deleteSubject(Subject subject) async {
    if (!await confirmDelete(context, subject.name)) return;
    await _repo!.deleteSubject(subject.id);
    _subjectId = null; // ให้ _reload เลือกวิชาแรกที่เหลือแทน
    await _reload();
  }

  Future<void> _renameChapter(Chapter chapter) async {
    final name = await askText(context,
        title: 'เปลี่ยนชื่อบท',
        label: 'ชื่อบท',
        initial: chapter.name,
        confirmLabel: 'บันทึก');
    if (name == null) return;
    await _repo!.renameChapter(chapter.id, name);
    await _reload();
  }

  Future<void> _chapterKind(Chapter chapter) async {
    final k = await showDialog<ChapterKind>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('ประเภทบท · ${chapter.name}'),
        children: [
          for (final (kind, detail) in const [
            (ChapterKind.theory, 'อ่าน · ทำความเข้าใจ · ทดสอบตัวเอง'),
            (ChapterKind.practice, 'ดูตัวอย่าง → ลงมือทำ · คละโจทย์'),
            (ChapterKind.mixed, 'ทฤษฎีครึ่งแรก → ลงมือทำครึ่งหลัง'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, kind),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(kind == chapter.kind
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(chapterKindLabel(kind)),
                subtitle: Text(detail),
              ),
            ),
        ],
      ),
    );
    if (k == null) return;
    await _repo!.setChapterKind(chapter.id, k);
    await _reload();
  }

  Future<void> _chapterStatus(Chapter chapter) async {
    final st = await showDialog<ChapterStatus>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('สถานะบท · ${chapter.name}'),
        children: [
          for (final s in ChapterStatus.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(s == chapter.status
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(chapterStatusLabel(s)),
              ),
            ),
        ],
      ),
    );
    if (st == null) return;
    await _repo!.setChapterStatus(chapter.id, st);
    await _reload();
  }

  Future<void> _addChapter() async {
    final name = await askText(context,
        title: 'เพิ่มบท',
        label: 'ชื่อบท',
        hint: 'เช่น บท ${_chapters.length + 1} · ...');
    if (name == null) return;
    await _repo!.addChapter(_subjectId!, name);
    await _reload();
  }

  Future<void> _addSubtopic(Chapter chapter) async {
    final name = await askText(context,
        title: 'เพิ่มหัวข้อย่อย', label: 'ชื่อหัวข้อย่อย', hint: chapter.name);
    if (name == null) return;
    await _repo!.addSubtopic(chapter.id, name);
    await _reload();
  }

  Future<void> _deleteChapter(Chapter chapter) async {
    if (!await confirmDelete(context, chapter.name)) return;
    await _repo!.deleteChapter(chapter.id);
    await _reload();
  }

  Future<void> _openSubtopic(Subtopic topic) async {
    final edit = await showSubtopicDialog(context, topic);
    if (edit == null || !mounted) return;
    final repo = _repo!;

    if (edit.delete) {
      if (!await confirmDelete(context, topic.name)) return;
      await repo.deleteSubtopic(topic.id);
    } else if (edit.history) {
      await showScoreHistory(context, repo, topic);
    } else if (edit.rename) {
      final name = await askText(context,
          title: 'เปลี่ยนชื่อหัวข้อย่อย',
          label: 'ชื่อหัวข้อย่อย',
          initial: topic.name,
          confirmLabel: 'บันทึก');
      if (name == null) return;
      await repo.renameSubtopic(topic.id, name);
    } else {
      if (edit.examFlag != topic.examFlag) {
        await repo.setExamFlag(topic.id, edit.examFlag);
      }
      if (edit.score != null) {
        await repo.addAssessment(topic.id, edit.score!);
        if (_mode == GradingMode.advanced) await _applyAdvancedRules(topic.id);
      }
    }
    await _reload();
  }

  /// [Advanced] หลังบันทึกคะแนน: เช็ก 2 เหตุการณ์ที่ค่าเฉลี่ยรวมหลอกตา
  /// 1) เคยตก → เขียว 2 รอบติด  2) เคยเขียว → ตก 2 รอบติด
  /// ทำตามค่าตั้งค่า หรือถามผู้ใช้ (พร้อมติ๊ก "ไม่ต้องถามอีก")
  Future<void> _applyAdvancedRules(int subtopicId) async {
    final repo = _repo!;
    Subtopic? topic;
    for (final ch in await repo.chapters(_subjectId!)) {
      for (final t in ch.subtopics) {
        if (t.id == subtopicId) topic = t;
      }
    }
    if (topic == null) return;

    final RuleText rule;
    if (needsGreenDecision(topic)) {
      rule = greenRule;
    } else if (needsRedDecision(topic)) {
      rule = redRule;
    } else {
      return;
    }

    final saved = rule.choiceFrom(await repo.getSetting(rule.key));
    RuleAnswer answer;
    if (saved == RuleChoice.ask) {
      if (!mounted) return;
      final decision = rule == greenRule
          ? await askGreenTwice(context, topic)
          : await askRedTwice(context, topic);
      if (decision == null) return; // ปิดกล่องเฉย ๆ = ยังไม่ตัดสินใจ
      answer = decision.answer;
      if (decision.remember) {
        await repo.setSetting(
          rule.key,
          (answer == RuleAnswer.recent ? RuleChoice.recent : RuleChoice.average)
              .name,
        );
      }
    } else {
      answer =
          saved == RuleChoice.recent ? RuleAnswer.recent : RuleAnswer.average;
    }

    switch (answer) {
      case RuleAnswer.recent:
        // เริ่มนับใหม่ตั้งแต่รอบแรกของ 2 รอบล่าสุด (ก่อนหน้านั้นเป็นโมฆะ)
        await repo.resetHistoryFrom(
            topic.id, topic.scores[topic.scores.length - 2].at);
      case RuleAnswer.average:
        break; // ไม่ต้องทำอะไร
      case RuleAnswer.wrongScore:
        if (mounted) await showScoreHistory(context, repo, topic);
    }
  }

  Future<void> _openSettings() => showStudySettings(context, _repo!);

  /// กดยุบ / ขยาย แล้วบันทึกทันที (ปิดเปิดแอปก็ยังเป็นแบบเดิม)
  Future<void> _setCollapsed(Set<String> keys) async {
    setState(() => _collapsed = keys);
    await _repo!.setSetting(_collapsedKey, keys.join(','));
  }

  void _toggle(String key) => _setCollapsed(
      _collapsed.contains(key) ? ({..._collapsed}..remove(key)) : {..._collapsed, key});

  /// สลับ แผนผัง ↔ รายวิชา
  Widget _viewSwitch() => Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (!_mapView && _returnTo != null)
            TextButton.icon(
              onPressed: _goBack,
              icon: const Icon(Icons.arrow_back),
              label: Text(switch (_returnTo) { 'week' => 'กลับตารางเรียน', 'jump' => 'กลับหน้าเดิม', _ => 'กลับแผน 4 ปี' }),
            ),
          SegmentedButton<bool>(
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: true, icon: Icon(Icons.account_tree_outlined), label: Text('แผน 4 ปี')),
            ButtonSegment(value: false, icon: Icon(Icons.menu_book_outlined), label: Text('รายวิชา')),
          ],
          selected: {_mapView},
          showSelectedIcon: false,
          onSelectionChanged: (v) => _setMapView(v.first),
          ),
          OutlinedButton.icon(
            onPressed: _openWeek,
            icon: const Icon(Icons.calendar_view_week_outlined),
            label: const Text('ตารางเรียนทั้งสัปดาห์'),
          ),
          OutlinedButton.icon(
            onPressed: _openGpa,
            icon: const Icon(Icons.school_outlined),
            label: const Text('เกรดและหน่วยกิต'),
          ),
        ],
      );

  /// เกรดและหน่วยกิตทุกเทอม · เปิดที่เทอมปัจจุบันถ้ามี
  void _openGpa() {
    final t = _currentTerm;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GpaPage(initialTerm: t == null ? null : (t.year, t.term)),
    ));
  }

  /// ตารางเรียนของทุกวิชา · "เปิดวิชา" จากคาบ → กลับมาหน้ารายวิชาของวิชานั้น
  void _openWeek() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (ctx) => WeekTimetablePage(
        onOpenSubject: (s) {
          Navigator.of(ctx).pop();
          _openSubject(s, from: 'week');
        },
      ),
    ));
  }

  Widget _buildMap(BuildContext context) {
    final c = context.noir;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      children: [
        _viewSwitch(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                  _mapYear == null
                      ? 'การเรียน'
                      : _mapTerm == null
                          ? 'การเรียน · ปี $_mapYear'
                          : 'การเรียน · ปี $_mapYear · ${_mapTerm == 3 ? 'ฤดูร้อน' : 'ภาค $_mapTerm'}',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: c.text)),
            ),
            FilledButton.icon(
              onPressed: _addSubject,
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มวิชา'),
            ),
            PopupMenuButton<String>(
              tooltip: 'ตัวเลือก',
              onSelected: _onPageMenu,
              itemBuilder: (_) => _pageMenuItems,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
        Text(
            _mapSelectedId == null
                ? (_mapYear == null
                    ? 'คลิกหัวปี / หัวภาค = ดูเฉพาะส่วนนั้น · คลิกวิชา = เปิด · คลิกขวา = ตัวเลือก'
                    : 'คลิกวิชา = เปิดดูบท คะแนน ตารางเรียน · คลิกขวา (กดค้าง) = ตัวเลือก · ชี้ = ดูสายวิชา')
                : 'ไฮไลต์สาย "${_subjects.where((s) => s.id == _mapSelectedId).firstOrNull?.name ?? ''}" · คลิกขวาอีกครั้งเพื่อเลิก',
            style: TextStyle(color: c.muted, fontSize: 13)),
            if (_subjects.where((s) => s.id == _mapSelectedId).firstOrNull case final sel?)
              TextButton.icon(
                onPressed: () => _editLinks(sel),
                icon: const Icon(Icons.timeline, size: 18),
                label: const Text('แก้เส้นเชื่อม'),
              ),
            // สีกล่อง: เริ่มต้น / ตามวิชา (สีเดียวกับปฏิทิน ตารางเรียน หน้าวิชา)
            SegmentedButton<bool>(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.crop_square, size: 16), label: Text('สีเริ่มต้น')),
                ButtonSegment(value: true, icon: Icon(Icons.palette_outlined, size: 16), label: Text('สีวิชา')),
              ],
              selected: {_mapColorBySubject},
              onSelectionChanged: (v) {
                setState(() => _mapColorBySubject = v.first);
                _repo!.setSetting(_mapColorKey, v.first ? 'subject' : 'default');
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        CurriculumMap(
          subjects: _subjects,
          progress: _progress,
          selectedId: _mapSelectedId,
          onOpen: _openSubject,
          onContextMenu: _subjectMenu,
          colorBySubject: _mapColorBySubject,
          focusYear: _mapYear,
          focusTerm: _mapTerm,
          links: _links,
          onFocus: (y, t) => setState(() {
            _mapYear = y;
            _mapTerm = t;
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_mapView) return _buildMap(context);
    return _buildDetail(context, c);
  }

  Widget _buildDetail(BuildContext context, NoirColors c) {
    final subject = _subject;
    final allTopics = [for (final ch in _chapters) ...ch.subtopics];
    final review = reviewOrder(allTopics, mode: _mode);
    final exam = examTopics(allTopics, _mode);
    final chapterNames = {
      for (final ch in _chapters) ch.chapter.id: ch.chapter.name,
    };

    // ---- เนื้อหาแต่ละแท็บ ----
    List<Widget> overviewTab(Subject subject) => [
          _overviewTiles(context, subject, allTopics),
          if (review.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ReviewBox(
              topics: review,
              chapterNames: chapterNames,
              collapsed: _collapsed.contains('review'),
              onToggle: () => _toggle('review'),
            ),
          ],
          if (exam.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ExamBox(
              topics: exam,
              chapterNames: chapterNames,
              mode: _mode,
              collapsed: _collapsed.contains('exam'),
              onToggle: () => _toggle('exam'),
            ),
          ],
          if (review.isEmpty && exam.isEmpty) ...[
            const SizedBox(height: 12),
            Text('ยังไม่มีหัวข้อที่ต้องทวน · ประเมินหัวข้อในแท็บ "บทเรียน" ก่อน',
                style: TextStyle(color: c.muted)),
          ],
        ];

    List<Widget> chaptersTab() => [
          const _Legend(),
          const SizedBox(height: 12),
          // สวิตช์โหมด EZ / Advanced (จำไว้ในฐานข้อมูล ทุกวิชาใช้ร่วมกัน)
          Row(
            children: [
              SegmentedButton<GradingMode>(
              segments: const [
                ButtonSegment(value: GradingMode.ez, label: Text('EZ')),
                ButtonSegment(
                    value: GradingMode.advanced, label: Text('Advanced')),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: (selected) async {
                await _repo!.setGradingMode(selected.first);
                await _reload();
              },
              ),
              if (_mode == GradingMode.advanced)
                IconButton(
                  tooltip: 'ตั้งค่าโหมด Advanced',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: _openSettings,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _mode == GradingMode.ez
                ? 'EZ: สีและ % = คะแนนล่าสุด'
                : 'Advanced: สีและ % = ค่าเฉลี่ยทุกรอบ · เคยตกต้องเขียว 2 รอบติดถึงผ่าน',
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
          const SizedBox(height: 8),
          if (_chapters.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Builder(builder: (context) {
                final chapterKeys = {for (final ch in _chapters) 'ch${ch.chapter.id}'};
                final allCollapsed = chapterKeys.every(_collapsed.contains);
                return TextButton.icon(
                  onPressed: () => _setCollapsed(allCollapsed
                      ? _collapsed.difference(chapterKeys)
                      : _collapsed.union(chapterKeys)),
                  icon: Icon(allCollapsed ? Icons.unfold_more : Icons.unfold_less),
                  label: Text(allCollapsed ? 'ขยายทุกบท' : 'ยุบทุกบท'),
                );
              }),
            ),
          for (final ch in _chapters) ...[
            _ChapterCard(
              collapsed: _collapsed.contains('ch${ch.chapter.id}'),
              onToggle: () => _toggle('ch${ch.chapter.id}'),
              data: ch,
              onAddSubtopic: () => _addSubtopic(ch.chapter),
              onRename: () => _renameChapter(ch.chapter),
              onDelete: () => _deleteChapter(ch.chapter),
              onKind: () => _chapterKind(ch.chapter),
              onStatus: () => _chapterStatus(ch.chapter),
              onOpenSubtopic: _openSubtopic,
              mode: _mode,
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: _addChapter,
            icon: const Icon(Icons.add),
            label: const Text('เพิ่มบท'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: c.text,
              side: BorderSide(color: c.line2),
            ),
          ),
        ];

    List<Widget> headerMenu(Subject subject) => [
              PopupMenuButton<String>(
                tooltip: 'ตัวเลือกวิชา',
                onSelected: (v) {
                  switch (v) {
                    case 'rename':
                      _renameSubject(subject);
                    case 'importance':
                      _changeImportance(subject);
                    case 'sessions':
                      _changeSessions(subject);
                    case 'demo' || 'dupes' || 'terms':
                      _onPageMenu(v);
                    case 'plan':
                      _editPlan(subject);
                    case 'color':
                      _pickColor(subject);
                    default:
                      _deleteSubject(subject);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'rename', child: Text('เปลี่ยนชื่อวิชา')),
                  const PopupMenuItem(value: 'importance', child: Text('เปลี่ยนความสำคัญ')),
                  const PopupMenuItem(value: 'sessions', child: Text('รอบติวต่อสัปดาห์')),
                  const PopupMenuItem(value: 'plan', child: Text('ปี / เทอม ในแผน 4 ปี')),
                  const PopupMenuItem(value: 'color', child: Text('สีวิชา')),
                  const PopupMenuItem(value: 'delete', child: Text('ลบวิชา')),
                  const PopupMenuDivider(),
                  ..._pageMenuItems,
                ],
              ),
    ];

    final content = <Widget>[
      _viewSwitch(),
      const SizedBox(height: 16),
      if (subject == null)
        Text('ยังไม่มีวิชา · กด "เพิ่มวิชา" ในแผน 4 ปี', style: TextStyle(color: c.muted))
      else ...[
        _subjectHeader(context, subject, headerMenu(subject)),
        const SizedBox(height: 12),
        _tabStrip(context, subject),
        const SizedBox(height: 16),
        ...switch (_tab) {
          1 => chaptersTab(),
          2 => [ClassScheduleCard(subject: subject, onEditPlan: () => _editPlan(subject))],
          3 => [TutorCard(subject: subject, chapters: _chapters)],
          4 => [GradeCard(subject: subject)],
          _ => overviewTab(subject),
        },
      ],
    ];

    // จอกว้าง: รายชื่อวิชาซ้าย (แบบ B) · จอแคบ: ชิปเลือกปีด้านบน (ที่เดิม)
    return LayoutBuilder(builder: (context, size) {
      final wide = size.maxWidth >= 1000;
      final list = ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        children: [
          if (!wide) ...[
            _yearPicker(context, subject),
            const SizedBox(height: 12),
          ],
          ...content,
        ],
      );
      if (!wide) return list;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 300, child: _subjectSidebar(context, subject)),
          VerticalDivider(width: 1, color: c.line),
          Expanded(child: list),
        ],
      );
    });
  }

}

/// การ์ดของ 1 บท: หัวบท + หัวข้อย่อยทุกข้อ
class _ChapterCard extends StatelessWidget {
  const _ChapterCard({
    required this.data,
    required this.onAddSubtopic,
    required this.onRename,
    required this.onDelete,
    required this.onKind,
    required this.onStatus,
    required this.onOpenSubtopic,
    required this.mode,
    required this.collapsed,
    required this.onToggle,
  });

  final ChapterWithTopics data;
  final GradingMode mode;
  final bool collapsed; // true = ซ่อนหัวข้อย่อย เหลือแค่หัวบท
  final VoidCallback onToggle;
  final VoidCallback onAddSubtopic;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onKind;
  final VoidCallback onStatus;
  final ValueChanged<Subtopic> onOpenSubtopic;

  Future<void> _menuAt(BuildContext context, Offset at) async {
    final v = await showContextMenuAt<String>(context, at, [
      ctxItem('add', Icons.add, 'เพิ่มหัวข้อย่อย'),
      ctxItem('rename', Icons.drive_file_rename_outline, 'เปลี่ยนชื่อบท'),
      ctxItem('kind', Icons.category_outlined, 'ประเภทบท: ทฤษฎี / ปฏิบัติ / ผสม'),
      ctxItem('status', Icons.flag_outlined, 'สถานะบท'),
      ctxItem('delete', Icons.delete_outline, 'ลบบทนี้', danger: true),
    ]);
    switch (v) {
      case 'add':
        onAddSubtopic();
      case 'rename':
        onRename();
      case 'kind':
        onKind();
      case 'status':
        onStatus();
      case 'delete':
        onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    var pressAt = Offset.zero;
    final c = context.noir;
    final topics = data.subtopics;
    final assessed = topics.where((t) => t.latestScore != null).length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle, // แตะหัวบท = ยุบ / ขยาย
            // คลิกขวา / กดค้าง = เมนูเดียวกับปุ่ม ⋮ แต่เด้งตรงเมาส์
            onSecondaryTapUp: (d) => _menuAt(context, d.globalPosition),
            onTapDown: (d) => pressAt = d.globalPosition,
            onLongPress: () => _menuAt(context, pressAt),
            child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(
              children: [
                Icon(collapsed ? Icons.chevron_right : Icons.expand_more,
                    color: c.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data.chapter.name,
                          style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                      Text(
                        topics.isEmpty
                            ? 'ยังไม่มีหัวข้อย่อย'
                            : 'ประเมินแล้ว $assessed/${topics.length} หัวข้อ',
                        style: TextStyle(fontSize: 13, color: c.muted),
                      ),
                      Text(
                        '${chapterKindLabel(data.chapter.kind)} · ${chapterStatusLabel(data.chapter.status)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: data.chapter.status == ChapterStatus.learning ? c.accent : c.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'ตัวเลือกบท',
                  onSelected: (v) {
                    switch (v) {
                      case 'add':
                        onAddSubtopic();
                      case 'rename':
                        onRename();
                      case 'kind':
                        onKind();
                      case 'status':
                        onStatus();
                      default:
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'add', child: Text('เพิ่มหัวข้อย่อย')),
                    PopupMenuItem(value: 'rename', child: Text('เปลี่ยนชื่อบท')),
                    PopupMenuItem(value: 'kind', child: Text('ประเภทบท: ทฤษฎี / ปฏิบัติ / ผสม')),
                    PopupMenuItem(value: 'status', child: Text('สถานะบท')),
                    PopupMenuItem(value: 'delete', child: Text('ลบบทนี้')),
                  ],
                ),
              ],
            ),
          ),
          ),
          if (!collapsed)
          for (final t in topics) ...[
            Divider(height: 1, color: c.line),
            _SubtopicRow(topic: t, mode: mode, onTap: () => onOpenSubtopic(t)),
          ],
        ],
      ),
    );
  }
}

/// แถวหัวข้อย่อย: ชื่อ + ป้าย + แถบคะแนน + %
class _SubtopicRow extends StatelessWidget {
  const _SubtopicRow({
    required this.topic,
    required this.mode,
    required this.onTap,
  });

  final Subtopic topic;
  final GradingMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final score = shownScore(topic, mode); // EZ = ล่าสุด · Advanced = เฉลี่ย
    final color = switch (masteryOf(score)) {
      MasteryLevel.good => c.good,
      MasteryLevel.warn => c.warn,
      MasteryLevel.bad => c.bad,
      MasteryLevel.none => c.line2,
    };
    // จอแคบ (มือถือ / หน้าต่างเล็ก) → แถบคะแนนสั้นลง ชื่อหัวข้อจะได้ไม่โดนบีบ
    final barWidth = MediaQuery.sizeOf(context).width < 600 ? 64.0 : 160.0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(topic.name, style: TextStyle(fontSize: 15, color: c.text)),
                  if (topic.examFlag)
                    _Tag(
                      text: 'ออกสอบ',
                      icon: Icons.star,
                      border: c.flag,
                      fg: c.flagText,
                    ),
                  if (showRecheck(topic, mode))
                    _Tag(text: 'เช็กซ้ำ', bg: c.amberBg, fg: c.amberText),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: barWidth,
              height: 8,
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (score ?? 0) / 100,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                score == null ? '—' : '$score%',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 14, color: score == null ? c.muted : c.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// กล่อง "ต้องทวนก่อนสอบ": รายการหัวข้อแยกบรรทัด เรียงจากเร่งสุด (ข้อ 1) ลงไป
/// โชว์แค่ชื่อหัวข้อ + อยู่บทไหน ไม่โชว์คะแนน (คะแนนดูได้ในการ์ดบทด้านบน)
class _ReviewBox extends StatelessWidget {
  const _ReviewBox({
    required this.topics,
    required this.chapterNames,
    required this.collapsed,
    required this.onToggle,
  });

  final List<Subtopic> topics;
  final Map<int, String> chapterNames; // chapterId → ชื่อบท
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: c.amberBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BoxHeader(
            text: 'ต้องทวนก่อนสอบ · ${topics.length} หัวข้อ',
            color: c.amberText,
            collapsed: collapsed,
            onToggle: onToggle,
          ),
          if (!collapsed) const SizedBox(height: 8),
          if (!collapsed)
          for (var i = 0; i < topics.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text('${i + 1}.',
                        style: TextStyle(color: c.amberText)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(topics[i].name,
                            style: TextStyle(fontSize: 15, color: c.text)),
                        Text(
                          chapterNames[topics[i].chapterId] ?? '',
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                      ],
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

/// คำอธิบายสี
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    Widget dot(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, color: c.muted)),
          ],
        );

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        dot(c.good, 'ดี >80%'),
        dot(c.warn, 'พอได้ 60–80%'),
        dot(c.bad, 'ยังไม่ได้ <60%'),
        dot(c.line2, 'ยังไม่ประเมิน'),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.text,
    required this.fg,
    this.bg,
    this.border,
    this.icon,
  });

  final String text;
  final Color fg;
  final Color? bg;
  final Color? border;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 3),
          ],
          Text(text, style: TextStyle(fontSize: 12, color: fg)),
        ],
      ),
    );
  }
}

/// กล่อง "อาจออกสอบ": ทุกหัวข้อที่ติดดาว ไม่สนว่าคะแนนเท่าไหร่
/// โชว์คะแนน + สี เพื่อดูภาพรวมก่อนสอบ (ต่างจากกล่องทวนที่บอกแค่ "ต้องทำอะไร")
class _ExamBox extends StatelessWidget {
  const _ExamBox({
    required this.topics,
    required this.chapterNames,
    required this.mode,
    required this.collapsed,
    required this.onToggle,
  });

  final List<Subtopic> topics;
  final Map<int, String> chapterNames;
  final GradingMode mode;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.flag),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BoxHeader(
            icon: Icons.star,
            text: 'อาจออกสอบ · ${topics.length} หัวข้อ',
            color: c.flagText,
            collapsed: collapsed,
            onToggle: onToggle,
          ),
          if (!collapsed) const SizedBox(height: 8),
          if (!collapsed)
          for (final t in topics)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.name,
                            style: TextStyle(fontSize: 15, color: c.text)),
                        Text(chapterNames[t.chapterId] ?? '',
                            style: TextStyle(fontSize: 12, color: c.muted)),
                      ],
                    ),
                  ),
                  _ScoreDot(score: shownScore(t, mode)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// จุดสี + % เล็ก ๆ (ใช้ในกล่องอาจออกสอบ)
class _ScoreDot extends StatelessWidget {
  const _ScoreDot({required this.score});

  final int? score;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final color = switch (masteryOf(score)) {
      MasteryLevel.good => c.good,
      MasteryLevel.warn => c.warn,
      MasteryLevel.bad => c.bad,
      MasteryLevel.none => c.line2,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 44,
          child: Text(score == null ? '—' : '$score%',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 14, color: c.text)),
        ),
      ],
    );
  }
}

/// หัวกล่องท้ายหน้า: แตะเพื่อยุบ / ขยาย (ลูกศรอยู่ขวา)
class _BoxHeader extends StatelessWidget {
  const _BoxHeader({
    required this.text,
    required this.color,
    required this.collapsed,
    required this.onToggle,
    this.icon,
  });

  final String text;
  final Color color;
  final bool collapsed;
  final VoidCallback onToggle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(text,
                  style: TextStyle(fontWeight: FontWeight.w600, color: color)),
            ),
            Icon(collapsed ? Icons.expand_more : Icons.expand_less,
                color: color),
          ],
        ),
      ),
    );
  }
}
