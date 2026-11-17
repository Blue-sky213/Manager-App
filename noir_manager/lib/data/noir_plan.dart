/// แผนของนัวร์ (รอบ 10C · อนุมัติ 17 พ.ย. 2569) + ล้างแล้วเริ่มใหม่
///
/// - งาน mecsteam จ–ส 08:00–17:00 · ไลฟ์ จ/พ/ศ/ส 20:00–22:30 · อา 19:00–21:30
/// - IELTS (เป้า Band 6.5 · 6 เดือน) · DaVinci (ตัดคลิป 1 ชม. ≤ 1:30) · Canva (ปก ≤ 30 นาที) · อ่านหนังสือ 30′ ทุกวัน
/// - เว็บ mecsteam.com: เหลือ ใส่ภาพ → รายละเอียด → ข้อมูล → ทดสอบ → Deploy
/// - กดซ้ำได้: ของที่มีชื่อเดียวกันอยู่แล้วจะข้าม (ไม่ซ้อน)
library;

import '../calendar/calendar_models.dart';
import '../calendar/calendar_repository.dart';
import '../skills/skill_lessons.dart';
import '../skills/skill_models.dart';
import '../work/project_models.dart';
import 'study_repository.dart';

/// ผลการล้าง
typedef ResetResult = ({int activities, int subjects, int terms, int holidays});

/// ลบกิจกรรมทั้งหมด (รวมคาบเรียน) + วิชา/แผน 4 ปี + เทอม + วันหยุด
/// ไม่แตะ: สติกเกอร์ · เช็กอิน · หมวด · เงิน · โปรเจกต์ · สกิล · ตั้งค่า (ต้องสำรองก่อนเรียก — หน้าตั้งค่าทำให้)
Future<ResetResult> resetForFreshStart(CalendarRepository cal, StudyRepository study) async {
  final acts = await cal.activityIds();
  for (final id in acts) {
    await cal.deleteActivity(id);
  }
  final subs = await study.subjects();
  for (final s in subs) {
    await study.deleteSubject(s.id);
  }
  final terms = await cal.terms();
  for (final t in terms) {
    await cal.deleteTerm(t.id);
  }
  final hols = await cal.holidays();
  for (final h in hols) {
    await cal.removeHoliday(h.day);
  }
  return (activities: acts.length, subjects: subs.length, terms: terms.length, holidays: hols.length);
}

/// ผลการใส่แผน (นับเฉพาะที่เพิ่มใหม่)
typedef PlanResult = ({int activities, int skills, int tasks});

/// 1 งานซ้ำในแผน: ชื่อ · หมวด · วัน (1 = จันทร์) · เริ่ม (นาที) · ยาว (นาที) · สกิลที่ผูก · ยืดหยุ่น
typedef _Slot = (String name, String cat, Set<int> days, int start, int minutes, String? skill, bool flexible);

const _slots = <_Slot>[
  // แยกเช้า/บ่าย เพื่อให้พักเที่ยง (คำศัพท์) ไม่ชนกับงาน
  ('งาน · mecsteam', 'งาน', {1, 2, 3, 4, 5, 6}, 8 * 60, 4 * 60, null, false),
  ('งาน · mecsteam (บ่าย)', 'งาน', {1, 2, 3, 4, 5, 6}, 13 * 60, 4 * 60, null, false),
  ('IELTS · คำศัพท์ 10 คำ', 'เรียนเอง', {1, 2, 3, 4, 5, 6}, 12 * 60 + 15, 30, 'IELTS', true),
  ('IELTS · Listening', 'เรียนเอง', {1}, 18 * 60 + 45, 60, 'IELTS', true),
  ('IELTS · Writing', 'เรียนเอง', {3}, 18 * 60 + 45, 60, 'IELTS', true),
  ('IELTS · Grammar + ทวน', 'เรียนเอง', {5}, 18 * 60 + 45, 60, 'IELTS', true),
  ('IELTS · Reading', 'เรียนเอง', {2}, 19 * 60, 90, 'IELTS', true),
  ('IELTS · Speaking', 'เรียนเอง', {4}, 19 * 60, 90, 'IELTS', true),
  ('IELTS · ข้อสอบเก่า / Mock', 'เรียนเอง', {7}, 9 * 60, 150, 'IELTS', true),
  ('ฝึก · DaVinci Resolve', 'เรียนเอง', {2, 4}, 20 * 60 + 30, 60, 'DaVinci Resolve', true),
  ('ฝึก · DaVinci (ก่อนไลฟ์)', 'เรียนเอง', {6}, 18 * 60 + 45, 60, 'DaVinci Resolve', true),
  ('ฝึก · DaVinci ตัด Highlight ไลฟ์ (จับเวลา)', 'เรียนเอง', {7}, 13 * 60 + 30, 120, 'DaVinci Resolve', true),
  ('ฝึก · Canva', 'เรียนเอง', {2, 4}, 21 * 60 + 30, 30, 'Canva', true),
  ('ฝึก · Canva ปกไลฟ์', 'เรียนเอง', {7}, 15 * 60 + 30, 30, 'Canva', true),
  ('ไลฟ์ · Noir Lev', 'สตรีม', {1, 3, 5, 6}, 20 * 60, 150, null, false),
  ('ไลฟ์ · Noir Lev (อาทิตย์)', 'สตรีม', {7}, 19 * 60, 150, null, true),
  ('อ่านหนังสือ', 'เรียนเอง', {1, 2, 3, 4, 5, 6, 7}, 22 * 60 + 45, 30, null, true),
];

/// ชื่องานทั้งหมดในแผน (ไว้เทส / ตรวจ)
List<String> get noirPlanNames => [for (final s in _slots) s.$1];

/// สกิล: สาย · ไอคอนสาย · สี · สกิล · ไอคอน (บท + หัวข้อ มาจากสารบัญเรียนเอง · รอบ 13)
const _skills = [
  ('ภาษา', '🗣️', 'sky', 'IELTS', '🇬🇧'),
  ('ตัดต่อ', '🎬', 'purple', 'DaVinci Resolve', '🎬'),
  ('ออกแบบ', '🎨', 'pink', 'Canva', '🎨'),
];

Future<PlanResult> applyNoirPlan(CalendarRepository cal, DateTime today, {int months = 6}) async {
  final day0 = dayOnly(today);
  final end = DateTime(day0.year, day0.month + months, day0.day);

  // หมวด: ใช้ของเดิมถ้ามีชื่อนี้ ไม่มีก็สร้าง
  final cats = [...await cal.categories()];
  Future<int> cat(String name, String color, String icon, String group) async {
    final hit = cats.where((c) => c.name == name).firstOrNull;
    if (hit != null) return hit.id;
    final id = await cal.addCategory(ActivityCategory(id: 0, name: name, colorKey: color, icon: icon, statsGroup: group));
    cats.add(ActivityCategory(id: id, name: name, colorKey: color, icon: icon, statsGroup: group));
    return id;
  }

  final catIds = {
    'งาน': await cat('งาน', 'amber', '💼', 'work'),
    'สตรีม': await cat('สตรีม', 'purple', '🎮', 'other'),
    'เรียนเอง': await cat('เรียนเอง', 'sky', '📘', 'study'),
  };

  // สกิล + สาย (ชื่อซ้ำ = ใช้ของเดิม · DaVinci ที่มีอยู่แล้วก็ใช้ต่อ)
  final r = cal.skillRepo;
  final branches = await r.branches();
  final skills = await r.skills();
  final skillIds = <String, int>{};
  var newSkills = 0;
  for (final (bName, bIcon, color, sName, sIcon) in _skills) {
    final b = branches.where((x) => x.name == bName).firstOrNull?.id ??
        await r.saveBranch(SkillBranch(name: bName, icon: bIcon, colorKey: color, sort: branches.length + skillIds.length));
    final key = sName.split(' ').first.toLowerCase();
    final old = skills.where((s) => s.name.toLowerCase().contains(key)).firstOrNull;
    if (old != null) {
      skillIds[sName] = old.id;
      if (old.branchId == null) await r.saveSkill(old.copyWith(branchId: b));
      continue;
    }
    final id = await r.saveSkill(Skill(name: sName, icon: sIcon, branchId: b, colorKey: color, startedAt: day0));
    skillIds[sName] = id;
    newSkills++;
    switch (sName) {
      case 'IELTS':
        await r.saveGoal(SkillGoal(skillId: id, kind: GoalKind.count, title: 'คำศัพท์ใหม่', unit: 'คำ', target: 10, streak: 14));
        await r.saveGoal(SkillGoal(skillId: id, kind: GoalKind.milestone, title: 'IELTS Band 6.5 ใน 6 เดือน', steps: const [
          GoalStep('เดือน 1 · พื้นฐาน + วัดระดับ'),
          GoalStep('เดือน 2 · Listening + Reading'),
          GoalStep('เดือน 3 · Writing + Speaking'),
          GoalStep('เดือน 4 · ข้อสอบเก่า 1 ชุด/สัปดาห์'),
          GoalStep('เดือน 5 · แก้จุดอ่อน'),
          GoalStep('เดือน 6 · Mock ได้ 6.5 สองครั้ง → สมัครสอบ'),
        ]));
      case 'DaVinci Resolve':
        await r.saveGoal(SkillGoal(skillId: id, kind: GoalKind.faster, title: 'ตัดคลิป 1 ชม.', unit: 'นาที', target: 90));
      case 'Canva':
        await r.saveGoal(SkillGoal(skillId: id, kind: GoalKind.faster, title: 'ปกไลฟ์ 1 ใบ', unit: 'นาที', target: 30));
    }
  }
  if (!branches.any((b) => b.name == 'อ่าน')) {
    await r.saveBranch(SkillBranch(name: 'อ่าน', icon: '📚', colorKey: 'mint', sort: branches.length + 3));
  }
  // บท + หัวข้อ + ลิงก์คลิป ของ IELTS / DaVinci / Canva
  await applyLessonPresets(r);

  // งานซ้ำในปฏิทิน (ชื่อซ้ำ = ข้าม)
  final have = <String>{};
  for (final id in await cal.activityIds()) {
    have.add((await cal.activity(id)).name);
  }
  var newActs = 0;
  for (final (name, c, days, start, minutes, skill, flexible) in _slots) {
    if (have.contains(name)) continue;
    final id = await cal.addActivity(NewActivity(
      name: name,
      categoryId: catIds[c]!,
      importance: 2,
      timed: true,
      day: day0,
      startMinute: start,
      durationMin: minutes,
      repeat: RepeatKind.weekly,
      weekdays: days,
      endDate: end,
      flexible: flexible,
    ));
    newActs++;
    if (skill != null) await r.linkActivity(skillIds[skill]!, id);
  }

  // โปรเจกต์เว็บ mecsteam.com (มีอยู่แล้ว = เติมขั้นที่ขาด)
  final w = cal.workRepo;
  final pjs = await w.projects();
  final old = pjs.where((p) => p.name.toLowerCase().contains('mecsteam')).firstOrNull;
  final pid = old?.id ??
      await w.saveProject(Project(
          name: 'เว็บ mecsteam.com', client: 'MECSTEAM', type: 'web', status: ProjectStatus.doing, start: day0, due: _d(day0, 21)));
  final tasks = await w.tasks(pid);
  var newTasks = 0;
  for (final (title, add, done) in [
    ('เก็บความต้องการ + Wireframe (Figma)', 0, true),
    ('ออกแบบ + เขียนหน้าเว็บ', 0, true),
    ('ใส่ภาพผลงาน 4 หมวด (เครื่องจักร · ท่อ · ออกแบบ · Heatpipe)', 7, false),
    ('เขียนรายละเอียดผลงานแต่ละชิ้น', 14, false),
    ('ข้อมูลบริษัท + ติดต่อ (ที่อยู่ · Email · LINE · Maps)', 18, false),
    ('ทดสอบมือถือ + จอ 1920', 20, false),
    ('Deploy ขึ้น mecsteam.com', 21, false),
  ]) {
    if (tasks.any((t) => t.title == title)) continue;
    await w.saveTask(ProjectTask(projectId: pid, title: title, due: done ? null : _d(day0, add), done: done));
    newTasks++;
  }
  return (activities: newActs, skills: newSkills, tasks: newTasks);
}

DateTime _d(DateTime d, int add) => DateTime(d.year, d.month, d.day + add);
