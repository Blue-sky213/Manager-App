/// ข้อมูลตัวอย่าง (สมมุติ): ปี 1 เทอม 1 หลักสูตรวิศวกรรมสารสนเทศและเครือข่าย
///
/// โครงเทอม: 13 สัปดาห์ (~3 เดือน)
///   สัปดาห์ 1–6 เรียน → สัปดาห์ 7 สอบกลางภาค → สัปดาห์ 8–12 เรียน → สัปดาห์ 13 สอบปลายภาค
/// เนื้อหาบท/หัวข้อย่อยเป็นการคาดเดาจากชื่อวิชา ไม่ใช่ประมวลรายวิชาจริง
library;

import '../calendar/calendar_models.dart';
import '../calendar/calendar_repository.dart';
import 'study_repository.dart';

class DemoChapter {
  const DemoChapter(this.name, this.topics, {this.flagged = const {}});
  final String name;
  final List<String> topics;

  /// index ของหัวข้อย่อยที่ติดธง "อาจออกสอบ"
  final Set<int> flagged;
}

class DemoClass {
  const DemoClass(this.weekday, this.start, this.minutes);
  final int weekday; // 1 = จันทร์
  final int start; // นาทีนับจากเที่ยงคืน
  final int minutes;
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
    classes: const [DemoClass(1, 9 * _h, 4 * _h)],
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
    classes: const [DemoClass(3, 9 * _h, 4 * _h)],
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
    classes: const [DemoClass(2, 9 * _h, 3 * _h)],
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
    classes: const [DemoClass(1, 13 * _h + 30, 3 * _h)],
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
    classes: const [DemoClass(4, 13 * _h, 3 * _h)],
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
    classes: const [DemoClass(2, 13 * _h, 2 * _h)],
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

/// ใส่แผนการเรียนทั้งหลักสูตร: ปี 1 เทอม 1 แบบละเอียด + เทอมอื่นแบบรายชื่อ · คืนจำนวนวิชาที่เพิ่ม
Future<int> loadDemoCurriculum(StudyRepository study, CalendarRepository calendar) async {
  var added = 0;
  if (await loadDemoTerm(study, calendar)) added += demoSubjects.length;

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
  return added;
}
