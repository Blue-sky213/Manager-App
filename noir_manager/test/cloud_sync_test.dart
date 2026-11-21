import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/sqlite_calendar_repository.dart';
import 'package:noir_manager/data/app_database.dart';
import 'package:noir_manager/sync/duplicate_plan.dart';
import 'package:noir_manager/sync/local_mirror.dart';
import 'package:noir_manager/sync/sync_remote.dart';

/// 1 เครื่อง = 1 ไฟล์ SQLite จริง (โครงตารางล่าสุด + ค่าตั้งต้นเหมือนติดตั้งใหม่)
class Dev {
  Dev._(this.db) : mirror = LocalMirror(db), cal = SqliteCalendarRepository(db);
  final Database db;
  final LocalMirror mirror;
  final SqliteCalendarRepository cal;
  int lastRev = 0;
  int lastSync = 0;

  static Future<Dev> open() async {
    final dir = await Directory.systemTemp.createTemp('noir_sync_');
    final db = await databaseFactoryFfi.openDatabase(
      '${dir.path}/noir.db',
      options: OpenDatabaseOptions(
        version: appSchemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await createAllTables(db);
          await seedStudyData(db);
        },
      ),
    );
    return Dev._(db);
  }

  Future<RoundResult> sync(MemorySyncRemote remote, int now) async {
    final (r, rev) = await mirror.round(remote, now: now, lastSync: lastSync, lastRev: lastRev);
    lastRev = rev;
    lastSync = now;
    return r;
  }

  /// แก้ตอนไม่มีเน็ต: สแกนเก็บเวลาที่แก้ไว้ (เหมือนแอปสแกนหลังแก้ 5 วิ)
  Future<void> scanAt(int now) async {
    await mirror.scan(now);
    await mirror.save();
  }

  Future<Map<String, Object?>> activity(String name) async =>
      (await db.query('activity', where: 'name = ?', whereArgs: [name])).single;
}

void main() {
  sqfliteFfiInit();
  final day = DateTime(2026, 11, 20);

  Future<(Dev, Dev, MemorySyncRemote)> twoDevices() async {
    final a = await Dev.open(), b = await Dev.open(), remote = MemorySyncRemote();
    await a.cal.addActivity(NewActivity(
      name: 'ไลฟ์ RE4',
      categoryId: null,
      importance: 3,
      timed: true,
      day: day,
      startMinute: 19 * 60,
      durationMin: 120,
      repeat: RepeatKind.daily,
      endDate: day.add(const Duration(days: 6)),
    ));
    final occ = await a.cal.occurrencesOn(day);
    await a.cal.setDone(occ.single.id, true);
    await a.cal.setSetting('tray_pins', '["อ่านหนังสือ"]');
    await a.cal.setSetting('phone_sync_dir', r'C:\iCloud\A');
    await a.sync(remote, 1000);
    await b.cal.setSetting('phone_sync_dir', r'C:\iCloud\B');
    final r = await b.sync(remote, 2000);
    expect(r.wiped, isTrue); // เครื่องใหม่ → ใช้ข้อมูลจากบัญชีทั้งหมด
    return (a, b, remote);
  }

  test('ทุกช่องที่อ้างถึงแถวอื่น (…_id) ต้องรู้ว่าอ้างตารางไหน · ทุกตารางมีคีย์หลัก', () async {
    final d = await Dev.open();
    final specs = await readSpecs(d.db);
    final missing = [
      for (final t in specs)
        for (final c in t.columns)
          if ((c.endsWith('_id') || c == 'moved_from') && !t.refs.containsKey(c)) '${t.name}.$c',
    ];
    expect(missing, isEmpty);
    expect([for (final t in specs) if (t.pk.contains('rowid')) t.name], isEmpty);
    expect(specs.indexWhere((t) => t.name == 'activity') < specs.indexWhere((t) => t.name == 'occurrence'), isTrue);
  });

  test('เครื่องใหม่เข้าบัญชี → ได้ข้อมูลครบ ไม่ซ้ำ · ค่าของเครื่อง (iCloud) ไม่ข้ามเครื่อง', () async {
    final (a, b, remote) = await twoDevices();
    expect(remote.length, greaterThan(10));
    final act = await b.activity('ไลฟ์ RE4');
    expect(act['start_minute'], 19 * 60);
    final occ = await b.cal.occurrencesOn(day);
    expect(occ.single.status, OccurrenceStatus.done);
    expect(await b.cal.getSetting('tray_pins'), '["อ่านหนังสือ"]');
    expect(await b.cal.getSetting('phone_sync_dir'), r'C:\iCloud\B');
    for (final t in ['category', 'subject', 'preset', 'life_base']) {
      final na = (await a.db.rawQuery('SELECT COUNT(*) AS n FROM $t')).single['n'];
      final nb = (await b.db.rawQuery('SELECT COUNT(*) AS n FROM $t')).single['n'];
      expect(nb, na, reason: t);
    }
    // วันถัดไป: ทั้งสองเครื่องสร้าง "ครั้ง" ของงานซ้ำเอง → รหัสเดียวกัน ไม่ซ้ำ
    final d2 = day.add(const Duration(days: 1));
    await a.cal.occurrencesOn(d2);
    await b.cal.occurrencesOn(d2);
    await a.sync(remote, 3000);
    await b.sync(remote, 3100);
    await a.sync(remote, 3200);
    expect((await a.cal.occurrencesOn(d2)).length, 1);
    expect((await b.cal.occurrencesOn(d2)).length, 1);
  });

  test('กรณีนัวร์: มือถือแก้ offline ก่อน · คอมแก้ทีหลัง · มือถือออนไลน์ทีหลัง → ได้ค่าคอม + เตือน', () async {
    final (pc, phone, remote) = await twoDevices();
    remote.offline = true;
    final phoneId = (await phone.activity('ไลฟ์ RE4'))['id'];
    await phone.db.update('activity', {'start_minute': 20 * 60}, where: 'id = ?', whereArgs: [phoneId]);
    await phone.scanAt(10000); // 10:12 offline
    final pcId = (await pc.activity('ไลฟ์ RE4'))['id'];
    await pc.db.update('activity', {'start_minute': 21 * 60}, where: 'id = ?', whereArgs: [pcId]);
    await pc.scanAt(11000); // 11:05
    remote.offline = false;
    final r1 = await pc.sync(remote, 12000);
    expect(r1.conflicts, isEmpty);
    final r2 = await phone.sync(remote, 13000); // มือถือกลับมาออนไลน์
    expect(r2.conflicts.single.field, 'start_minute');
    expect((await phone.activity('ไลฟ์ RE4'))['start_minute'], 21 * 60);
    await pc.sync(remote, 14000);
    expect((await pc.activity('ไลฟ์ RE4'))['start_minute'], 21 * 60);

    // กด "ใช้อีกค่า" บนมือถือ → ค่ามือถือชนะทั้งสองเครื่อง
    await phone.mirror.useOtherValue(r2.conflicts.single, 15000);
    expect((await phone.activity('ไลฟ์ RE4'))['start_minute'], 20 * 60);
    await phone.sync(remote, 15100);
    final r3 = await pc.sync(remote, 16000);
    expect(r3.conflicts, isEmpty);
    expect((await pc.activity('ไลฟ์ RE4'))['start_minute'], 20 * 60);
  });

  test('แก้คนละช่อง = ได้ทั้งคู่ ไม่เตือน · ค่าเหมือนกัน = ไม่เตือน · ลบแล้วหายทุกเครื่อง', () async {
    final (pc, phone, remote) = await twoDevices();
    final occPc = (await pc.cal.occurrencesOn(day)).single;
    final occPhone = (await phone.cal.occurrencesOn(day)).single;
    await pc.db.update('occurrence', {'note': 'เตรียม OBS'}, where: 'id = ?', whereArgs: [occPc.id]);
    await phone.db.update('occurrence', {'reason': 'ไลฟ์ยาว'}, where: 'id = ?', whereArgs: [occPhone.id]);
    // ทั้งคู่แก้ชื่อเป็นค่าเดียวกัน
    await pc.db.update('activity', {'name': 'ไลฟ์ RE4 Day 2'}, where: 'name = ?', whereArgs: ['ไลฟ์ RE4']);
    await phone.db.update('activity', {'name': 'ไลฟ์ RE4 Day 2'}, where: 'name = ?', whereArgs: ['ไลฟ์ RE4']);
    expect((await pc.sync(remote, 5000)).conflicts, isEmpty);
    expect((await phone.sync(remote, 5100)).conflicts, isEmpty);
    await pc.sync(remote, 5200);
    for (final d in [pc, phone]) {
      final o = (await d.db.query('occurrence', where: 'day = ?', whereArgs: ['2026-11-20'])).single;
      expect(o['note'], 'เตรียม OBS');
      expect(o['reason'], 'ไลฟ์ยาว');
    }

    await pc.cal.deleteActivity((await pc.activity('ไลฟ์ RE4 Day 2'))['id'] as int);
    await pc.sync(remote, 6000);
    await phone.sync(remote, 6100);
    expect(await phone.db.query('activity', where: 'name = ?', whereArgs: ['ไลฟ์ RE4 Day 2']), isEmpty);
    expect(await phone.db.query('occurrence'), isEmpty);
  });

  test('ย้ายเครื่อง (รอบ 20): เครื่องใหม่ที่มีข้อมูลแล้ว → ค่าตั้งต้น (เวลานอน 12:00) ไม่ทับค่าจริงในบัญชี · ไม่เตือน', () async {
    final a = await Dev.open(), b = await Dev.open(), remote = MemorySyncRemote();
    await a.db.update('life_base', {'bed_minute': 60, 'wake_minute': 450});
    await a.cal.addActivity(NewActivity(name: 'งาน PC เก่า', categoryId: null, importance: 2, timed: false, day: day));
    await a.sync(remote, 1000);
    // เครื่องใหม่ใช้ไปก่อนเข้าบัญชี (ไม่ใช่เครื่องว่าง)
    await b.cal.addActivity(NewActivity(name: 'งานเครื่องใหม่', categoryId: null, importance: 2, timed: false, day: day));
    final r = await b.sync(remote, 5000);
    expect(r.wiped, isFalse);
    expect(r.conflicts, isEmpty);
    final lb = await b.db.query('life_base');
    expect(lb.every((x) => x['bed_minute'] == 60 && x['wake_minute'] == 450), isTrue);
    expect((await b.db.query('activity')).map((x) => x['name']), containsAll(['งาน PC เก่า', 'งานเครื่องใหม่']));
    await a.sync(remote, 6000);
    expect((await a.db.query('life_base')).every((x) => x['bed_minute'] == 60), isTrue);
    expect((await a.db.query('activity')).map((x) => x['name']), contains('งานเครื่องใหม่'));
  });

  NewActivity plan(String name, DateTime start) => NewActivity(
        name: name,
        categoryId: null,
        importance: 2,
        timed: true,
        day: start,
        startMinute: 8 * 60,
        durationMin: 240,
        repeat: RepeatKind.daily,
        endDate: start.add(const Duration(days: 155)),
      );

  test('ย้ายเครื่อง (รอบ 20): แผนชุดเดียวกันสร้างคนละวันบน 2 เครื่อง → เข้าบัญชีแล้วเหลือชุดเดียว', () async {
    final a = await Dev.open(), b = await Dev.open(), remote = MemorySyncRemote();
    await a.cal.addActivity(plan('งาน · mecsteam', DateTime(2026, 11, 17)));
    await a.sync(remote, 1000);
    await b.cal.addActivity(plan('งาน · mecsteam', DateTime(2026, 11, 21))); // กดใส่แผนอีกรอบบนเครื่องใหม่
    await b.cal.addActivity(NewActivity(name: 'งานเครื่องใหม่', categoryId: null, importance: 2, timed: false, day: day));
    await b.sync(remote, 5000);
    final acts = await b.db.query('activity', where: 'name = ?', whereArgs: ['งาน · mecsteam']);
    expect(acts.length, 1);
    expect(acts.single['start_date'], '2026-11-17'); // ใช้ของบัญชี (เครื่องเก่า)
    expect((await b.cal.occurrencesOn(DateTime(2026, 11, 21))).where((o) => o.title == 'งาน · mecsteam').length, 1);
  });

  test('หางานซ้ำที่เกิดไปแล้ว: เก็บตัวที่มีประวัติ · ลบได้เฉพาะตัวที่ยังไม่เคยใช้', () async {
    final d = await Dev.open();
    final old = await d.cal.addActivity(plan('อ่านหนังสือ', DateTime(2026, 11, 17)));
    final dup = await d.cal.addActivity(plan('อ่านหนังสือ', DateTime(2026, 11, 21)));
    await d.cal.addActivity(plan('ไลฟ์', DateTime(2026, 11, 17)));
    final occ = (await d.cal.occurrencesOn(DateTime(2026, 11, 18))).firstWhere((o) => o.activityId == old);
    await d.cal.setDone(occ.id, true);
    final found = await findDuplicateActivities(d.db);
    expect(found.single.name, 'อ่านหนังสือ');
    expect(found.single.keepId, old);
    expect(found.single.removeIds, [dup]);
    await d.cal.deleteActivity(dup);
    expect(await findDuplicateActivities(d.db), isEmpty);
  });
}
