import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/calendar_repository.dart' show CalendarScope;
import 'package:noir_manager/calendar/day_cards.dart';
import 'package:noir_manager/calendar/day_judge.dart';
import 'package:noir_manager/calendar/lookback.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/calendar/stickers.dart';
import 'package:noir_manager/theme/app_theme.dart';
import 'package:noir_manager/theme/noir_colors.dart';

NewActivity _important(String name, DateTime day, {int start = 19 * 60}) => NewActivity(
      name: name,
      categoryId: 4,
      importance: 3,
      timed: true,
      day: day,
      startMinute: start,
      durationMin: 120,
    );

void main() {
  group('ตัดสินวัน (M / M+)', () {
    final mon = DateTime(2026, 11, 16);
    final tue = DateTime(2026, 11, 17);

    test('ยังไม่ถึงเวลาตื่น = ยังไม่ตัดสิน (โต้รุ่งได้) · เลยเวลาตื่น = แปะ "พลาด" เป็น ⭐', () async {
      final repo = MemoryCalendarRepository();
      await repo.addActivity(_important('ตัดคลิป', mon));
      expect(await judgeDays(repo, now: DateTime(2026, 11, 17, 3), force: true), 0); // ตี 3 ยังทำต่อได้
      expect(openDay(DateTime(2026, 11, 17, 3), defaultLifeBase()), mon);
      expect(await judgeDays(repo, now: DateTime(2026, 11, 17, 7, 1), force: true), 1);
      final st = await repo.daySticker(mon, mon);
      expect(st.single.auto, 'missed');
      expect(st.single.highlight, isTrue);
      expect(st.single.sticker.name, 'เหนื่อยมาก'); // ค่าเริ่มต้นจนกว่าจะเลือกเอง
      expect(await judgeDays(repo, now: DateTime(2026, 11, 17, 9), force: true), 0); // ไม่แปะซ้ำ

      // ทำเสร็จทีหลัง → เปลี่ยนเป็น "เสร็จย้อนหลัง" + ป้ายช้า
      final o = (await repo.occurrencesOn(mon)).single;
      await repo.setDone(o.id, true);
      final text = await afterDone(repo, mon, now: DateTime(2026, 11, 17, 9, 30));
      expect(text, 'ทำย้อนหลัง · ช้า 2 ชม. 30 นาที');
      final late = (await repo.daySticker(mon, mon)).single;
      expect(late.auto, 'late');
      expect(late.sticker.name, 'ภูมิใจ');
      expect(late.note, text);
    });

    test('ต่อเวลาถึงเที่ยง · ปิดวันเอง = ตัดสินทันที · ปิดระบบ = ไม่แปะ · วันหยุด = ไม่แปะ', () async {
      final repo = MemoryCalendarRepository();
      await repo.addActivity(_important('ตัดคลิป', mon));
      await repo.setSetting(extendKey(mon), DateTime(2026, 11, 17, 12).toIso8601String());
      expect(await judgeDays(repo, now: DateTime(2026, 11, 17, 9), force: true), 0);

      await repo.addActivity(_important('ส่งงาน', tue));
      await repo.setSetting(closedKey(tue), 'on');
      expect(await judgeDays(repo, now: DateTime(2026, 11, 17, 11), force: true), 1); // ปิดวันอังคารเอง (จันทร์ยังต่อเวลาอยู่)

      final r2 = MemoryCalendarRepository();
      await r2.addActivity(_important('ตัดคลิป', mon));
      await r2.setSetting(autoStickerKey, 'off');
      expect(await judgeDays(r2, now: DateTime(2026, 11, 18), force: true), 0);

      final r3 = MemoryCalendarRepository();
      await r3.addActivity(_important('ตัดคลิป', mon));
      await r3.setHoliday(mon, 'หยุด');
      expect(await judgeDays(r3, now: DateTime(2026, 11, 18), force: true), 0);
    });

    test('งานยืดหยุ่นที่ "ว่างทั้งช่วง" ไม่นับเป็นพลาด', () async {
      final repo = MemoryCalendarRepository();
      await repo.addActivity(NewActivity(
        name: 'ทำงาน',
        categoryId: 4,
        importance: 3,
        timed: true,
        day: mon,
        startMinute: 8 * 60,
        durationMin: 9 * 60,
        repeat: RepeatKind.weekly,
        weekdays: const {1},
        flexible: true,
      ));
      final o = (await repo.occurrencesOn(mon)).single;
      await repo.setFree(o.id, o.startAt, o.endAt);
      expect(await judgeDays(repo, now: DateTime(2026, 11, 18), force: true), 0);
    });
  });

  test('สถิติย้อนหลัง: นอนน้อย → พลาดบ่อย · CSV', () {
    final days = <DateTime, List<Occurrence>>{};
    final checkins = <DateTime, Checkin>{};
    var id = 1;
    Occurrence occ(DateTime d, OccurrenceStatus st) => Occurrence(
          id: id++, activityId: id, title: 'งาน', categoryId: 4, importance: 3, repeats: false, day: d,
          startAt: DateTime(d.year, d.month, d.day, 19), endAt: DateTime(d.year, d.month, d.day, 21),
          status: st, reason: null, movedFromId: null);
    for (var i = 1; i <= 8; i++) {
      final d = DateTime(2026, 11, i);
      final short = i <= 4;
      days[d] = [occ(d, short && i != 1 ? OccurrenceStatus.planned : OccurrenceStatus.done)];
      checkins[d] = Checkin(
        day: d,
        sleptAt: DateTime(2026, 11, i, short ? 3 : 0),
        wokeAt: DateTime(2026, 11, i, 7),
        energy: short ? 2 : 4,
      );
    }
    final lb = analyzeLookback(days: days, checkins: checkins, stickers: const {}, today: DateTime(2026, 11, 10));
    expect(lb.total, 8);
    expect(lb.missed, 3);
    expect(lb.sleep[0], ('< 6 ชม.', 1, 4));
    expect(lb.sleep[2], ('≥ 7 ชม.', 4, 4));
    expect(lb.insights.first, startsWith('คืนที่นอน < 6 ชม.'));
    expect(lb.insights.any((t) => t.contains('พลังต่ำ')), isTrue);
    final csv = lookbackCsv(lb);
    expect(csv.split('\n').first, 'day,weekday,important,on_time,late,missed,sleep_hours,energy,miss_reason,moods');
    expect(csv.split('\n')[1], startsWith('2026-11-01,7,1,1,0,0,4.00,2'));
  });

  testWidgets('หน้าวันนี้: เลยเวลานอน + งานสำคัญค้าง → ถาม "ยังทำอยู่ไหม?" · เช็กอินเช้าบันทึกได้', (tester) async {
    final repo = MemoryCalendarRepository();
    final mon = DateTime(2026, 11, 16);
    await repo.addActivity(_important('ตัดคลิป', mon));
    Widget host(DateTime now) => MaterialApp(
          theme: AppTheme.of(themeChoices.first),
          home: Scaffold(
            body: CalendarScope(repository: repo, child: SingleChildScrollView(child: NightCards(now: now))),
          ),
        );
    await tester.pumpWidget(host(DateTime(2026, 11, 17, 0, 30))); // หลังเที่ยงคืน ยังเป็น "วันจันทร์"
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('night-card')), findsOneWidget);
    await tester.tap(find.text('ต่อถึงเที่ยงพรุ่งนี้'));
    await tester.pumpAndSettle();
    expect(await repo.getSetting(extendKey(mon)), DateTime(2026, 11, 17, 12).toIso8601String());
    expect(find.byKey(const Key('night-card')), findsNothing);

    await tester.tap(find.byKey(const Key('checkin-save')));
    await tester.pumpAndSettle();
    final ci = await repo.checkin(DateTime(2026, 11, 17));
    expect(ci?.energy, 3);
    expect(ci?.sleepHours, closeTo(7.5, 0.01)); // ค่าเริ่มต้นจาก Life Base 23:30 → 07:00
    expect(tester.takeException(), isNull);
  });

  test('ไฮไลต์ของวัน: ⭐ ที่เลือก · ไม่ได้เลือก = ชิ้นแรก', () {
    const s1 = Sticker(id: 1, packId: 1, name: 'a', emoji: '🔥');
    const s2 = Sticker(id: 2, packId: 1, name: 'b', emoji: '🥳');
    final d = DateTime(2026, 11, 13);
    expect(highlightOf([DaySticker(id: 1, day: d, sticker: s1), DaySticker(id: 2, day: d, sticker: s2)])!.id, 1);
    expect(highlightOf([DaySticker(id: 1, day: d, sticker: s1), DaySticker(id: 2, day: d, sticker: s2, highlight: true)])!.id, 2);
  });

  test('ช้าเกินวัน → บอกเป็นวัน (เดิม 170 ชม. 11 นาที)', () {
    expect(lateText(const Duration(hours: 170, minutes: 11)), '7 วัน 2 ชม.');
    expect(lateText(const Duration(days: 1)), '1 วัน');
    expect(lateText(const Duration(hours: 2, minutes: 30)), '2 ชม. 30 นาที');
    expect(lateText(const Duration(minutes: 45)), '45 นาที');
  });
}
