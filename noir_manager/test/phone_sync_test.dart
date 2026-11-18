// รอบ 14: PC ↔ iPhone ผ่านโฟลเดอร์ iCloud (snapshot.json + inbox/)
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/noir_plan.dart';
import 'package:noir_manager/sync/phone_sync.dart';
import 'package:noir_manager/sync/phone_sync_settings.dart';
import 'package:noir_manager/sync/scriptable_script.dart';

final now = DateTime(2026, 11, 18, 15, 10);
final today = dayOnly(now);

Future<MemoryCalendarRepository> planned() async {
  final cal = MemoryCalendarRepository();
  await applyNoirPlan(cal, today);
  return cal;
}

Future<Occurrence> occNamed(MemoryCalendarRepository cal, DateTime day, String prefix) async =>
    (await cal.occurrencesOn(day)).firstWhere((o) => o.title.startsWith(prefix));

void main() {
  test('โฟลเดอร์ Scriptable ของ iCloud for Windows', () {
    expect(defaultPhoneSyncDir(env: {'USERPROFILE': r'C:\Users\Napat'}, os: 'windows'),
        r'C:\Users\Napat\iCloudDrive\iCloud~dk~simonbs~Scriptable\NoirManager');
    expect(defaultPhoneSyncDir(env: const {}, os: 'windows'), isNull);
    expect(defaultPhoneSyncDir(env: {'USERPROFILE': 'x'}, os: 'android'), isNull);
    expect([parseHm('07:05'), parseHm('7:05'), parseHm('24:00'), parseHm('ab'), parseHm(null)], [425, 425, null, null, null]);
  });

  test('snapshot: วันนี้ + 7 วัน · งานผูกสกิล · บทตอนนี้ของสกิล · หมวด', () async {
    final cal = await planned();
    final snap = jsonDecode(jsonEncode(await buildSnapshot(cal, now))) as Map; // ต้องแปลงเป็น JSON ได้
    expect(snap['v'], snapshotVersion);
    expect(snap['today'], '2026-11-18');
    final days = snap['days'] as List;
    expect(days.length, snapshotDays);
    expect(days.last['date'], '2026-11-25');
    final items = (days.first['items'] as List).cast<Map>();
    final dv = items.firstWhere((i) => (i['title'] as String).startsWith('ฝึก · DaVinci'));
    expect((dv['start'], dv['end'], dv['done']), ('20:30', '21:30', false));
    expect(dv['skill'], isNotNull);
    final skills = (snap['skills'] as List).cast<Map>();
    final dvSkill = skills.firstWhere((s) => s['id'] == dv['skill']);
    expect(dvSkill['current']['name'], startsWith('บท 0'));
    expect((dvSkill['current']['topics'] as List).first['url'], startsWith('https://www.youtube.com/'));
    expect((snap['categories'] as List), isNotEmpty);
  });

  group('คำสั่งจากมือถือ', () {
    test('ติ๊กทำแล้ว / เลิกติ๊ก · id หายไป → หาจากงานเดียวกันวันเดียวกัน · ไม่เจอ = failed', () async {
      final cal = await planned();
      final o = await occNamed(cal, today, 'ฝึก · Canva');
      var r = await applyPhoneCommand(cal, {'type': 'done', 'occ': o.id, 'act': o.activityId, 'date': '2026-11-18'}, now);
      expect(r.outcome, CmdOutcome.applied);
      expect((await occNamed(cal, today, 'ฝึก · Canva')).status, OccurrenceStatus.done);
      r = await applyPhoneCommand(cal, {'type': 'done', 'occ': -1, 'act': o.activityId, 'date': '2026-11-18', 'done': false}, now);
      expect(r.outcome, CmdOutcome.applied);
      expect((await occNamed(cal, today, 'ฝึก · Canva')).status, OccurrenceStatus.planned);
      r = await applyPhoneCommand(cal, {'type': 'done', 'occ': -1, 'act': -1, 'date': '2026-11-18'}, now);
      expect(r.outcome, CmdOutcome.failed);
    });

    test('เพิ่มงาน · เลื่อนงาน (เวลาเดิมถ้าไม่บอก)', () async {
      final cal = await planned();
      final tomorrow = today.add(const Duration(days: 1));
      var r = await applyPhoneCommand(
          cal, {'type': 'add', 'name': 'ตัดปกไลฟ์ CS2', 'date': '2026-11-19', 'start': '19:00', 'minutes': 30, 'imp': 3}, now);
      expect(r.outcome, CmdOutcome.applied);
      final added = await occNamed(cal, tomorrow, 'ตัดปกไลฟ์');
      expect((added.startAt, added.endAt, added.importance),
          (tomorrow.add(const Duration(hours: 19)), tomorrow.add(const Duration(hours: 19, minutes: 30)), 3));
      r = await applyPhoneCommand(cal, {'type': 'add', 'name': '  ', 'date': '2026-11-19'}, now);
      expect(r.outcome, CmdOutcome.failed);

      final o = await occNamed(cal, today, 'อ่านหนังสือ');
      r = await applyPhoneCommand(cal, {'type': 'move', 'occ': o.id, 'act': o.activityId, 'date': '2026-11-18', 'toDate': '2026-11-21'}, now);
      expect(r.outcome, CmdOutcome.applied);
      final moved = (await cal.occurrencesOn(DateTime(2026, 11, 21))).where((x) => x.title == o.title && x.movedFromId == o.id).single;
      expect(moved.startAt!.hour * 60 + moved.startAt!.minute, o.startAt!.hour * 60 + o.startAt!.minute);
    });

    test('เช็กอิน: นอนหลัง 18:00 = คืนก่อน · ค่าที่ไม่ส่งมาคงเดิม · สติกเกอร์ติดวัน', () async {
      final cal = await planned();
      final sticker = (await cal.stickerPacks()).expand((p) => p.stickers).firstWhere((s) => s.emoji != null);
      await applyPhoneCommand(cal, {'type': 'checkin', 'date': '2026-11-18', 'energy': 4, 'sleptAt': '23:30', 'wokeAt': '07:20', 'sticker': sticker.id}, now);
      var c = (await cal.checkin(today))!;
      expect((c.energy, c.sleptAt, c.wokeAt), (4, DateTime(2026, 11, 17, 23, 30), DateTime(2026, 11, 18, 7, 20)));
      expect((await cal.daySticker(today, today)).map((d) => d.stickerId), contains(sticker.id));
      await applyPhoneCommand(cal, {'type': 'checkin', 'date': '2026-11-18', 'sleptAt': '00:40'}, now);
      c = (await cal.checkin(today))!;
      expect((c.energy, c.sleptAt, c.wokeAt), (4, DateTime(2026, 11, 18, 0, 40), DateTime(2026, 11, 18, 7, 20)));
    });

    test('บันทึกรอบ + คะแนนหัวข้อ · ให้คะแนนอย่างเดียว · คำสั่งไม่รู้จัก = failed', () async {
      final cal = await planned();
      final r0 = cal.skillRepo;
      final dv = (await r0.skills()).firstWhere((s) => s.name.startsWith('DaVinci'));
      final topic = (await r0.topics()).first;
      var r = await applyPhoneCommand(
          cal, {'type': 'skillLog', 'skill': dv.id, 'date': '2026-11-18', 'minutes': 60, 'topic': topic.id, 'score': 90}, now);
      expect(r.outcome, CmdOutcome.applied);
      expect((await r0.logs(dv.id)).single.minutes, 60);
      expect((await r0.topics()).first.score, 90);
      r = await applyPhoneCommand(cal, {'type': 'topicScore', 'topic': topic.id, 'score': 140}, now);
      expect((await r0.topics()).first.score, 100);
      r = await applyPhoneCommand(cal, {'type': 'fly'}, now);
      expect(r.outcome, CmdOutcome.failed);
    });
  });

  test('1 รอบ: ทำคำสั่งตามลำดับ · id ซ้ำไม่ทำซ้ำ · ไฟล์ยังโหลดไม่ครบรอรอบหน้า · เขียนสคริปต์ + snapshot เฉพาะตอนเปลี่ยน', () async {
    final tmp = await Directory.systemTemp.createTemp('noir_sync');
    addTearDown(() => tmp.delete(recursive: true));
    final cal = await planned();
    final sync = PhoneSync(cal, Directory('${tmp.path}/NoirManager'));
    var r = await sync.runOnce(now);
    expect(r.wrote, isTrue);
    expect(sync.scriptFile.readAsStringSync(), scriptableSource);
    final snap = jsonDecode(sync.snapshotFile.readAsStringSync()) as Map;
    expect(snap['generatedAt'], now.toIso8601String());
    expect(sync.snapshotFile.parent.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);

    // ไม่มีอะไรเปลี่ยน → ไม่เขียนซ้ำ (ไม่ให้ iCloud อัปโหลดทุก 30 วินาที)
    r = await sync.runOnce(now);
    expect(r.wrote, isFalse);

    final o = await occNamed(cal, today, 'ฝึก · Canva');
    final cmd = {'id': 'a1', 'type': 'done', 'occ': o.id, 'act': o.activityId, 'date': '2026-11-18'};
    File('${sync.inboxDir.path}/1-done.json').writeAsStringSync(jsonEncode(cmd));
    File('${sync.inboxDir.path}/2-done.json').writeAsStringSync(jsonEncode({...cmd, 'done': false, 'id': 'a1'})); // id ซ้ำ
    File('${sync.inboxDir.path}/3-add.json').writeAsStringSync('{"id":"a2","type":"add","na'); // ยังโหลดไม่ครบ
    r = await sync.runOnce(now);
    expect(r.applied, hasLength(1));
    expect((await occNamed(cal, today, 'ฝึก · Canva')).status, OccurrenceStatus.done);
    expect(r.wrote, isTrue);
    expect(sync.inboxDir.listSync().map((f) => f.path.split(RegExp(r'[\\/]')).last), ['3-add.json']);

    // iCloud ส่งไฟล์ id เดิมมาอีกรอบ (เช่น sync ซ้ำ) → ข้าม
    File('${sync.inboxDir.path}/4-done.json').writeAsStringSync(jsonEncode({...cmd, 'done': false}));
    File('${sync.inboxDir.path}/3-add.json')
        .writeAsStringSync(jsonEncode({'id': 'a2', 'type': 'add', 'name': 'งานจากมือถือ', 'date': '2026-11-18'}));
    r = await sync.runOnce(now);
    expect(r.applied, ['เพิ่มงาน: งานจากมือถือ']);
    expect((await occNamed(cal, today, 'ฝึก · Canva')).status, OccurrenceStatus.done);
    expect(sync.inboxDir.listSync(), isEmpty);
  });

  test('โค้ด Scriptable ในแอป = tool/NoirManager.js (แก้ .js แล้วรัน tool/gen_scriptable.py)', () {
    expect(scriptableSource, File('tool/NoirManager.js').readAsStringSync());
  });

  testWidgets('ตั้งค่า: โหมดข้อมูลตัวอย่าง / มือถือ = ปิดใช้ · มีคู่มือ 5 ขั้นเมื่อเปิดใช้ได้', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PhoneSyncSection())));
    expect(find.textContaining('ใช้ได้กับข้อมูลจริงบน PC เท่านั้น'), findsOneWidget);
    final cal = MemoryCalendarRepository();
    final service = PhoneSyncService(cal);
    service.status.value = const PhoneSyncStatus(dir: '/nope/NoirManager');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PhoneSyncSection(service: service)))));
    expect(find.text('ยังไม่พบโฟลเดอร์ Scriptable'), findsOneWidget);
    await tester.tap(find.byKey(const Key('phone-sync-guide')));
    await tester.pumpAndSettle();
    expect(find.textContaining('iCloud for Windows'), findsOneWidget);
    // ยังไม่พบโฟลเดอร์ → เปิดไม่ได้ (ไม่สร้างโฟลเดอร์มั่ว ๆ)
    await tester.tap(find.byKey(const Key('phone-sync-on')));
    await tester.pumpAndSettle();
    expect(service.status.value.on, isFalse);
    expect(await cal.getSetting(phoneSyncOnKey), isNull);
    expect(phoneSetupSteps, hasLength(5));
  });
}
