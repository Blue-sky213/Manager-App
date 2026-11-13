import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/calendar/sqlite_calendar_repository.dart' show createCalendarSchema, createCalendarV5, createCalendarV7;
import 'package:noir_manager/data/app_database.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/data/sqlite_study_repository.dart';
import 'package:noir_manager/data/study_models.dart';
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
      GradeSetup(
          scale: withFCut(kuGradeScale, 45),
          flags: const GradeFlags(missedExam: true, absentCount: 3, classTotal: 30, absentLimit: 25),
          official: 'B'));
  final g = await repo.gradeSetup(sid);
  expect(g.flags.absentCount, 3);
  expect(g.flags.classTotal, 30);
  expect(g.flags.absentLimit, 25);
  expect(fCutOf(g.scale), 45);
  expect(g.flags.missedExam, isTrue);
  expect(g.official, 'B');

  await repo.deleteGradeItem(parts.first.items.last.id);
  await repo.deleteGradePart(mid);
  parts = await repo.gradeParts(sid);
  expect(parts.single.items.length, 4);

  // บันทึกคาบ (ไม่ผูกคาบในปฏิทิน): บทยังไม่เริ่ม → กำลังติว · ลบบท → บันทึกยังอยู่
  final ch = await repo.addChapter(sid, 'บท 1');
  await repo.logClass(sid, DateTime(2026, 11, 10, 9, 30),
      chapterId: ch, finished: true, note: ' ', topics: ['for', 'while'], homework: 'การบ้าน 1', dueAt: DateTime(2026, 11, 17, 23, 59));
  final log = (await repo.classLogs(sid)).single;
  expect(log.topics, ['for', 'while']);
  expect(log.homework, 'การบ้าน 1');
  expect(log.dueAt, DateTime(2026, 11, 17, 23, 59));
  expect(log.day, DateTime(2026, 11, 10));
  expect(log.finished, isTrue);
  expect(log.note, isNull);
  expect((await repo.chapters(sid)).single.chapter.status, ChapterStatus.learning);
  await repo.deleteChapter(ch);
  expect((await repo.classLogs(sid)).single.chapterId, isNull);

  // ลบวิชา → คะแนน + บันทึกคาบหายตาม
  await repo.deleteSubject(sid);
  expect(await repo.gradeParts(sid), isEmpty);
  expect(await repo.classLogs(sid), isEmpty);
}

void main() {
  test('RAM: เก็บส่วนคะแนน / ชิ้นคะแนน / ตั้งค่าเกรด', () async {
    await gradeRepoRules(MemoryStudyRepository());
  });

  test('SQLite: migration v13–15 รันซ้ำได้ · กฎเหมือน RAM', () async {
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
    await createClassLogV14(db);
    await createClassLogV15(db);
    await createClassLogV14(db); // รันซ้ำก็ไม่พัง
    await createClassLogV15(db);
    await createRound7V17(db); // v17: คอลัมน์รอบ 7
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
    final a = computeGrade(sample(fin: 40), kuGradeScale, const GradeFlags(absentCount: 6, classTotal: 26));
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

  test('ขาดเรียน: แอปคิด % เอง · 20% พอดียังไม่ F · บอกว่าขาดได้อีกกี่คาบ', () {
    const ok = GradeFlags(absentCount: 4, classTotal: 30);
    expect(ok.absentPercent, closeTo(13.33, 0.01));
    expect(ok.absentLeft, 2);
    expect(ok.absentOver, isFalse);
    expect(const GradeFlags(absentCount: 6, classTotal: 30).absentOver, isFalse); // 20% พอดี
    expect(const GradeFlags(absentCount: 7, classTotal: 30).absentOver, isTrue);
    expect(const GradeFlags(absentCount: 7).absentOver, isFalse); // ยังไม่รู้คาบทั้งหมด
    expect(const GradeFlags(absentCount: 7).absentLeft, isNull);
  });

  test('โอกาสปรับปรุง: เสียตรงไหน · ขาดอีกกี่คะแนนถึงเกรดถัดไป · เกรดจริงไม่ตรง', () {
    final tips = gradeFeedback(sample(fin: 30), const GradeSetup(official: 'B'));
    expect(tips.join('\n'), contains('เสียคะแนนมากสุด: ปลายภาค −10 · กลางภาค −5'));
    expect(tips.join('\n'), contains('ขาดอีก 1 คะแนนจะได้ A'));
    expect(tips.join('\n'), contains('เกรดจริง B ต่ำกว่าที่คำนวณ (B+)'));

    final absent = gradeFeedback(sample(fin: 30), const GradeSetup(flags: GradeFlags(absentCount: 5, classTotal: 30)));
    expect(absent.join('\n'), contains('ขาดเรียนได้อีกแค่ 1 คาบ'));
    expect(gradeFeedback(const [], const GradeSetup()), isEmpty);
  });
}
