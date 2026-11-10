import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/data/app_database.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/data/sqlite_study_repository.dart';
import 'package:noir_manager/data/study_repository.dart';
import 'package:noir_manager/study/grading.dart';

GradePart part(int id, String name, double weight, List<(double, double?)> items) => GradePart(
      id: id,
      name: name,
      weight: weight,
      items: [
        for (final (i, (full, got)) in items.indexed)
          GradeItem(id: id * 100 + i, name: '$name ${i + 1}', full: full, got: got),
      ],
    );

/// กฎเก็บคะแนนเหมือนกันทั้ง RAM และ SQLite
Future<void> gradeRepoRules(StudyRepository repo) async {
  final sid = await repo.addSubject('การเขียนโปรแกรม');
  final work = await repo.addGradePart(sid, 'งาน', 20, items: 4, itemFull: 5);
  final mid = await repo.addGradePart(sid, 'กลางภาค', 20);
  var parts = await repo.gradeParts(sid);
  expect(parts.map((p) => p.name), ['งาน', 'กลางภาค']);
  expect(parts.first.items.map((i) => i.name), ['งาน 1', 'งาน 2', 'งาน 3', 'งาน 4']);
  expect(parts.last.items.single.full, 20);

  // ใส่คะแนน → ลบคะแนน → แก้คะแนนเต็ม
  final w1 = parts.first.items.first.id;
  await repo.updateGradeItem(w1, got: 4);
  await repo.updateGradeItem(parts.last.items.single.id, got: 15);
  parts = await repo.gradeParts(sid);
  expect(parts.first.earned, closeTo(4 / 20 * 20, 1e-9));
  await repo.updateGradeItem(w1, clearGot: true);
  await repo.addGradeItem(work, 'งาน 5', 5);
  await repo.updateGradePart(mid, weight: 30, name: 'สอบกลางภาค');
  parts = await repo.gradeParts(sid);
  expect(parts.first.items.first.got, isNull);
  expect(parts.first.items.length, 5);
  expect(parts.last.name, 'สอบกลางภาค');
  expect(parts.last.weight, 30);

  // ตั้งค่าเกรด: ค่าเริ่มต้น = ตาราง มก. · บันทึกแล้วอ่านกลับได้
  expect((await repo.gradeSetup(sid)).scale, kuGradeScale);
  await repo.setGradeSetup(sid,
      GradeSetup(scale: withFCut(kuGradeScale, 45), flags: const GradeFlags(missedExam: true), official: 'B'));
  final g = await repo.gradeSetup(sid);
  expect(fCutOf(g.scale), 45);
  expect(g.flags.missedExam, isTrue);
  expect(g.official, 'B');

  await repo.deleteGradeItem(parts.first.items.last.id);
  await repo.deleteGradePart(mid);
  parts = await repo.gradeParts(sid);
  expect(parts.single.items.length, 4);

  // ลบวิชา → คะแนนหายตาม
  await repo.deleteSubject(sid);
  expect(await repo.gradeParts(sid), isEmpty);
}

void main() {
  test('RAM: เก็บส่วนคะแนน / ชิ้นคะแนน / ตั้งค่าเกรด', () async {
    await gradeRepoRules(MemoryStudyRepository());
  });

  test('SQLite: migration v13 รันซ้ำได้ · กฎเหมือน RAM', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')));
    await createStudySchema(db);
    await createSettingSchema(db);
    await createCalendarSchema(db);
    await createCalendarV5(db);
    await createCalendarV7(db);
    await createStudyPlanV8(db);
    await createTutorV9(db);
    await createTermV10(db);
    await createClassInfoV11(db);
    await createSubjectLinkV12(db);
    await createGradeV13(db);
    await createGradeV13(db); // รันซ้ำก็ไม่พัง
    await gradeRepoRules(SqliteStudyRepository(db));
    await db.close();
  });

  // ตัวอย่างที่นัวร์อนุมัติ: งาน 20 · สอบย่อย 15 · เข้าเรียน 5 · กลางภาค 20 · ปลายภาค 40
  List<GradePart> sample({double? fin}) => [
        part(1, 'งาน', 20, [(5, 5), (5, 5), (5, 4), (5, 3)]),
        part(2, 'สอบย่อย', 15, [(5, 4), (5, 5), (5, 3)]),
        part(3, 'เข้าเรียน', 5, [(5, 5)]),
        part(4, 'กลางภาค', 20, [(20, 15)]),
        part(5, 'ปลายภาค', 40, [(40, fin)]),
      ];

  test('ตาราง มก.: 80 = A · 79.9 = B+ · 50 = D · 49 = F', () {
    expect(letterFor(80, kuGradeScale), 'A');
    expect(letterFor(79.9, kuGradeScale), 'B+');
    expect(letterFor(55, kuGradeScale), 'D+');
    expect(letterFor(50, kuGradeScale), 'D');
    expect(letterFor(49, kuGradeScale), 'F');
  });

  test('ก่อนปลายภาค: เก็บได้ 49/60 · ยังไม่ครบ · ต้องได้ปลายภาค ≥ 31 ถึงได้ A', () {
    final r = computeGrade(sample(), kuGradeScale);
    expect(r.earned, closeTo(49, 1e-9));
    expect(r.decided, closeTo(60, 1e-9));
    expect(r.remaining, closeTo(40, 1e-9));
    expect(r.complete, isFalse);
    expect(neededFor(r, kuGradeScale.first), closeTo(31, 1e-9)); // A
    expect(neededFor(r, kuGradeScale.last), closeTo(1, 1e-9)); // D
  });

  test('ใส่ปลายภาค 30 → 79 = B+ · ครบแล้ว', () {
    final r = computeGrade(sample(fin: 30), kuGradeScale);
    expect(r.earned, closeTo(79, 1e-9));
    expect(r.letter, 'B+');
    expect(r.complete, isTrue);
  });

  test('ขาดเรียนเกิน 20% / ขาดสอบ → F ทันที', () {
    final a = computeGrade(sample(fin: 40), kuGradeScale, const GradeFlags(absentOver: true));
    expect(a.letter, 'F');
    expect(a.reason, contains('ขาดเรียน'));
    final m = computeGrade(sample(fin: 40), kuGradeScale, const GradeFlags(missedExam: true));
    expect(m.letter, 'F');
    expect(neededFor(m, kuGradeScale.first), double.infinity);
  });

  test('สอบย่อยดิบเต็ม 60 เก็บ 15: ได้ 48/60 → 12 คะแนน', () {
    final p = part(1, 'สอบย่อย', 15, [(20, 16), (20, 16), (20, 16)]);
    expect(p.earned, closeTo(12, 1e-9));
  });

  test('อาจารย์ตัด F ที่ 45 → 46 ได้ D · อ่าน/เขียนช่วงเกรดกลับได้เหมือนเดิม', () {
    final s = withFCut(kuGradeScale, 45);
    expect(letterFor(46, s), 'D');
    expect(letterFor(45, s), 'F');
    expect(fCutOf(s), 45);
    final back = parseScale(encodeScale(s));
    expect(back.map((b) => '${b.letter}${b.min}'), s.map((b) => '${b.letter}${b.min}'));
    expect(parseScale('เสีย'), kuGradeScale);
  });

  test('คะแนนรวมไม่ถึง 100 → เทียบเป็น 100 ก่อนตัดเกรด', () {
    final r = computeGrade([part(1, 'สอบ', 50, [(50, 40)])], kuGradeScale);
    expect(r.percent, closeTo(80, 1e-9));
    expect(r.letter, 'A');
  });

  test('GPA: ตัวอย่าง 6 วิชา = 3.19 · S/U และยังไม่มีเกรดไม่นับ', () {
    final g = gpa([(3, 'B'), (3, 'B+'), (3, 'A'), (3, 'D+'), (3, 'A'), (1, 'B'), (1, 'S'), (3, '—')]);
    expect(g!.toStringAsFixed(2), '3.19');
    expect(gpa([(3, 'S')]), isNull);
  });
}
