// รอบ 10C: ล้างแล้วเริ่มใหม่ + แผนของนัวร์
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/data/noir_plan.dart';
import 'package:noir_manager/skills/skill_lessons.dart';
import 'package:noir_manager/skills/skill_models.dart';
import 'package:noir_manager/work/project_models.dart';

final today = DateTime(2026, 11, 17);

void main() {
  test('ใส่แผน: งานซ้ำครบ · ไม่ชนกันเอง · ผูกสกิล · เว็บ mecsteam · กดซ้ำไม่ซ้อน', () async {
    final cal = MemoryCalendarRepository();
    final r = await applyNoirPlan(cal, today);
    expect(r.activities, noirPlanNames.length);
    expect(r.skills, 3);
    expect(r.tasks, 7);

    // ไม่ชนกันเองทุกวันใน 2 สัปดาห์
    for (var i = 0; i < 14; i++) {
      final d = today.add(Duration(days: i));
      final occ = [for (final o in await cal.occurrencesOn(d)) if (o.timed) o]..sort((a, b) => a.startAt!.compareTo(b.startAt!));
      for (var k = 1; k < occ.length; k++) {
        expect(occ[k].startAt!.isBefore(occ[k - 1].endAt!), isFalse, reason: '${dayKey(d)} ${occ[k - 1].title} ชน ${occ[k].title}');
      }
      // ไลฟ์ จ/พ/ศ/ส/อา
      expect(occ.any((o) => o.title.startsWith('ไลฟ์')), {1, 3, 5, 6, 7}.contains(d.weekday), reason: dayKey(d));
    }
    // 6 เดือน → หลังจากนั้นไม่มี
    expect(await cal.occurrencesOn(DateTime(2027, 6, 1)), isEmpty);

    final skills = await cal.skillRepo.skills();
    expect(skills.map((s) => s.name).toSet(), {'IELTS', 'DaVinci Resolve', 'Canva', englishB1Skill});
    final dv = skills.firstWhere((s) => s.name.startsWith('DaVinci'));
    expect((await cal.skillRepo.activitiesOf(dv.id)).length, 3);
    expect((await cal.skillRepo.branches()).map((b) => b.name), containsAll(['ภาษา', 'ตัดต่อ', 'ออกแบบ', 'อ่าน']));

    final pj = (await cal.workRepo.projects()).single;
    expect((pj.name, pj.type, pj.status), ('เว็บ mecsteam.com', 'web', ProjectStatus.doing));
    expect((await cal.workRepo.tasks(pj.id)).where((t) => !t.done).length, 5);

    final again = await applyNoirPlan(cal, today);
    expect((again.activities, again.skills, again.tasks), (0, 0, 0));
  });

  test('ใส่แผน: ใช้สกิล DaVinci / โปรเจกต์ mecsteam ที่มีอยู่แล้ว (ไม่สร้างซ้ำ)', () async {
    final cal = MemoryCalendarRepository();
    await cal.skillRepo.saveSkill(Skill(name: 'DaVinci', startedAt: DateTime(2026, 11, 1)));
    await cal.workRepo.saveProject(const Project(name: 'Website: mecsteam.com', type: 'web', price: 5000));
    final r = await applyNoirPlan(cal, today);
    expect(r.skills, 2);
    expect((await cal.skillRepo.skills()).where((s) => s.name.toLowerCase().contains('davinci')).length, 1);
    expect((await cal.workRepo.projects()).length, 1);
  });

  test('ล้างแล้วเริ่มใหม่: กิจกรรม + วิชา + เทอม + วันหยุด หาย · สติกเกอร์ / เช็กอิน / เงิน อยู่ครบ', () async {
    final cal = MemoryCalendarRepository();
    final study = MemoryStudyRepository.seeded();
    await applyNoirPlan(cal, today);
    await cal.saveTerm(1, 1, DateTime(2026, 11, 1), DateTime(2027, 2, 28));
    await cal.setHoliday(DateTime(2026, 12, 5), 'วันพ่อ');
    await cal.saveCheckin(Checkin(day: today, energy: 4));
    expect(await study.subjects(), isNotEmpty);

    final r = await resetForFreshStart(cal, study);
    expect(r.activities, noirPlanNames.length);
    expect((r.terms, r.holidays), (1, 1));
    expect(await cal.activityIds(), isEmpty);
    expect(await study.subjects(), isEmpty);
    expect(await cal.terms(), isEmpty);
    expect(await cal.holidays(), isEmpty);
    expect(await cal.occurrencesOn(today), isEmpty);
    expect((await cal.checkin(today))?.energy, 4);
    expect(await cal.skillRepo.skills(), hasLength(4));
    expect(await cal.workRepo.projects(), hasLength(1));
  });

  testWidgets('ตั้งค่า › ข้อมูล › ล้าง (ต้องพิมพ์ "ลบทั้งหมด") · ไม่มีปุ่มใส่แผนแล้ว', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cal = MemoryCalendarRepository();
    final study = MemoryStudyRepository.seeded();
    await cal.addActivity(NewActivity(name: 'งานเก่า', categoryId: (await cal.categories()).first.id, importance: 2, timed: false, day: today));
    await tester.pumpWidget(NoirManagerApp(studyRepository: study, calendarRepository: cal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตั้งค่า').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('set-cat-data')));
    await tester.pumpAndSettle();
    // รอบ 21: ปุ่มใส่แผน / สารบัญ เอาออกแล้ว (ใช้นำเข้าไฟล์แทน)
    expect(find.byKey(const Key('fresh-plan')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('fresh-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fresh-reset')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('fresh-confirm')), 'ลบ');
    await tester.tap(find.widgetWithText(FilledButton, 'สำรอง + ลบ'));
    await tester.pumpAndSettle();
    expect(find.text('พิมพ์ "ลบทั้งหมด" ให้ตรงก่อน'), findsOneWidget);
    expect(await cal.activityIds(), hasLength(1));
    await tester.enterText(find.byKey(const Key('fresh-confirm')), 'ลบทั้งหมด');
    await tester.tap(find.widgetWithText(FilledButton, 'สำรอง + ลบ'));
    await tester.pumpAndSettle();
    expect(await cal.activityIds(), isEmpty);
    expect(await study.subjects(), isEmpty);

    expect(tester.takeException(), isNull);
  });
}
