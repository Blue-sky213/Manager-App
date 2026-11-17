/// สารบัญเรียนเอง (รอบ 11 · อนุมัติ 17 พ.ย. 2569): IELTS · DaVinci · Canva · คำศัพท์ A1 → C2
/// เป็น "วิชา" ในหน้าการเรียน (ไม่ผูกแผน 4 ปี) → บท → หัวข้อย่อย ให้คะแนน 🟢🟡🔴 ได้เหมือนวิชาปกติ
/// งานในแผน (IELTS · / ฝึก · DaVinci / ฝึก · Canva) ผูกกับวิชาเป็น "รอบติว" → กดทำแล้ว = ถามว่าเรียนบทไหน
library;

import '../calendar/calendar_models.dart';
import '../calendar/calendar_repository.dart';
import '../skills/skill_models.dart';
import '../study/mastery.dart';
import 'study_models.dart';
import 'study_repository.dart';

/// (ชื่อวิชา, [(บท, [หัวข้อ])]) · ชื่อหัวข้อ = ไทย · คำอังกฤษไว้ค้นใน YouTube/Google
typedef Toc = (String, List<(String, List<String>)>);

const selfStudyToc = <Toc>[
  ('IELTS', [
    ('บท 1 รู้จัก IELTS + วัดระดับ', ['รูปแบบข้อสอบ 4 ทักษะ · Test format', 'เกณฑ์ Band 1–9 · Band descriptors', 'ทำแบบทดสอบวัดระดับ · Diagnostic test', 'ตั้งเป้ารายทักษะ · Target band']),
    ('บท 2 คำศัพท์วิชาการ (AWL)', ['คำศัพท์วิชาการ ชุด 1 · AWL Sublist 1', 'คำศัพท์วิชาการ ชุด 2 · AWL Sublist 2', 'คำที่มักใช้คู่กัน · Collocations', 'คำตามหัวข้อ การศึกษา / เทคโนโลยี · Topic vocabulary']),
    ('บท 3 Grammar สำหรับ IELTS', ['Tense ที่ใช้บ่อย · Tenses', 'ประโยคซับซ้อน because / although / which · Complex sentences', 'ประโยคถูกกระทำ · Passive voice', 'เปรียบเทียบ · Comparatives', 'ประโยคเงื่อนไข · Conditionals']),
    ('บท 4 Listening', ['Part 1–2 ข้อมูลทั่วไป ตัวเลข สะกดชื่อ · Section 1–2', 'Part 3–4 บทสนทนา / บรรยาย · Section 3–4', 'เติมแบบฟอร์ม / โน้ต · Form & note completion', 'ตัวเลือก · Multiple choice', 'แผนที่ / แผนผัง · Map labelling']),
    ('บท 5 Reading', ['อ่านเร็ว จับใจความ / หาคำ · Skimming & scanning', 'จริง / ไม่จริง / ไม่ได้บอก · True / False / Not Given', 'จับคู่หัวข้อ · Matching headings', 'เติมประโยค · Sentence completion', 'จับเวลา 60 นาที · Timed practice']),
    ('บท 6 Writing Task 1 อธิบายกราฟ', ['อ่านกราฟ เส้น / แท่ง / วงกลม / ตาราง · Charts', 'ขั้นตอน / แผนที่ · Process & map', 'โครง 4 ย่อหน้า · Structure', 'ภาษาบอกแนวโน้ม + เปรียบเทียบ · Trend language']),
    ('บท 7 Writing Task 2 เรียงความ', ['ประเภทคำถาม · Question types', 'โครง 4 ย่อหน้า · Essay structure', 'ประโยคหลักแต่ละย่อหน้า · Thesis & topic sentence', 'คำเชื่อม · Linking words', 'เกณฑ์ตรวจ 4 ข้อ · Marking criteria']),
    ('บท 8 Speaking', ['Part 1 คุยเรื่องตัวเอง', 'Part 2 พูดคนเดียว 2 นาที · Cue card', 'Part 3 แสดงความเห็น', 'พูดลื่น + ออกเสียง · Fluency & pronunciation', 'อัดเสียงตัวเองฟัง · Self-recording']),
    ('บท 9 ข้อสอบเก่า (Cambridge IELTS)', ['ชุดที่ 1 · Test 1', 'ชุดที่ 2 · Test 2', 'ชุดที่ 3 · Test 3', 'ชุดที่ 4 · Test 4', 'สรุปจุดที่ผิดบ่อย · Error log']),
    ('บท 10 Mock + สมัครสอบ', ['Mock เต็ม จับเวลา ครั้งที่ 1', 'Mock เต็ม ครั้งที่ 2', 'เลือกศูนย์สอบ + สมัคร · BC / IDP', 'เตรียมวันสอบ · Test day']),
  ]),
  ('คำศัพท์ A1 → C2', [
    ('A1 แนะนำตัว ถามตอบพื้นฐาน', ['ตัวเอง + ครอบครัว', 'บ้าน + ของใช้', 'อาหาร + เครื่องดื่ม', 'เวลา วัน เดือน', 'ตัวเลข + เงิน']),
    ('A2 เรื่องใกล้ตัว กิจวัตร', ['กิจวัตรประจำวัน', 'ซื้อของ + ราคา', 'เดินทาง + ทิศทาง', 'สุขภาพ + ร่างกาย', 'งานอดิเรก']),
    ('B1 อธิบายเหตุการณ์ เรื่องคุ้นเคย', ['งาน + ที่ทำงาน', 'เทคโนโลยี + อินเทอร์เน็ต', 'อารมณ์ + ความรู้สึก', 'การศึกษา', 'ข่าว + เหตุการณ์']),
    ('B2 เหตุผล ข้อดีข้อเสีย', ['สิ่งแวดล้อม', 'ธุรกิจ + การเงิน', 'สังคม + ปัญหา', 'สื่อ + การโฆษณา', 'คำเชื่อมแสดงเหตุผล']),
    ('C1 บทความยาว พรีเซนต์ซับซ้อน', ['คำวิชาการขั้นสูง', 'สำนวน + Phrasal verbs', 'ภาษาทางการ / งานเขียน']),
    ('C2 คล่องเกือบเจ้าของภาษา', ['คำหายาก + ความหมายแฝง', 'สำนวนเฉพาะ', 'ปรับถ้อยคำให้ลื่น']),
  ]),
  ('DaVinci Resolve', [
    ('บท 1 พื้นฐาน + ตั้งค่าให้ไม่หน่วง', ['Project / Media pool', 'ตั้ง Timeline 1080p 60fps', 'ไฟล์สำรองตัดลื่น · Proxy / Optimized media', 'ตั้งคีย์ลัด · Keyboard layout']),
    ('บท 2 Cut page ตัดเร็ว', ['Source tape', 'ใส่คลิปเร็ว · Smart insert / Append', 'ตัด / เล็ม · Blade & trim', 'แยกฉากอัตโนมัติ · Scene detect']),
    ('บท 3 Edit page', ['ลบแล้วชิดเอง · Ripple delete', 'เล่น J / K / L', 'ปักหมุด · Markers', 'เร่ง / ชะลอ · Speed ramp', 'คีย์ลัดชุดหลัก']),
    ('บท 4 เสียง (Fairlight)', ['ปรับเสียงให้เท่ากัน -14 LUFS · Normalize', 'ลดเสียงรบกวน · Noise reduction', 'เพลงเบาลงตอนพูด · Ducking', 'แยกเสียงพูด · Voice isolation']),
    ('บท 5 สี (Color)', ['วงล้อสีหลัก · Primary wheels', 'อ่านกราฟสี · Scopes', 'Node พื้นฐาน', 'LUT', 'คัดลอกสีไปคลิปอื่น · Copy grade']),
    ('บท 6 ตัวหนังสือ + Fusion', ['Text+', 'ป้ายชื่อด้านล่าง · Lower third', 'ทำ Template เอง', 'ขยับด้วย Keyframe']),
    ('บท 7 Workflow ตัดไลฟ์', ['หา Highlight (ปักหมุดระหว่างไลฟ์)', 'ตัด 1 ชม. → 10 นาที', 'Shorts 9:16', 'Render สำหรับ YouTube']),
    ('บท 8 Speed challenge', ['จับเวลา ตัดคลิป 1 ชม. ครั้งที่ 1', 'ครั้งที่ 2', 'ครั้งที่ 3 (เป้า ≤ 90 นาที)', 'สรุปคีย์ลัด / ขั้นที่เสียเวลา']),
  ]),
  ('Canva', [
    ('บท 1 พื้นฐาน', ['หน้าจอ + เมนู · Workspace', 'ภาพ / ตัวหนังสือ · Elements & text', 'เลเยอร์ / จัดกลุ่ม', 'เริ่มจาก Template']),
    ('บท 2 Brand kit Noir Lev', ['สีประจำช่อง', 'ฟอนต์ไทย + อังกฤษ', 'โลโก้', 'Template ของช่อง']),
    ('บท 3 หลักออกแบบ', ['อะไรเด่นก่อน · Hierarchy', 'สีตัดกัน · Contrast', 'ตัวหนังสือบนรูป', 'จัดวางสามส่วน · Rule of thirds']),
    ('บท 4 ปก YouTube / ไลฟ์', ['ขนาด 1280×720', 'หน้าตัวเอง + ข้อความ 3 คำ', 'ลบพื้นหลัง · Background remover', 'ลองปก 2 แบบ · A/B']),
    ('บท 5 Shorts / Social', ['แนวตั้ง 9:16', 'โพสต์ประกาศไลฟ์', 'Story']),
    ('บท 6 ภาพเว็บ mecsteam', ['ครอป / ย่อภาพผลงาน', 'ใส่ลายน้ำ', 'Export เบา คมชัด · WebP']),
    ('บท 7 Speed', ['Template ปก ≤ 30 นาที', 'เครื่องมือ AI ใน Canva · Magic tools', 'จับเวลา 3 ครั้ง']),
  ]),
];

/// งานในแผน (ขึ้นต้นด้วย) → วิชาที่ผูก
const _linkPrefix = [
  ('IELTS · คำศัพท์', 'คำศัพท์ A1 → C2'),
  ('IELTS ·', 'IELTS'),
  ('ฝึก · DaVinci', 'DaVinci Resolve'),
  ('ฝึก · Canva', 'Canva'),
];

typedef SelfStudyResult = ({int subjects, int chapters, int subtopics, int linked});

/// สร้างวิชา + บท + หัวข้อ (มีอยู่แล้ว = ข้าม) แล้วผูกงานในแผนเป็นรอบติวของวิชานั้น · กดซ้ำได้
Future<SelfStudyResult> applySelfStudy(StudyRepository study, CalendarRepository cal) async {
  var subjects = 0, chapters = 0, subtopics = 0, linked = 0;
  final ids = <String, int>{};
  final have = await study.subjects();
  for (final (name, toc) in selfStudyToc) {
    var id = have.where((s) => s.name == name).firstOrNull?.id;
    if (id == null) {
      id = await study.addSubject(name);
      subjects++;
    }
    ids[name] = id;
    final chs = await study.chapters(id);
    for (final (chName, topics) in toc) {
      final ch = chs.where((c) => c.chapter.name == chName).firstOrNull;
      final chId = ch?.chapter.id ?? await study.addChapter(id, chName);
      if (ch == null) chapters++;
      final existing = {for (final t in ch?.subtopics ?? const <Subtopic>[]) t.name};
      for (final t in topics) {
        if (existing.contains(t)) continue;
        await study.addSubtopic(chId, t);
        subtopics++;
      }
    }
  }

  for (final aid in await cal.activityIds()) {
    final a = await cal.activity(aid);
    final subject = _linkPrefix.where((p) => a.name.startsWith(p.$1)).firstOrNull?.$2;
    if (subject == null || a.repeat == RepeatKind.dates) continue;
    if (a.subjectId == ids[subject] && a.kind == ActivityKind.tutor) continue;
    await cal.updateActivity(
      aid,
      NewActivity(
        name: a.name,
        categoryId: a.categoryId,
        importance: a.importance,
        timed: a.timed,
        day: a.startDate,
        startMinute: a.startMinute,
        durationMin: a.durationMin,
        repeat: a.repeat,
        weekdays: a.weekdays,
        endDate: a.endDate,
        presetId: a.presetId,
        subjectId: ids[subject],
        kind: ActivityKind.tutor,
        flexible: a.flexible,
      ),
    );
    linked++;
  }
  return (subjects: subjects, chapters: chapters, subtopics: subtopics, linked: linked);
}

/// % หัวข้อที่ "เข้าใจแล้ว" (🟢) ของวิชา · ไม่มีหัวข้อ = null · ใช้แทน % ในแผนผังสกิลเมื่อมีวิชาชื่อตรงกัน
Future<double?> subjectGreenRatio(StudyRepository study, int subjectId, GradingMode mode) async {
  final topics = [for (final ch in await study.chapters(subjectId)) ...ch.subtopics];
  if (topics.isEmpty) return null;
  return topics.where((t) => (shownScore(t, mode) ?? 0) >= 80).length / topics.length;
}

/// วิชาที่คู่กับสกิล (คำแรกของชื่อตรงกัน เช่น สกิล "DaVinci" ↔ วิชา "DaVinci Resolve")
Subject? subjectForSkill(String skillName, List<Subject> subjects) {
  final key = skillName.split(' ').first.toLowerCase();
  return subjects.where((s) => s.name.split(' ').first.toLowerCase() == key).firstOrNull;
}

/// % ของสกิลจากวิชาคู่กัน ถ้ามี (ไม่มี = [fallback]) · สกิลที่จบแล้วใช้ค่าเดิม
Future<double> subjectRatioOr(StudyRepository study, Skill s, GradingMode mode, double fallback) async {
  if (s.status == SkillStatus.done) return fallback;
  final sub = subjectForSkill(s.name, await study.subjects());
  if (sub == null) return fallback;
  return await subjectGreenRatio(study, sub.id, mode) ?? fallback;
}
