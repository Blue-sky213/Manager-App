/// สารบัญเรียนเองในสกิล (รอบ 13): บท → หัวข้อ + ลิงก์คลิป YouTube
/// เลือกครูจากยอดผู้ติดตาม / ความครบของคอร์ส (สำรวจ 17 พ.ย. 2569):
/// DaVinci = Casey Faris คอร์สเต็ม 4.5 ชม. (เรียงบทตามคลิป) + Primal Video ภาพรวม 28 นาที
/// Canva = สอนไทยตั้งแต่ต้น-จบ + Kesington Abdurrazaq คอร์สเต็ม · IELTS = E2 IELTS / IELTS Liz / IELTS Advantage
/// อังกฤษพื้นฐาน → B1 (นัวร์เลือก 18 พ.ย.) = KruDew English (Grammar ภาษาไทย) + Speak English With Vanessa (พูดช้า ชัด)
/// → ค่อยเรียน IELTS เมื่อได้ B1 (นัวร์พื้นอังกฤษยังไม่แน่น คลิปอังกฤษล้วนยากเกินไป)
/// IELTS ไม่มีคลิปเดียวจบ → ลิงก์เป็นหน้าค้นหาในช่องนั้น · บทที่คลิปไม่สอน (ตัดไลฟ์ / speed) = บทของเราเอง
library;

import 'skill_models.dart';
import 'skill_repository.dart';

/// คลิป YouTube เริ่มที่วินาที [sec]
String yt(String id, [int sec = 0]) => 'https://www.youtube.com/watch?v=$id${sec > 0 ? '&t=${sec}s' : ''}';

/// หน้าค้นหา YouTube (ใช้เมื่อไม่มีคลิปเดียวที่ครบ)
String ytSearch(String q) => 'https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent(q)}';

/// ค้นหาในช่องของครูคนนั้น (ได้คลิปของครูที่เลือกเท่านั้น)
String ytChannel(String handle, String q) => 'https://www.youtube.com/@$handle/search?query=${Uri.encodeQueryComponent(q)}';

typedef LessonTopic = (String name, String? url);
typedef LessonChapter = (String name, String? url, List<LessonTopic> topics);

/// (คำค้นชื่อสกิล, ชื่อสกิลถ้าต้องสร้างใหม่, ไอคอน, บท)
typedef LessonPreset = (String key, String skillName, String icon, List<LessonChapter> chapters);

const _casey = 'qDHnCFMZ9HA'; // Casey Faris · Introduction to DaVinci Resolve [Full Course] 2024
const _primal = 'CC_-V5qjhaY'; // Primal Video · DaVinci Resolve 20 Complete Tutorial
const _kes = '1knrVRlCUtg'; // Kesington Abdurrazaq · Canva Complete Course 2026
const _canvaTh = 'yQML-U8jAIs'; // สอนวิธีใช้ Canva ตั้งแต่ต้น-จนจบ
const _coverTh = 'oCxzbe8eOe4'; // ทำปก YouTube ใส่ภาษาไทย
const _coverTh2 = 'xN6xQ2FZfeE'; // จับมือทำปก YouTube
const _dew = 'kdenglishofficial'; // KruDew English Official · Grammar สอนภาษาไทย (นัวร์เลือก 18 พ.ย.)
const _vanessa = 'SpeakEnglishWithVanessa'; // Speak English With Vanessa · พูดช้า ชัด (นัวร์เลือก 18 พ.ย.)
String _kd(String q) => ytChannel(_dew, q);
String _vn(String q) => ytChannel(_vanessa, q);

/// ชื่อสกิลพื้นฐาน · IELTS "ต้องผ่านก่อน" สกิลนี้ (แค่เตือน)
const englishB1Skill = 'อังกฤษพื้นฐาน → B1';

final lessonPresets = <LessonPreset>[
  (
    'davinci',
    'DaVinci Resolve',
    '🎬',
    [
      ('บท 0 ภาพรวมเร็ว (Primal Video 28 นาที)', yt(_primal), [
        ('ดูทั้งโปรแกรมรอบเดียว', yt(_primal)),
        ('ตัดคลิปเบื้องต้น', yt(_primal, 272)),
        ('ใส่ตัวหนังสือ', yt(_primal, 673)),
        ('เสียงเบื้องต้น', yt(_primal, 1126)),
        ('สีเบื้องต้น', yt(_primal, 1419)),
        ('Export', yt(_primal, 1605)),
      ]),
      ('บท 1 เริ่มโปรเจกต์ + Media', yt(_casey), [
        ('Project / ตั้ง Timeline 1080p 60fps', yt(_casey)),
        ('Project / Media pool', yt(_casey, 950)),
        ('ไฟล์สำรองตัดลื่น · Proxy / Optimized media', ytSearch('DaVinci Resolve proxy optimized media')),
        ('ตั้งคีย์ลัด · Keyboard layout', ytSearch('DaVinci Resolve keyboard shortcuts customize')),
      ]),
      ('บท 2 Edit page', yt(_casey, 1768), [
        ('วางคลิปบน Timeline', yt(_casey, 1768)),
        ('ลบแล้วชิดเอง · Ripple delete', yt(_casey, 1768)),
        ('เล่น J / K / L', ytSearch('DaVinci Resolve JKL editing')),
        ('ปักหมุด · Markers', ytSearch('DaVinci Resolve markers')),
        ('เร่ง / ชะลอ · Speed ramp', ytSearch('DaVinci Resolve speed ramp')),
      ]),
      ('บท 3 Cut page ตัดเร็ว', yt(_casey, 4341), [
        ('Source tape', yt(_casey, 4341)),
        ('ใส่คลิปเร็ว · Smart insert / Append', yt(_casey, 4341)),
        ('ตัด / เล็ม · Blade & trim', yt(_casey, 4341)),
        ('แยกฉากอัตโนมัติ · Scene detect', ytSearch('DaVinci Resolve scene cut detection')),
      ]),
      ('บท 4 ตัวหนังสือ + Fusion', yt(_casey, 5588), [
        ('Text+', yt(_casey, 5588)),
        ('ขยับด้วย Keyframe', yt(_casey, 5588)),
        ('ป้ายชื่อด้านล่าง · Lower third', ytSearch('DaVinci Resolve lower third Fusion')),
        ('ทำ Template เอง', ytSearch('DaVinci Resolve Fusion macro title template')),
      ]),
      ('บท 5 สี (Color)', yt(_casey, 8886), [
        ('วงล้อสีหลัก · Primary wheels', yt(_casey, 8886)),
        ('อ่านกราฟสี · Scopes', yt(_casey, 8886)),
        ('Node พื้นฐาน', yt(_casey, 8886)),
        ('LUT', ytSearch('DaVinci Resolve LUT beginner')),
        ('คัดลอกสีไปคลิปอื่น · Copy grade', ytSearch('DaVinci Resolve copy grade')),
      ]),
      ('บท 6 เสียง (Fairlight)', yt(_casey, 14679), [
        ('ปรับเสียงให้เท่ากัน -14 LUFS · Normalize', yt(_casey, 14679)),
        ('ลดเสียงรบกวน · Noise reduction', ytSearch('DaVinci Resolve noise reduction Fairlight')),
        ('เพลงเบาลงตอนพูด · Ducking', ytSearch('DaVinci Resolve audio ducking')),
        ('แยกเสียงพูด · Voice isolation', ytSearch('DaVinci Resolve voice isolation')),
      ]),
      ('บท 7 Deliver ส่งออก', yt(_casey, 16035), [
        ('Render สำหรับ YouTube', yt(_casey, 16035)),
        ('Shorts 9:16', ytSearch('DaVinci Resolve vertical video shorts')),
      ]),
      ('บท 8 Workflow ตัดไลฟ์ (บทของเราเอง)', null, [
        ('หา Highlight (ปักหมุดระหว่างไลฟ์)', ytSearch('DaVinci Resolve edit livestream highlights')),
        ('ตัด 1 ชม. → 10 นาที', ytSearch('DaVinci Resolve edit long video fast')),
        ('Shorts จากไลฟ์', ytSearch('DaVinci Resolve shorts from stream')),
      ]),
      ('บท 9 Speed challenge', null, [
        ('จับเวลา ตัดคลิป 1 ชม. ครั้งที่ 1', null),
        ('ครั้งที่ 2', null),
        ('ครั้งที่ 3 (เป้า ≤ 90 นาที)', null),
        ('สรุปคีย์ลัด / ขั้นที่เสียเวลา', null),
      ]),
    ],
  ),
  (
    'canva',
    'Canva',
    '🎨',
    [
      ('บท 1 พื้นฐาน (สอนไทย ต้น-จบ)', yt(_canvaTh), [
        ('หน้าจอ + เมนู · Workspace', yt(_canvaTh)),
        ('ภาพ / ตัวหนังสือ · Elements & text', yt(_canvaTh)),
        ('เลเยอร์ / จัดกลุ่ม', yt(_canvaTh)),
        ('เริ่มจาก Template', yt(_canvaTh)),
        ('คอร์สเต็มภาษาอังกฤษ (เสริม)', yt(_kes)),
      ]),
      ('บท 2 Brand kit Noir Lev', null, [
        ('โลโก้', yt(_kes, 460)),
        ('สีประจำช่อง', ytSearch('Canva brand kit colors')),
        ('ฟอนต์ไทย + อังกฤษ', ytSearch('Canva ฟอนต์ไทย')),
        ('Template ของช่อง', ytSearch('Canva create template brand')),
      ]),
      ('บท 3 หลักออกแบบ', null, [
        ('อะไรเด่นก่อน · Hierarchy', ytSearch('graphic design hierarchy thumbnail')),
        ('สีตัดกัน · Contrast', ytSearch('graphic design contrast beginner')),
        ('ตัวหนังสือบนรูป', ytSearch('text on image design tips')),
        ('จัดวางสามส่วน · Rule of thirds', ytSearch('rule of thirds design')),
      ]),
      ('บท 4 ปก YouTube / ไลฟ์', yt(_kes, 1848), [
        ('ขนาด 1280×720', yt(_kes, 1848)),
        ('ปกใส่ภาษาไทย', yt(_coverTh)),
        ('หน้าตัวเอง + ข้อความ 3 คำ', yt(_coverTh2)),
        ('ลบพื้นหลัง · Background remover', yt(_kes, 3294)),
        ('ลองปก 2 แบบ · A/B', ytSearch('YouTube thumbnail A/B test')),
      ]),
      ('บท 5 แต่งรูป', yt(_kes, 2017), [
        ('ปรับแสง / สี', yt(_kes, 2017)),
        ('ครอป / ขยาย', yt(_kes, 2017)),
      ]),
      ('บท 6 Shorts / Social', null, [
        ('แนวตั้ง 9:16', ytSearch('Canva vertical video shorts')),
        ('โพสต์ประกาศไลฟ์', ytSearch('Canva stream schedule post')),
        ('Story', ytSearch('Canva story design')),
      ]),
      ('บท 7 ภาพเว็บ mecsteam (บทของเราเอง)', null, [
        ('ครอป / ย่อภาพผลงาน', ytSearch('Canva resize image website')),
        ('ใส่ลายน้ำ', ytSearch('Canva watermark')),
        ('Export เบา คมชัด · WebP', ytSearch('Canva export compress image')),
      ]),
      ('บท 8 Speed', null, [
        ('Template ปก ≤ 30 นาที', null),
        ('เครื่องมือ AI ใน Canva · Magic tools', ytSearch('Canva magic studio tutorial')),
        ('จับเวลา 3 ครั้ง', null),
      ]),
    ],
  ),
  (
    'อังกฤษพื้นฐาน',
    englishB1Skill,
    '📘',
    [
      ('บท 1 ประโยคพื้นฐาน (ครูดิว)', ytChannel(_dew, 'พื้นฐาน'), [
        ('ชนิดของคำ · Parts of speech', _kd('ชนิดของคำ')),
        ('โครงสร้างประโยค ประธาน + กริยา + กรรม', _kd('โครงสร้างประโยค')),
        ('Verb to be · is / am / are', _kd('verb to be')),
        ('คำนามนับได้ / นับไม่ได้ · a / an / the', _kd('article a an the')),
      ]),
      ('บท 2 ปัจจุบัน · Present (ครูดิว)', _kd('present tense'), [
        ('Present simple', _kd('present simple')),
        ('Present continuous', _kd('present continuous')),
        ('ฟังเรื่องชีวิตประจำวัน (Vanessa)', _vn('daily routine')),
      ]),
      ('บท 3 อดีต · Past (ครูดิว)', _kd('past tense'), [
        ('Past simple', _kd('past simple')),
        ('กริยา 3 ช่องที่ใช้บ่อย · Irregular verbs', _kd('กริยา 3 ช่อง')),
        ('Past continuous', _kd('past continuous')),
        ('ฟังเล่าเรื่องในอดีต (Vanessa)', _vn('past tense story')),
      ]),
      ('บท 4 อนาคต + Perfect (ครูดิว)', _kd('future tense'), [
        ('Will / be going to', _kd('will going to')),
        ('Present perfect', _kd('present perfect')),
        ('สรุปทุก Tense', _kd('tense ทั้งหมด')),
      ]),
      ('บท 5 คำถาม + Modal verbs', _kd('modal verb'), [
        ('ประโยคคำถาม Wh- / Yes-No', _kd('ประโยคคำถาม')),
        ('Can / should / must / have to', _kd('modal verb')),
        ('ถามตอบในชีวิตจริง (Vanessa)', _vn('questions conversation')),
      ]),
      ('บท 6 ประโยคยาวขึ้น (ครูดิว)', _kd('ตัวเชื่อม'), [
        ('คำเชื่อม · and / but / because / so', _kd('ตัวเชื่อม')),
        ('ขั้นกว่า ขั้นสุด · Comparison', _kd('comparative superlative')),
        ('Relative clause · who / which / that', _kd('relative clause')),
        ('Passive voice', _kd('passive voice')),
        ('If · Conditionals', _kd('if clause')),
      ]),
      ('บท 7 คำศัพท์ (คลังศัพท์ A1–B2)', null, [
        ('A1 ครบ', null),
        ('A2 ครบ', null),
        ('B1 ครบ', null),
        ('B2 (เริ่ม)', null),
      ]),
      ('บท 8 ฟัง (Vanessa · พูดช้า ชัด)', 'https://www.youtube.com/@$_vanessa', [
        ('ฟังเรื่องชีวิตประจำวัน', _vn('daily life English')),
        ('ประโยคที่ใช้บ่อย · Common phrases', _vn('common phrases')),
        ('พูดตาม · Shadowing', _vn('shadowing')),
        ('ฟังไม่เปิดซับ เข้าใจ 70% ขึ้นไป', _vn('listening practice')),
      ]),
      ('บท 9 พูด + ออกเสียง', _vn('pronunciation'), [
        ('ออกเสียงให้ชัด · Pronunciation', _vn('pronunciation')),
        ('แนะนำตัวเอง 1 นาที', _vn('introduce yourself')),
        ('อัดเสียงตัวเองฟัง', null),
      ]),
      ('บท 10 วัดระดับ B1', 'https://www.efset.org/', [
        ('ทำแบบทดสอบ EF SET (ฟรี · บอกระดับ CEFR)', 'https://www.efset.org/'),
        ('ได้ B1 → เริ่มบท IELTS', null),
      ]),
    ],
  ),
  (
    'ielts',
    'IELTS',
    '🇬🇧',
    [
      ('บท 1 รู้จัก IELTS + วัดระดับ', ytSearch('E2 IELTS test format'), [
        ('รูปแบบข้อสอบ 4 ทักษะ · Test format', ytSearch('E2 IELTS test format')),
        ('เกณฑ์ Band 1–9 · Band descriptors', ytSearch('IELTS band descriptors explained')),
        ('ทำแบบทดสอบวัดระดับ · Diagnostic test', ytSearch('IELTS full practice test')),
        ('ตั้งเป้ารายทักษะ · Target band', null),
      ]),
      ('บท 2 Listening (E2 IELTS)', ytSearch('E2 IELTS listening'), [
        ('Part 1–2 ข้อมูลทั่วไป ตัวเลข สะกดชื่อ · Section 1–2', ytSearch('E2 IELTS listening section 1')),
        ('Part 3–4 บทสนทนา / บรรยาย · Section 3–4', ytSearch('E2 IELTS listening section 4')),
        ('เติมแบบฟอร์ม / โน้ต · Form & note completion', ytSearch('IELTS listening form completion tips')),
        ('ตัวเลือก · Multiple choice', ytSearch('IELTS listening multiple choice tips')),
        ('แผนที่ / แผนผัง · Map labelling', ytSearch('IELTS listening map labelling')),
      ]),
      ('บท 3 Reading (E2 IELTS)', ytSearch('E2 IELTS reading'), [
        ('อ่านเร็ว จับใจความ / หาคำ · Skimming & scanning', ytSearch('E2 IELTS reading skimming scanning')),
        ('จริง / ไม่จริง / ไม่ได้บอก · True / False / Not Given', ytSearch('E2 IELTS true false not given')),
        ('จับคู่หัวข้อ · Matching headings', ytSearch('E2 IELTS matching headings')),
        ('เติมประโยค · Sentence completion', ytSearch('IELTS reading sentence completion')),
        ('จับเวลา 60 นาที · Timed practice', null),
      ]),
      ('บท 4 Writing Task 1 อธิบายกราฟ (IELTS Advantage)', ytSearch('IELTS Advantage writing task 1'), [
        ('อ่านกราฟ เส้น / แท่ง / วงกลม / ตาราง · Charts', ytSearch('IELTS Advantage task 1 line graph')),
        ('ขั้นตอน / แผนที่ · Process & map', ytSearch('IELTS writing task 1 process diagram')),
        ('โครง 4 ย่อหน้า · Structure', ytSearch('IELTS Advantage task 1 structure')),
        ('ภาษาบอกแนวโน้ม + เปรียบเทียบ · Trend language', ytSearch('IELTS task 1 trend vocabulary')),
      ]),
      ('บท 5 Writing Task 2 เรียงความ (IELTS Advantage)', ytSearch('IELTS Advantage writing task 2'), [
        ('ประเภทคำถาม · Question types', ytSearch('IELTS Advantage task 2 question types')),
        ('โครง 4 ย่อหน้า · Essay structure', ytSearch('IELTS Advantage essay structure')),
        ('ประโยคหลักแต่ละย่อหน้า · Thesis & topic sentence', ytSearch('IELTS task 2 thesis statement')),
        ('คำเชื่อม · Linking words', ytSearch('IELTS linking words writing')),
        ('เกณฑ์ตรวจ 4 ข้อ · Marking criteria', ytSearch('IELTS writing marking criteria')),
      ]),
      ('บท 6 Speaking (IELTS Liz)', ytSearch('IELTS Liz speaking'), [
        ('Part 1 คุยเรื่องตัวเอง', ytSearch('IELTS Liz speaking part 1')),
        ('Part 2 พูดคนเดียว 2 นาที · Cue card', ytSearch('IELTS Liz speaking part 2')),
        ('Part 3 แสดงความเห็น', ytSearch('IELTS Liz speaking part 3')),
        ('พูดลื่น + ออกเสียง · Fluency & pronunciation', ytSearch('IELTS speaking fluency pronunciation tips')),
        ('อัดเสียงตัวเองฟัง · Self-recording', null),
      ]),
      ('บท 7 คำศัพท์ + Grammar', ytSearch('E2 IELTS grammar'), [
        ('คำศัพท์วิชาการ · AWL', ytSearch('academic word list IELTS')),
        ('คำที่มักใช้คู่กัน · Collocations', ytSearch('IELTS collocations')),
        ('ประโยคซับซ้อน · Complex sentences', ytSearch('E2 IELTS complex sentences')),
        ('Tense / Passive / Conditionals', ytSearch('E2 IELTS grammar tenses')),
      ]),
      ('บท 8 ข้อสอบเก่า (Cambridge IELTS)', null, [
        ('ชุดที่ 1 · Test 1', null),
        ('ชุดที่ 2 · Test 2', null),
        ('ชุดที่ 3 · Test 3', null),
        ('ชุดที่ 4 · Test 4', null),
        ('สรุปจุดที่ผิดบ่อย · Error log', null),
      ]),
      ('บท 9 Mock + สมัครสอบ', null, [
        ('Mock เต็ม จับเวลา ครั้งที่ 1', ytSearch('IELTS full mock test')),
        ('Mock เต็ม ครั้งที่ 2', null),
        ('เลือกศูนย์สอบ + สมัคร · BC / IDP', null),
        ('เตรียมวันสอบ · Test day', ytSearch('IELTS test day tips')),
      ]),
    ],
  ),
];

/// ทักษะย่อยเดิมที่แผนนัวร์ (รอบ 10) ใส่ให้ · ยังว่าง (ไม่มีหัวข้อ / ไม่ติ๊ก) = แทนด้วยสารบัญ
const legacyPlanNodes = {
  'Vocab', 'Listening', 'Reading', 'Writing', 'Speaking', 'Mock test', //
  'Cut / Edit (คีย์ลัด)', 'Color', 'Fairlight เสียง', 'Fusion ตัวหนังสือ',
  'Brand kit Noir Lev', 'ปก YouTube', 'Shorts / โพสต์', 'ภาพเว็บ mecsteam',
};

/// หาสกิลตามคำค้น (ชื่อมีคำนี้ ไม่สนตัวพิมพ์)
Skill? skillByKey(List<Skill> skills, String key) => skills.where((s) => s.name.toLowerCase().contains(key)).firstOrNull;

typedef LessonResult = ({int skills, int chapters, int topics, int removed});

/// ใส่สารบัญ (ชื่อซ้ำ = ข้าม · กดซ้ำได้) · สกิลยังไม่มี = สร้าง · ทักษะย่อยเดิมที่ว่างของแผนเก่า = ลบ
Future<LessonResult> applyLessonPresets(SkillRepository r) async {
  var skills = 0, chapters = 0, topics = 0, removed = 0;
  final all = await r.skills();
  int? newB1;
  for (final (key, name, icon, toc) in lessonPresets) {
    var skillId = skillByKey(all, key)?.id;
    if (skillId == null) {
      // อังกฤษพื้นฐานอยู่สายเดียวกับ IELTS (สาย "ภาษา" จากแผนนัวร์ ถ้ามี)
      final lang = key == 'อังกฤษพื้นฐาน' ? (await r.branches()).where((b) => b.name == 'ภาษา').firstOrNull?.id : null;
      skillId = await r.saveSkill(Skill(name: name, icon: icon, branchId: lang, startedAt: DateTime.now()));
      if (key == 'อังกฤษพื้นฐาน') newB1 = skillId;
      skills++;
    }
    var nodes = (await r.nodes()).where((n) => n.skillId == skillId).toList();
    var allTopics = await r.topics();
    for (final n in nodes) {
      final empty = !n.done && !allTopics.any((t) => t.nodeId == n.id);
      if (empty && legacyPlanNodes.contains(n.name)) {
        await r.deleteNode(n.id);
        removed++;
      }
    }
    nodes = (await r.nodes()).where((n) => n.skillId == skillId).toList();
    allTopics = await r.topics();
    for (final (ci, (chName, chUrl, list)) in toc.indexed) {
      final have = nodes.where((n) => n.name == chName).firstOrNull;
      final nodeId = have?.id ?? await r.saveNode(SkillNode(skillId: skillId, name: chName, sort: ci, url: chUrl));
      if (have == null) chapters++;
      final names = {for (final t in allTopics) if (t.nodeId == nodeId) t.name};
      for (final (ti, (tName, tUrl)) in list.indexed) {
        if (names.contains(tName)) continue;
        await r.saveTopic(SkillTopic(nodeId: nodeId, name: tName, sort: ti, url: tUrl));
        topics++;
      }
    }
  }
  // IELTS ต้องผ่านพื้นฐานก่อน (แค่เตือน) · ใส่ครั้งเดียวตอนสร้างพื้นฐาน นัวร์ลบเองได้
  final ielts = skillByKey(await r.skills(), 'ielts');
  if (newB1 != null && ielts != null) await r.addNeed(ielts.id, newB1);
  return (skills: skills, chapters: chapters, topics: topics, removed: removed);
}
