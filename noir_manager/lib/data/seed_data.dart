/// ข้อมูลตั้งต้นตอนเปิดแอปครั้งแรก: วิชาทดสอบ DaVinci Resolve (ตาม Roadmap Phase 1)
/// มีแค่โครงบท/หัวข้อย่อย ไม่มีคะแนน — คะแนนนัวร์ประเมินเองในแอป
library;

class SeedChapter {
  const SeedChapter(this.name, [this.subtopics = const []]);
  final String name;
  final List<String> subtopics;
}

const String seedSubjectName = 'DaVinci Resolve';
const int seedSubjectImportance = 3; // สูง → 3 รอบ/สัปดาห์

const List<SeedChapter> seedChapters = [
  SeedChapter('บท 1 · Interface & Media', [
    '1.1 หน้า Media Pool',
    '1.2 ตั้งค่า Project',
    '1.3 Import & Proxy',
    '1.4 Keyboard Shortcut',
  ]),
  SeedChapter('บท 2 · Edit Page'),
  SeedChapter('บท 3 · Color'),
  SeedChapter('บท 4 · Fairlight'),
  SeedChapter('บท 5 · Deliver'),
];
