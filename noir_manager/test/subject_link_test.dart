import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/calendar/sqlite_calendar_repository.dart';
import 'package:noir_manager/data/app_database.dart';
import 'package:noir_manager/data/demo_term.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/data/sqlite_study_repository.dart';
import 'package:noir_manager/data/study_repository.dart';
import 'package:noir_manager/study/curriculum_map.dart';

/// เส้นวิชาที่ต้องเรียนก่อน: กฎเดียวกันทั้ง RAM และ SQLite
Future<void> linkRules(StudyRepository repo) async {
  final a = await repo.addSubject('คณิต 1');
  final b = await repo.addSubject('คณิต 2');
  final c = await repo.addSubject('คณิต 3');

  await repo.addSubjectLink(a, b);
  await repo.addSubjectLink(a, b); // ซ้ำ → ไม่เพิ่ม
  await repo.addSubjectLink(b, b); // ชี้หาตัวเอง → ไม่เพิ่ม
  await repo.addSubjectLink(b, c);
  expect(await repo.subjectLinks(), [(from: a, to: b), (from: b, to: c)]);

  await repo.removeSubjectLink(a, b);
  expect(await repo.subjectLinks(), [(from: b, to: c)]);

  // ลบวิชา → เส้นของวิชานั้นหายตาม
  await repo.deleteSubject(c);
  expect(await repo.subjectLinks(), isEmpty);
}

void main() {
  test('RAM: เพิ่ม / ซ้ำ / ชี้ตัวเอง / ลบเส้น / ลบวิชาแล้วเส้นหาย', () async {
    await linkRules(MemoryStudyRepository());
  });

  test('SQLite: migration v12 รันซ้ำได้ · กฎเส้นเหมือน RAM', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')));
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
    await createSubjectLinkV12(db); // รันซ้ำก็ไม่พัง
    await createRound7V17(db); // v17: คอลัมน์รอบ 7
    await linkRules(SqliteStudyRepository(db));
    await db.close();
  });

  test('แผน 4 ปีตัวอย่าง: ได้เส้นตามหลักสูตรครบ · กดซ้ำไม่เพิ่ม · เส้นที่ทำเองไม่หาย', () async {
    final study = MemoryStudyRepository();
    await loadDemoCurriculum(study, MemoryCalendarRepository());
    final links = await study.subjectLinks();
    expect(links, hasLength(curriculumLinks.length));

    final byName = {for (final s in await study.subjects()) s.name: s.id};
    expect(links, contains((from: byName['คณิตศาสตร์วิศวกรรม 1']!, to: byName['คณิตศาสตร์วิศวกรรม 2']!)));

    final own = (from: byName['ภาษาอังกฤษ 2']!, to: byName['ผู้ประกอบการนวัตกรรม']!);
    await study.addSubjectLink(own.from, own.to);
    expect(await loadCurriculumLinks(study), 0);
    expect(await study.subjectLinks(), contains(own));
  });

  test('สายความสัมพันธ์: ไล่ขึ้น + ไล่ลงทั้งสาย ไม่ติดเส้นข้างเคียง', () {
    // 1 → 2 → 3 · 4 → 2 · 2 → 5 · 6 → 5 (6 เป็นเส้นข้างเคียงของ 5 ไม่ใช่สายของ 1)
    const links = [
      (from: 1, to: 2), (from: 2, to: 3), (from: 4, to: 2), (from: 2, to: 5), (from: 6, to: 5),
    ];
    final ch = linkChain(links, 2);
    expect(ch.nodes, {1, 2, 3, 4, 5});
    expect(ch.edges, hasLength(4));
    expect(ch.edges.contains((from: 6, to: 5)), isFalse);
    expect(linkChain(links, null).nodes, isEmpty);
  });
}
