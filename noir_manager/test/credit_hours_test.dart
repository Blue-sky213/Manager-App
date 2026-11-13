import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/calendar/sqlite_calendar_repository.dart';
import 'package:noir_manager/data/app_database.dart';
import 'package:noir_manager/study/credit_hours.dart';

/// คาบเรียนประจำทุกสัปดาห์ (ใช้ในเทสนี้)
NewActivity cls(Set<int> days, int start, int minutes,
        {ClassInfo info = ClassInfo.none, DateTime? from, DateTime? to}) =>
    NewActivity(
      name: 'เรียน · การเขียนโปรแกรม',
      categoryId: 1,
      importance: 3,
      timed: true,
      day: from ?? DateTime(2026, 11, 2),
      startMinute: start,
      durationMin: minutes,
      repeat: RepeatKind.weekly,
      weekdays: days,
      endDate: to ?? DateTime(2027, 2, 5),
      subjectId: 7,
      kind: ActivityKind.classSession,
      classInfo: info,
    );

const theory = ClassInfo(type: ClassType.theory, room: '1-B4-01-A', section: 'S.1');
const lab = ClassInfo(type: ClassType.lab, room: '1-B4-01-A', section: 'L.1');

void main() {
  group('อ่านหน่วยกิต', () {
    test('3(2-2-5) → ทฤษฎี 2 · ปฏิบัติ 2 · ศึกษาเอง 5', () {
      final h = parseCreditHours('3(2-2-5)')!;
      expect([h.credits, h.theory, h.lab, h.self], [3, 2, 2, 5]);
    });
    test('มีช่องว่างก็อ่านได้ · รูปแบบอื่นคืน null', () {
      expect(parseCreditHours(' 1 ( 0 - 3 - 1 ) ')!.lab, 3);
      expect(parseCreditHours('1(240 ชม.)'), isNull);
      expect(parseCreditHours(null), isNull);
      expect(parseCreditHours(''), isNull);
    });
  });

  group('ชั่วโมงเรียนต่อสัปดาห์', () {
    test('ทฤษฎี 2 ชม. + ปฏิบัติ 2 ชม. ตรงกับ 3(2-2-5) → ผ่าน', () {
      final acts = [
        cls({4}, 8 * 60, 120, info: theory).toActivity(id: 1),
        cls({4}, 10 * 60, 120, info: lab).toActivity(id: 2),
      ];
      final c = checkCredits('3(2-2-5)', acts)!;
      expect(c.theory.status, HourStatus.ok);
      expect(c.lab.status, HourStatus.ok);
      expect(c.allOk, isTrue);
    });

    test('คาบเดียวกันแยกช่วงก่อน/หลังสอบกลางภาค นับครั้งเดียว', () {
      final acts = [
        cls({3}, 9 * 60, 180, info: theory, to: DateTime(2026, 12, 18)).toActivity(id: 1),
        cls({3}, 9 * 60, 180, info: theory, from: DateTime(2027, 1, 4)).toActivity(id: 2),
      ];
      expect(weeklyClassMinutes(acts).theory, 180);
    });

    test('ขาด / เกิน / ไม่ระบุประเภท', () {
      final short = checkCredits('3(2-2-5)', [cls({1}, 9 * 60, 60, info: theory).toActivity(id: 1)])!;
      expect(short.theory.status, HourStatus.short);
      expect(short.lab.status, HourStatus.short);

      final over = checkCredits('1(0-2-1)', [cls({1, 3}, 10 * 60, 120, info: lab).toActivity(id: 1)])!;
      expect(over.lab.status, HourStatus.over);

      // คาบเก่าก่อน v11: รวมตรง 4 ชม. แต่ยังไม่ตั้งประเภท
      final old = checkCredits('3(2-2-5)', [cls({2}, 13 * 60, 240).toActivity(id: 1)])!;
      expect(old.unknown, 240);
      expect(old.totalMatchesOnly, isTrue);
      expect(old.allOk, isFalse);
    });

    test('ไม่นับงานทั่วไป ติว หรือวันสอบ', () {
      final tutor = NewActivity(
        name: 'ติว', categoryId: 1, importance: 2, timed: true, day: DateTime(2026, 11, 2),
        startMinute: 600, durationMin: 90, repeat: RepeatKind.weekly, weekdays: {6},
        subjectId: 7, kind: ActivityKind.tutor,
      ).toActivity(id: 9);
      expect(weeklyClassMinutes([tutor]).total, 0);
    });

    test('hoursText', () {
      expect(hoursText(120), '2');
      expect(hoursText(90), '1.5');
    });
  });

  test('พิมพ์ "กลุ่ม L.1" / "ห้อง 1-B4-08" → เก็บแค่ค่า (หน้าจอเติมคำนำหน้าเอง)', () {
    const typed = ClassInfo(type: ClassType.lab, section: 'กลุ่ม L.1', room: 'ห้อง: 1-B4-08');
    expect(typed.normalized, const ClassInfo(type: ClassType.lab, section: 'L.1', room: '1-B4-08'));
    expect(const ClassInfo(section: 'L.1').normalized.section, 'L.1');
    expect(const ClassInfo(section: 'กลุ่ม', room: '  ').normalized, ClassInfo.none);
  });

  group('เก็บประเภท/ห้อง/กลุ่ม', () {
    test('RAM: แก้เวลาทั้งชุดแล้วข้อมูลคาบไม่หาย · ตั้งประเภทให้คาบเก่าได้', () async {
      final repo = MemoryCalendarRepository();
      final id = await repo.addActivity(cls({4}, 8 * 60, 120, info: lab));
      expect((await repo.activity(id)).classInfo, lab);

      await repo.moveSeries(id, DateTime(2026, 11, 9), 9 * 60, 120);
      expect((await repo.activity(id)).classInfo, lab);

      final old = await repo.addActivity(cls({2}, 13 * 60, 240));
      expect((await repo.activity(old)).classInfo.type, isNull);
      await repo.updateActivity(old, (await repo.activity(old)).toDraft().withClassInfo(theory));
      expect((await repo.activity(old)).classInfo, theory);
    });

    test('SQLite: migration v11 รันซ้ำได้ · คาบเก่าเป็น null · บันทึกและอ่านกลับได้', () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await createStudySchema(db);
      await createSettingSchema(db);
      await createCalendarSchema(db);
      await createCalendarV5(db);
      await createCalendarV7(db);
      await createStudyPlanV8(db);
      await createTutorV9(db);
      await createTermV10(db);
      await createRound7V17(db); // v17: คอลัมน์รอบ 7

      await createClassInfoV11(db);
      await createClassInfoV11(db); // รันซ้ำก็ไม่พัง
      final cols = (await db.rawQuery('PRAGMA table_info(activity)')).map((c) => c['name']);
      expect(cols, containsAll(['class_type', 'room', 'section']));

      final repo = SqliteCalendarRepository(db);
      final old = await repo.addActivity(cls({2}, 13 * 60, 240)); // คาบแบบเก่า = ค่าว่าง
      expect((await repo.activity(old)).classInfo, ClassInfo.none);

      final id = await repo.addActivity(cls({3}, 8 * 60, 120, info: lab));
      expect((await repo.activity(id)).classInfo, lab);
      await db.close();
    });
  });
}
