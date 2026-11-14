/// ข้อมูลตัวอย่าง (สมมุติ): ปี 1 เทอม 1 หลักสูตรวิศวกรรมสารสนเทศและเครือข่าย
///
/// โครงเทอม: 13 สัปดาห์ (~3 เดือน)
///   สัปดาห์ 1–6 เรียน → สัปดาห์ 7 สอบกลางภาค → สัปดาห์ 8–12 เรียน → สัปดาห์ 13 สอบปลายภาค
/// เนื้อหาบท/หัวข้อย่อยเป็นการคาดเดาจากชื่อวิชา ไม่ใช่ประมวลรายวิชาจริง
library;

import '../study/grading.dart';
import '../calendar/calendar_models.dart';
import '../calendar/calendar_repository.dart';
import 'study_models.dart';
import 'study_repository.dart';

class DemoChapter {
  const DemoChapter(this.name, this.topics, {this.flagged = const {}});
  final String name;
  final List<String> topics;

  /// index ของหัวข้อย่อยที่ติดธง "อาจออกสอบ"
  final Set<int> flagged;
}

/// คาบตัวอย่าง: ตามกฎจำลอง (timetable_sim.dart) คาบละ ≤ 2 ชม. · ทฤษฎี/ปฏิบัติแยกคาบ · วิชาละ ≤ 4 ชม./สัปดาห์
class DemoClass {
  const DemoClass(this.weekday, this.start, this.minutes, [this.type]);
  final int weekday; // 1 = จันทร์
  final int start; // นาทีนับจากเที่ยงคืน
  final int minutes;
  final ClassType? type;
}

class DemoSubject {
  const DemoSubject({
    required this.code,
    required this.name,
    required this.credits,
    required this.importance,
    required this.sessions,
    required this.classes,
    required this.chapters,
    this.midterm,
    this.finalExam,
  });

  final String code;
  final String name;

  /// รูปแบบหน่วยกิต เช่น 3(2-2-5) = บรรยาย 2 ชม. · ปฏิบัติ 2 ชม. · ศึกษาเอง 5 ชม./สัปดาห์
  final String credits;
  final int importance;
  final int sessions;
  final List<DemoClass> classes;
  final List<DemoChapter> chapters;

  /// (วัน, นาทีเริ่ม, นาที) · null = ไม่มีสอบข้อเขียน
  final (DateTime, int, int)? midterm;
  final (DateTime, int, int)? finalExam;
}

// ---------- โครงเทอม ----------

final demoTermStart = DateTime(2026, 11, 9); // จ. สัปดาห์ 1
final demoFirstHalfEnd = DateTime(2026, 12, 18); // ศ. สัปดาห์ 6
final demoSecondHalfStart = DateTime(2026, 12, 28); // จ. สัปดาห์ 8
final demoTermLastClass = DateTime(2027, 1, 29); // ศ. สัปดาห์ 12
final demoTermEnd = DateTime(2027, 2, 5); // ศ. สัปดาห์สอบปลายภาค
const demoTermLabel = 'ปี 1 เทอม 1 (ตัวอย่าง)';

const _h = 60;

final List<DemoSubject> demoSubjects = [
  DemoSubject(
    code: '060233101',
    name: 'วิศวกรรมสารสนเทศและเครือข่ายเบื้องต้น',
    credits: '3(2-2-5)',
    importance: 3,
    sessions: 3,
    classes: const [DemoClass(1, 9 * _h, 2 * _h, ClassType.theory), DemoClass(4, 13 * _h, 2 * _h, ClassType.lab)],
    midterm: (DateTime(2026, 12, 21), 9 * _h, 3 * _h),
    finalExam: (DateTime(2027, 2, 2), 13 * _h, 3 * _h),
    chapters: const [
      DemoChapter('บท 1 · ภาพรวมวิชาชีพ [กลางภาค]',
          ['บทบาทวิศวกรสารสนเทศและเครือข่าย', 'สายอาชีพและทักษะที่ต้องมี', 'จรรยาบรรณและกฎหมายคอมพิวเตอร์']),
      DemoChapter('บท 2 · ระบบคอมพิวเตอร์ [กลางภาค]',
          ['ฮาร์ดแวร์และส่วนประกอบ', 'ซอฟต์แวร์และระบบปฏิบัติการ', 'เลขฐานและการแทนข้อมูล'],
          flagged: {2}),
      DemoChapter('บท 3 · พื้นฐานเครือข่าย [กลางภาค]',
          ['LAN / WAN / Internet', 'Topology', 'อุปกรณ์: Switch / Router / AP', 'สื่อกลาง: สายทองแดง / ไฟเบอร์ / ไร้สาย']),
      DemoChapter('บท 4 · OSI และ TCP/IP [กลางภาค]',
          ['7 ชั้นของ OSI', '4 ชั้นของ TCP/IP', 'Encapsulation', 'โปรโตคอลหลักในแต่ละชั้น'],
          flagged: {0, 2}),
      DemoChapter('บท 5 · IP Address [ปลายภาค]',
          ['IPv4 และ Class', 'Subnet Mask', 'Subnetting เบื้องต้น', 'IPv6 เบื้องต้น'],
          flagged: {2}),
      DemoChapter('บท 6 · บริการบนอินเทอร์เน็ต [ปลายภาค]',
          ['DNS', 'DHCP', 'HTTP / HTTPS', 'Email: SMTP / IMAP']),
      DemoChapter('บท 7 · ไร้สาย คลาวด์ IoT [ปลายภาค]',
          ['มาตรฐาน Wi-Fi', 'Cloud: IaaS / PaaS / SaaS', 'IoT เบื้องต้น']),
      DemoChapter('บท 8 · ความปลอดภัยเบื้องต้น [ปลายภาค]',
          ['ภัยคุกคามที่พบบ่อย', 'รหัสผ่านและการยืนยันตัวตน', 'Firewall', 'PDPA']),
    ],
  ),
  DemoSubject(
    code: '060233115',
    name: 'การเขียนโปรแกรมคอมพิวเตอร์',
    credits: '3(2-2-5)',
    importance: 3,
    sessions: 4,
    classes: const [DemoClass(2, 9 * _h, 2 * _h, ClassType.theory), DemoClass(3, 9 * _h, 2 * _h, ClassType.lab)],
    midterm: (DateTime(2026, 12, 22), 9 * _h, 3 * _h),
    finalExam: (DateTime(2027, 2, 1), 9 * _h, 3 * _h),
    chapters: const [
      DemoChapter('บท 1 · อัลกอริทึมและผังงาน [กลางภาค]',
          ['ขั้นตอนการแก้ปัญหา', 'Pseudocode', 'Flowchart']),
      DemoChapter('บท 2 · ตัวแปรและชนิดข้อมูล [กลางภาค]',
          ['int / float / str / bool', 'ตัวดำเนินการ', 'รับค่าและแสดงผล']),
      DemoChapter('บท 3 · เงื่อนไข [กลางภาค]',
          ['if / elif / else', 'and / or / not', 'เงื่อนไขซ้อน'],
          flagged: {0}),
      DemoChapter('บท 4 · การวนซ้ำ [กลางภาค]',
          ['for และ range', 'while', 'break / continue', 'ลูปซ้อน'],
          flagged: {0, 3}),
      DemoChapter('บท 5 · ฟังก์ชัน [ปลายภาค]',
          ['พารามิเตอร์และ return', 'Scope ของตัวแปร', 'Recursion เบื้องต้น'],
          flagged: {0}),
      DemoChapter('บท 6 · List / Tuple / Dict [ปลายภาค]',
          ['Index และ Slicing', 'เมธอดของ List', 'Dictionary', 'ประยุกต์ใช้โครงสร้างข้อมูล'],
          flagged: {1, 2}),
      DemoChapter('บท 7 · สตริงและไฟล์ [ปลายภาค]',
          ['เมธอดของสตริง', 'อ่าน / เขียนไฟล์', 'ไฟล์ CSV']),
      DemoChapter('บท 8 · ข้อผิดพลาดและโปรเจกต์ [ปลายภาค]',
          ['try / except', 'การดีบัก', 'Mini Project']),
    ],
  ),
  DemoSubject(
    code: '080303701',
    name: 'กระบวนการคิดเชิงออกแบบ',
    credits: '3(3-0-6)',
    importance: 2,
    sessions: 2,
    classes: const [DemoClass(2, 13 * _h, 2 * _h, ClassType.theory), DemoClass(5, 9 * _h, 1 * _h, ClassType.theory)],
    midterm: (DateTime(2026, 12, 23), 13 * _h, 3 * _h),
    finalExam: (DateTime(2027, 2, 4), 9 * _h, 3 * _h),
    chapters: const [
      DemoChapter('บท 1 · แนวคิด Design Thinking [กลางภาค]',
          ['ที่มาและหลักการ', '5 ขั้นตอน', 'Mindset ของนักออกแบบ'],
          flagged: {1}),
      DemoChapter('บท 2 · Empathize [กลางภาค]',
          ['การสัมภาษณ์ผู้ใช้', 'การสังเกต', 'Empathy Map']),
      DemoChapter('บท 3 · Define [กลางภาค]',
          ['Persona', 'Point of View', 'How Might We']),
      DemoChapter('บท 4 · Ideate [ปลายภาค]',
          ['Brainstorming', 'SCAMPER', 'การคัดเลือกไอเดีย']),
      DemoChapter('บท 5 · Prototype [ปลายภาค]',
          ['Low-fidelity / Paper prototype', 'Wireframe', 'Storyboard']),
      DemoChapter('บท 6 · Test และนำเสนอ [ปลายภาค]',
          ['Usability Test', 'เก็บ Feedback และปรับปรุง', 'Pitching และ Storytelling']),
    ],
  ),
  DemoSubject(
    code: '080103001',
    name: 'ภาษาอังกฤษ 1',
    credits: '3(3-0-6)',
    importance: 2,
    sessions: 2,
    classes: const [DemoClass(1, 13 * _h, 2 * _h, ClassType.theory), DemoClass(3, 13 * _h, 1 * _h, ClassType.theory)],
    midterm: (DateTime(2026, 12, 24), 9 * _h, 3 * _h),
    finalExam: (DateTime(2027, 2, 3), 9 * _h, 3 * _h),
    chapters: const [
      DemoChapter('Unit 1 · Greetings & Introductions [กลางภาค]',
          ['Greetings', 'Introducing yourself', 'Asking personal questions']),
      DemoChapter('Unit 2 · Daily Routines [กลางภาค]',
          ['Present Simple', 'Adverbs of frequency', 'Telling the time']),
      DemoChapter('Unit 3 · Places [กลางภาค]',
          ['There is / There are', 'Prepositions of place', 'Giving directions']),
      DemoChapter('Unit 4 · Past Experiences [ปลายภาค]',
          ['Past Simple', 'Irregular verbs', 'Telling a story']),
      DemoChapter('Unit 5 · Future Plans [ปลายภาค]',
          ['will vs going to', 'Making arrangements']),
      DemoChapter('Unit 6 · Reading & Writing [ปลายภาค]',
          ['Skimming / Scanning', 'Main idea', 'Writing an email'],
          flagged: {2}),
    ],
  ),
  DemoSubject(
    code: '080XXXXXX',
    name: 'วิชาเลือกศึกษาทั่วไป: รู้เท่าทันสื่อดิจิทัล',
    credits: '3(3-0-6)',
    importance: 1,
    sessions: 1,
    classes: const [DemoClass(4, 9 * _h, 2 * _h, ClassType.theory), DemoClass(5, 13 * _h, 1 * _h, ClassType.theory)],
    midterm: (DateTime(2026, 12, 25), 13 * _h, 2 * _h),
    finalExam: (DateTime(2027, 2, 5), 13 * _h, 2 * _h),
    chapters: const [
      DemoChapter('บท 1 · สื่อและสังคมดิจิทัล [กลางภาค]',
          ['ประเภทของสื่อ', 'อัลกอริทึมของแพลตฟอร์ม']),
      DemoChapter('บท 2 · ข่าวปลอม [กลางภาค]',
          ['ลักษณะของข่าวปลอม', 'การตรวจสอบข้อเท็จจริง']),
      DemoChapter('บท 3 · ลิขสิทธิ์ [ปลายภาค]',
          ['ลิขสิทธิ์เบื้องต้น', 'Creative Commons', 'Fair Use']),
      DemoChapter('บท 4 · ความปลอดภัยออนไลน์ [ปลายภาค]',
          ['Digital Footprint', 'ความเป็นส่วนตัว']),
      DemoChapter('บท 5 · สร้างคอนเทนต์อย่างรับผิดชอบ [ปลายภาค]',
          ['จริยธรรมผู้สร้างสื่อ', 'การอ้างอิงแหล่งที่มา']),
    ],
  ),
  DemoSubject(
    code: 'XXXXXXXXX',
    name: 'วิชาเลือกกีฬาและนันทนาการ',
    credits: '1(0-2-1)',
    importance: 1,
    sessions: 1,
    classes: const [DemoClass(5, 15 * _h, 2 * _h, ClassType.lab)],
    // วิชาปฏิบัติ: สอบทักษะในคาบ ไม่มีสอบข้อเขียน
    chapters: const [
      DemoChapter('บท 1 · พื้นฐาน [กลางภาค]', ['กติกา', 'การจับไม้และ Footwork']),
      DemoChapter('บท 2 · ทักษะการตี [กลางภาค]', ['Serve', 'Clear', 'Drop', 'Smash']),
      DemoChapter('บท 3 · การแข่งขัน [ปลายภาค]', ['เกมเดี่ยว', 'เกมคู่', 'สอบทักษะ']),
    ],
  ),
];

/// ใส่ข้อมูลตัวอย่างลงแอป · คืน false ถ้าเคยใส่แล้ว (เจอชื่อวิชาซ้ำ)
Future<bool> loadDemoTerm(StudyRepository study, CalendarRepository calendar) async {
  final existing = {for (final s in await study.subjects()) s.name};
  if (demoSubjects.any((d) => existing.contains(d.name))) return false;

  final learn = studyCategoryId(await calendar.categories());
  await calendar.saveTerm(1, 1, demoTermStart, demoTermEnd);

  for (final d in demoSubjects) {
    // ---- วิชา + บท + หัวข้อย่อย ----
    final id = await study.addSubject(d.name, importance: d.importance);
    await study.setSessionsPerWeek(id, d.sessions);
    await study.setSubjectPlan(id, code: d.code, credits: d.credits, year: 1, term: 1);
    for (final ch in d.chapters) {
      final chId = await study.addChapter(id, ch.name);
      for (var i = 0; i < ch.topics.length; i++) {
        final tId = await study.addSubtopic(chId, ch.topics[i]);
        if (ch.flagged.contains(i)) await study.setExamFlag(tId, true);
      }
    }

    // ---- คาบเรียน: 2 ช่วง (เว้นสัปดาห์สอบกลางภาค) ----
    for (final c in d.classes) {
      for (final (from, to) in [
        (demoTermStart, demoFirstHalfEnd),
        (demoSecondHalfStart, demoTermLastClass),
      ]) {
        await calendar.addActivity(NewActivity(
          name: 'เรียน · ${d.name}',
          categoryId: learn,
          importance: 3,
          timed: true,
          day: from,
          startMinute: c.start,
          durationMin: c.minutes,
          repeat: RepeatKind.weekly,
          weekdays: {c.weekday},
          endDate: to,
          subjectId: id,
          kind: ActivityKind.classSession,
          classInfo: ClassInfo(
            type: c.type,
            section: switch (c.type) { ClassType.theory => 'S.1', ClassType.lab => 'L.1', null => null },
          ),
        ));
      }
    }

    // ---- วันสอบ ----
    for (final (label, exam) in [('สอบกลางภาค', d.midterm), ('สอบปลายภาค', d.finalExam)]) {
      if (exam == null) continue;
      await calendar.addActivity(NewActivity(
        name: '$label · ${d.name}',
        categoryId: learn,
        importance: 3,
        timed: true,
        day: exam.$1,
        startMinute: exam.$2,
        durationMin: exam.$3,
        subjectId: id,
        kind: ActivityKind.exam,
      ));
    }
  }
  return true;
}

// ---------- แผนการเรียนทั้งหลักสูตร (4 ปี · 125 หน่วยกิต) ----------
// จากแผนภูมิหลักสูตรวิศวกรรมสารสนเทศและเครือข่าย พ.ศ. 2567 ที่นัวร์ส่งมา
// ปี 1 เทอม 1 มีรายละเอียดเต็มใน demoSubjects · เทอมอื่นใส่แค่ชื่อ/รหัส/หน่วยกิต (ยังไม่มีบท)

typedef PlanEntry = ({int year, int term, String code, String name, String credits});

const List<PlanEntry> curriculumPlan = [
  // ปี 1 เทอม 2 · 17 หน่วยกิต
  (year: 1, term: 2, code: '040203123', name: 'คณิตศาสตร์เต็มหน่วยและการประยุกต์', credits: '3(3-0-6)'),
  (year: 1, term: 2, code: '060233108', name: 'การสื่อสารข้อมูลและเครือข่ายคอมพิวเตอร์', credits: '3(3-0-6)'),
  (year: 1, term: 2, code: '060233116', name: 'การแก้ปัญหาและขั้นตอนวิธี', credits: '3(2-2-5)'),
  (year: 1, term: 2, code: '060233117', name: 'อิเล็กทรอนิกส์และวงจรดิจิทัล', credits: '3(2-2-5)'),
  (year: 1, term: 2, code: '080103002', name: 'ภาษาอังกฤษ 2', credits: '3(3-0-6)'),
  (year: 1, term: 2, code: '080XXXXXX', name: 'วิชาเลือกในหมวดวิชาศึกษาทั่วไป', credits: '2(2-0-4)'),
  // ปี 2 เทอม 1 · 16
  (year: 2, term: 1, code: '040203111', name: 'คณิตศาสตร์วิศวกรรม 1', credits: '3(3-0-6)'),
  (year: 2, term: 1, code: '060233106', name: 'การเขียนแบบวิศวกรรมสารสนเทศและเครือข่าย', credits: '3(2-2-5)'),
  (year: 2, term: 1, code: '060233215', name: 'ปฏิบัติการวิศวกรรมสารสนเทศและเครือข่าย 1', credits: '1(0-3-1)'),
  (year: 2, term: 1, code: '060233205', name: 'เครือข่ายขั้นสูงและโปรโตคอล', credits: '3(3-0-6)'),
  (year: 2, term: 1, code: 'XXXXXXXXX', name: 'วิชาเลือกเสรี', credits: '3(3-0-6)'),
  (year: 2, term: 1, code: '080XXXXXX', name: 'วิชาเลือกในหมวดวิชาศึกษาทั่วไป', credits: '3(3-0-6)'),
  // ปี 2 เทอม 2 · 19
  (year: 2, term: 2, code: '040203112', name: 'คณิตศาสตร์วิศวกรรม 2', credits: '3(3-0-6)'),
  (year: 2, term: 2, code: '060233120', name: 'การพัฒนาระบบสารสนเทศแบบครบองค์ประกอบ', credits: '3(2-2-5)'),
  (year: 2, term: 2, code: '060233216', name: 'ปฏิบัติการวิศวกรรมสารสนเทศและเครือข่าย 2', credits: '1(0-3-1)'),
  (year: 2, term: 2, code: '060233111', name: 'สถาปัตยกรรมคอมพิวเตอร์และระบบปฏิบัติการ', credits: '3(3-0-6)'),
  (year: 2, term: 2, code: '060233112', name: 'วิศวกรรมข้อมูล', credits: '3(3-0-6)'),
  (year: 2, term: 2, code: '060233119', name: 'ระบบฐานข้อมูล', credits: '3(3-0-6)'),
  (year: 2, term: 2, code: '060233219', name: 'การออกแบบและการประยุกต์อินเทอร์เน็ตในทุกสรรพสิ่ง', credits: '3(2-2-5)'),
  // ปี 3 เทอม 1 · 16
  (year: 3, term: 1, code: '060233118', name: 'วิศวกรรมซอฟต์แวร์', credits: '3(3-0-6)'),
  (year: 3, term: 1, code: '060233114', name: 'สถิติสำหรับวิศวกรรมข้อมูลและนักวิทยาศาสตร์ข้อมูล', credits: '3(3-0-6)'),
  (year: 3, term: 1, code: '060233217', name: 'ปฏิบัติการวิศวกรรมสารสนเทศและเครือข่าย 3', credits: '1(0-3-1)'),
  (year: 3, term: 1, code: '060233218', name: 'โครงสร้างพื้นฐานคลาวด์สำหรับซอฟต์แวร์และบริการ', credits: '3(2-2-5)'),
  (year: 3, term: 1, code: '060233221', name: 'ความปลอดภัยและความเป็นส่วนตัวของข้อมูล', credits: '3(3-0-6)'),
  (year: 3, term: 1, code: '0602333XX', name: 'วิชาเลือกกลุ่มวิชาชีพ', credits: '3(3-0-6)'),
  // ปี 3 เทอม 2 · 19
  (year: 3, term: 2, code: '060233207', name: 'การประยุกต์ใช้การเรียนรู้ของเครื่องจักร', credits: '3(2-2-5)'),
  (year: 3, term: 2, code: '060233206', name: 'การจัดการเครือข่ายเบื้องต้นและเครื่องมือ', credits: '3(3-0-6)'),
  (year: 3, term: 2, code: '060233204', name: 'การออกแบบและจัดทำเครือข่ายคอมพิวเตอร์', credits: '3(3-0-6)'),
  (year: 3, term: 2, code: '060233209', name: 'การพัฒนาโปรแกรมประยุกต์บนอุปกรณ์เคลื่อนที่', credits: '3(3-0-6)'),
  (year: 3, term: 2, code: '060233212', name: 'การวิเคราะห์ข้อมูลขนาดใหญ่', credits: '3(2-2-5)'),
  (year: 3, term: 2, code: '060233214', name: 'สัมมนาวิศวกรรมสารสนเทศและเครือข่าย', credits: '1(0-3-1)'),
  (year: 3, term: 2, code: '080203914', name: 'ผู้ประกอบการนวัตกรรม', credits: '3(3-0-6)'),
  // ปี 3 ภาคฤดูร้อน · 1
  (year: 3, term: 3, code: '060233403', name: 'การฝึกงาน', credits: '1(240 ชม.)'),
  // ปี 4 เทอม 1 · 15
  (year: 4, term: 1, code: '060233401', name: 'โครงงานวิศวกรรมสารสนเทศและเครือข่าย 1', credits: '3(0-6-3)'),
  (year: 4, term: 1, code: '060233208', name: 'ความมั่นคงปลอดภัยไซเบอร์', credits: '3(3-0-6)'),
  (year: 4, term: 1, code: '060233220', name: 'การประมวลผลภาษาธรรมชาติ', credits: '3(2-2-5)'),
  (year: 4, term: 1, code: '0602333XX', name: 'วิชาเลือกกลุ่มวิชาชีพ', credits: '3(3-0-6)'),
  (year: 4, term: 1, code: '080XXXXXX', name: 'วิชาเลือกในหมวดวิชาศึกษาทั่วไป', credits: '3(3-0-6)'),
  // ปี 4 เทอม 2 · 6
  (year: 4, term: 2, code: '060233402', name: 'โครงงานวิศวกรรมสารสนเทศและเครือข่าย 2', credits: '3(0-6-3)'),
  (year: 4, term: 2, code: 'XXXXXXXXX', name: 'วิชาเลือกเสรี', credits: '3(3-0-6)'),
];

/// วิชาที่ต้องเรียนก่อน (รหัส → รหัส) ตามแผนภูมิหลักสูตร 2567 ที่นัวร์ยืนยันแล้ว
const List<(String, String)> curriculumLinks = [
  ('060233115', '060233120'), // การเขียนโปรแกรม → พัฒนาระบบสารสนเทศฯ
  ('080103001', '080103002'), // อังกฤษ 1 → 2
  ('040203111', '040203112'), // คณิตวิศวกรรม 1 → 2
  ('060233108', '060233215'), // การสื่อสารข้อมูลฯ → ปฏิบัติการ 1
  ('060233108', '060233205'), //   → เครือข่ายขั้นสูงฯ
  ('060233108', '060233206'), //   → การจัดการเครือข่ายฯ
  ('060233108', '060233204'), //   → ออกแบบเครือข่ายฯ
  ('060233108', '060233208'), //   → ความมั่นคงปลอดภัยไซเบอร์
  ('060233215', '060233216'), // ปฏิบัติการ 1 → 2
  ('060233120', '060233403'), // พัฒนาระบบสารสนเทศฯ → ฝึกงาน
  ('060233120', '060233401'), //   → โครงงาน 1
  ('060233207', '060233403'), // ML → ฝึกงาน
  ('060233401', '060233402'), // โครงงาน 1 → 2
];

/// ใส่เส้นความสัมพันธ์ตามหลักสูตร: จับคู่จากรหัสวิชา · เพิ่มอย่างเดียว ไม่ลบเส้นที่นัวร์ทำเอง
/// รหัสในรายการไม่ซ้ำกับวิชาเลือก (XXX) จึงจับคู่ได้ตัวเดียว · คืนจำนวนเส้นที่เพิ่ม
Future<int> loadCurriculumLinks(StudyRepository study) async {
  final byCode = <String, int>{};
  for (final s in await study.subjects()) {
    if (s.code != null) byCode.putIfAbsent(s.code!, () => s.id);
  }
  final have = (await study.subjectLinks()).toSet();
  var added = 0;
  for (final (a, b) in curriculumLinks) {
    final from = byCode[a], to = byCode[b];
    if (from == null || to == null || have.contains((from: from, to: to))) continue;
    await study.addSubjectLink(from, to);
    added++;
  }
  return added;
}

/// ใส่แผนการเรียนทั้งหลักสูตร: ปี 1 เทอม 1 แบบละเอียด + เทอมอื่นแบบรายชื่อ · คืนจำนวนวิชาที่เพิ่ม
/// [today] = วันนี้ของข้อมูลตัวอย่าง (เทสส่งค่าคงที่ · ไม่ส่ง = วันจริง)
Future<int> loadDemoCurriculum(StudyRepository study, CalendarRepository calendar, {DateTime? today}) async {
  var added = 0;
  if (await loadDemoTerm(study, calendar)) {
    added += demoSubjects.length;
    // ใส่ใหม่ครั้งแรก → เติมรายละเอียดให้ครบทุกระบบเลย (คะแนน ห้อง คาบที่เรียนแล้ว ติว ฯลฯ)
    await enrichDemoTerm(study, calendar, today: today);
  }

  // วิชาตัวอย่างปี 1 เทอม 1 ที่ใส่ไว้ก่อนมีแผนการเรียน → เติมรหัส/หน่วยกิต/ปี/เทอม
  final byName = {for (final d in demoSubjects) d.name: d};
  for (final s in await study.subjects()) {
    final d = byName[s.name];
    if (d != null && s.planYear == null) {
      await study.setSubjectPlan(s.id, code: d.code, credits: d.credits, year: 1, term: 1);
    }
  }

  final have = {
    for (final s in await study.subjects()) '${s.planYear}|${s.planTerm}|${s.code}|${s.name}'
  };
  for (final e in curriculumPlan) {
    if (have.contains('${e.year}|${e.term}|${e.code}|${e.name}')) continue;
    final id = await study.addSubject(e.name, importance: 2);
    await study.setSubjectPlan(id, code: e.code, credits: e.credits, year: e.year, term: e.term);
    added++;
  }
  await loadCurriculumLinks(study);
  return added;
}

// ---------- รายละเอียดตัวอย่างให้ครบทุกระบบ (ทดสอบ) ----------

/// วันหยุดตัวอย่างในเทอม (วันรัฐธรรมนูญ)
final demoHoliday = DateTime(2026, 12, 10);

/// เติมรายละเอียดให้วิชาตัวอย่างปี 1 ภาค 1 ครบทุกระบบที่แอปมี:
/// ห้องเรียน · คะแนนหัวข้อ (ดี / พอได้ / ยังไม่ได้ / ยังไม่ประเมิน) · ประเภท/สถานะบท ·
/// คาบที่เรียนไปแล้ว (ทำแล้ว + เวลาเลิกจริง / ยกเลิกพร้อมเหตุผล) · รอบติว ·
/// งานหมวดอื่น (ออกกำลังกาย / สตรีม / งาน) · Updates · วันหยุด
///
/// แตะเฉพาะวิชาตัวอย่าง (จับจากรหัส) · หัวข้อที่มีคะแนนแล้ว / คาบที่มีห้องแล้ว ไม่ทับ
/// ทำซ้ำได้ (ครั้งที่สองไม่เพิ่มของซ้ำ) · [today] = วันนี้ (เทสส่งค่าคงที่ได้) · คืนสรุปสั้น ๆ
Future<String> enrichDemoTerm(StudyRepository study, CalendarRepository calendar, {DateTime? today}) async {
  final now = dayOnly(today ?? DateTime.now());
  final codes = [for (final d in demoSubjects) d.code];
  final subjects = [
    for (final s in await study.subjects())
      if (s.planYear == 1 && s.planTerm == 1 && codes.contains(s.code)) s
  ]..sort((a, b) => codes.indexOf(a.code!).compareTo(codes.indexOf(b.code!)));
  if (subjects.isEmpty) return 'ไม่พบวิชาตัวอย่าง · กด "ใส่ตัวอย่าง: แผน 4 ปี" ก่อน';

  var scores = 0, rooms = 0, done = 0, extras = 0;
  for (final (i, s) in subjects.indexed) {
    // ---- บท: บทแรกประเมินแล้ว · บทสองกำลังติว · ที่เหลือยังไม่เริ่ม · ประเภทตามหน่วยกิต ----
    final lab = (parseLabHours(s.credits) ?? 0) > 0;
    final chapters = await study.chapters(s.id);
    for (final (ci, ch) in chapters.indexed) {
      await study.setChapterKind(
          ch.chapter.id, !lab ? ChapterKind.theory : (ci.isEven ? ChapterKind.mixed : ChapterKind.practice));
      await study.setChapterStatus(ch.chapter.id,
          ci == 0 ? ChapterStatus.assessed : (ci == 1 ? ChapterStatus.learning : ChapterStatus.todo));
      if (ci > 1) continue; // บทที่ยังไม่เรียน = ยังไม่ประเมิน
      for (final (ti, t) in ch.subtopics.indexed) {
        if (t.scores.isNotEmpty) continue;
        // กระจายคะแนนแบบคงที่ (seed จากตำแหน่ง) ให้มีครบทั้ง เขียว / เหลือง / แดง
        final base = 35 + (i * 37 + ci * 17 + ti * 23) % 65;
        final rounds = 1 + (i + ti) % 3;
        for (var r = 0; r < rounds; r++) {
          final score = (base + r * 8).clamp(0, 100);
          await study.addAssessment(t.id, score, at: now.subtract(Duration(days: 12 - r * 4 - ti % 3)));
          scores++;
        }
      }
    }

    // ---- ห้องเรียน: ทฤษฎี 1-B4-0N · ปฏิบัติ LAB-N ----
    for (final a in await calendar.activitiesForSubject(s.id)) {
      if (a.kind != ActivityKind.classSession || a.classInfo.room != null) continue;
      final room = a.classInfo.type == ClassType.lab ? 'LAB-${i + 1}' : '1-B4-0${i + 1}';
      await calendar.updateActivity(a.id, a.toDraft().withClassInfo(ClassInfo(
        type: a.classInfo.type,
        room: room,
        section: a.classInfo.section,
      )), from: a.startDate);
      rooms++;
    }
  }

  // ---- คาบที่ผ่านไปแล้วในเทอม: ทำแล้ว + เวลาเลิกจริง (ช้ากว่าตาราง 0–20 นาที) · ยกเลิก 1 คาบ ----
  var cancelled = false;
  for (var d = demoTermStart; d.isBefore(now); d = d.add(const Duration(days: 1))) {
    for (final o in await calendar.occurrencesOn(d)) {
      if (o.kind != ActivityKind.classSession || o.status != OccurrenceStatus.planned) continue;
      if (!cancelled && d.weekday == DateTime.tuesday) {
        await calendar.cancel(o.id, 'อาจารย์ติดประชุม งดสอน (ตัวอย่าง)');
        cancelled = true;
        continue;
      }
      await calendar.setDone(o.id, true);
      await calendar.setActualTimes(o.id, end: o.endAt!.add(Duration(minutes: (o.id * 7) % 25)));
      done++;
    }
  }

  // ---- ของที่ไม่ใช่คาบเรียน: เพิ่มครั้งเดียว (เช็กชื่อก่อน) ----
  final cats = await calendar.categories();
  int cat(String name) => cats.firstWhere((c) => c.name == name, orElse: () => cats.first).id;
  final learn = studyCategoryId(cats) ?? cats.first.id;
  // ของที่เพิ่มด้านล่างอยู่ใน 2 สัปดาห์แรกทั้งหมด → เช็กชื่อในช่วงนั้นพอ
  final have = <String>{
    for (var k = 0; k < 14; k++)
      for (final o in await calendar.occurrencesOn(demoTermStart.add(Duration(days: k)))) o.title,
    for (final o in await calendar.inbox()) o.title,
  };
  Future<int?> add(NewActivity a) async {
    if (have.contains(a.name)) return null;
    extras++;
    return calendar.addActivity(a);
  }

  final prog = subjects.where((s) => s.code == '060233115').firstOrNull ?? subjects.first;
  // รอบติว: จันทร์ (ทำไปแล้ว) + พฤหัส (ตามแผน)
  await add(NewActivity(
    name: 'ติว · ${prog.name}', categoryId: learn, importance: 3, timed: true,
    day: demoTermStart, startMinute: 19 * 60, durationMin: 90,
    subjectId: prog.id, kind: ActivityKind.tutor,
  ));
  await add(NewActivity(
    name: 'ติวทวน · ${prog.name}', categoryId: learn, importance: 3, timed: true,
    day: demoTermStart.add(const Duration(days: 3)), startMinute: 19 * 60, durationMin: 90,
    subjectId: prog.id, kind: ActivityKind.tutor,
  ));
  // ชีวิตนอกห้องเรียน (ไม่ชนคาบเรียนตัวอย่าง)
  await add(NewActivity(
    name: 'วิ่ง 5K', categoryId: cat('ออกกำลังกาย'), importance: 2, timed: true,
    day: demoTermStart, startMinute: 17 * 60 + 30, durationMin: 45,
    repeat: RepeatKind.weekly, weekdays: {2, 4}, endDate: demoTermEnd,
  ));
  await add(NewActivity(
    name: 'Live CS2', categoryId: cat('สตรีม'), importance: 1, timed: true,
    day: demoTermStart, startMinute: 20 * 60, durationMin: 120,
    repeat: RepeatKind.weekly, weekdays: {6}, endDate: demoTermEnd,
  ));
  await add(NewActivity(
    name: 'ส่งรายงานแล็บ 1 · ${subjects.first.name}', categoryId: cat('งาน'), importance: 3, timed: true,
    day: demoTermStart.add(const Duration(days: 11)), startMinute: 21 * 60, durationMin: 60,
    subjectId: subjects.first.id,
  ));
  // Updates: งานยังไม่มีวัน
  final inboxId = await add(NewActivity(
    name: 'อ่านสไลด์บท 2 ก่อนเรียน', categoryId: learn, importance: 2, timed: false, day: demoTermStart,
  ));
  if (inboxId != null) {
    final o = (await calendar.occurrencesOn(demoTermStart)).where((o) => o.activityId == inboxId).firstOrNull;
    if (o != null) await calendar.sendToInbox(o.id);
  }
  // ทำรอบติววันจันทร์ไปแล้ว
  if (demoTermStart.isBefore(now)) {
    for (final o in await calendar.occurrencesOn(demoTermStart)) {
      if (o.kind == ActivityKind.tutor && o.status == OccurrenceStatus.planned) await calendar.setDone(o.id, true);
    }
  }
  if ((await calendar.holidays()).every((h) => h.day != demoHoliday)) {
    await calendar.setHoliday(demoHoliday, 'วันรัฐธรรมนูญ');
    extras++;
  }

  // ---- เกรด: งาน 20 (4×5) · สอบย่อย 15 (3×5) · เข้าเรียน 5 · กลางภาค 20 · ปลายภาค 40 ----
  // ใส่คะแนนชิ้นที่ผ่านไปแล้ว (งาน 3 ชิ้น · ย่อย 2 ครั้ง) · สอบยังไม่ถึง → ยังไม่มีคะแนน
  var gradeSubjects = 0;
  for (final (i, s) in subjects.indexed) {
    if ((await study.gradeParts(s.id)).isNotEmpty) continue; // มีของนัวร์อยู่แล้ว → ไม่แตะ
    for (final (name, weight, n) in const [
      ('งาน', 20.0, 4),
      ('สอบย่อย', 15.0, 3),
      ('เข้าเรียน', 5.0, 1),
      ('สอบกลางภาค', 20.0, 1),
      ('สอบปลายภาค', 40.0, 1),
    ]) {
      await study.addGradePart(s.id, name, weight, items: n, itemFull: n == 1 ? weight : 5);
    }
    final parts = await study.gradeParts(s.id);
    for (final (k, item) in parts[0].items.take(3).indexed) {
      await study.updateGradeItem(item.id, got: (5 - (i + k) % 3).toDouble());
    }
    for (final (k, item) in parts[1].items.take(2).indexed) {
      await study.updateGradeItem(item.id, got: (2 + (i * 2 + k) % 4).toDouble());
    }
    await study.updateGradeItem(parts[2].items.single.id, got: i == 3 ? 3 : 5);
    // วิชาที่ 4 (อังกฤษ): อาจารย์ตัด F ที่ 45
    if (i == 3) await study.setGradeSetup(s.id, GradeSetup(scale: withFCut(kuGradeScale, 45)));
    gradeSubjects++;
  }

  return 'คะแนน $scores ครั้ง · ห้อง $rooms คาบ · เรียนแล้ว $done คาบ'
      '${cancelled ? ' · ยกเลิก 1' : ''} · ของอื่น $extras รายการ'
      '${gradeSubjects > 0 ? ' · คะแนนเก็บ $gradeSubjects วิชา' : ''}';
}

/// ชั่วโมงปฏิบัติจากหน่วยกิต "3(2-2-5)" → 2 · อ่านไม่ได้ → null
int? parseLabHours(String? credits) {
  final m = RegExp(r'\(\s*\d+\s*-\s*(\d+)\s*-').firstMatch(credits ?? '');
  return m == null ? null : int.parse(m.group(1)!);
}
