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

  final cats = await calendar.categories();
  final learn = cats.where((c) => c.name == 'เรียน').firstOrNull?.id;

  for (final d in demoSubjects) {
    // ---- วิชา + บท + หัวข้อย่อย ----
    final id = await study.addSubject(d.name, importance: d.importance);
    await study.setSessionsPerWeek(id, d.sessions);
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
      ));
    }
  }
  return true;
}
