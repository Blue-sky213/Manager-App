import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/calendar/sqlite_calendar_repository.dart';
import 'package:noir_manager/data/app_database.dart';
import 'package:noir_manager/data/demo_year.dart' show demoMode;
import 'package:noir_manager/sync/cloud_sync.dart';
import 'package:noir_manager/sync/login_gate.dart';
import 'package:noir_manager/sync/merge.dart';
import 'package:noir_manager/sync/supabase_api.dart';
import 'package:noir_manager/theme/app_theme.dart';
import 'package:noir_manager/theme/noir_colors.dart';

void main() {
  sqfliteFfiInit();

  test('ออนไลน์ก่อน: ของที่ถึงบัญชีทีหลังชนะ · ช่องที่เครื่องนี้แก้แต่ยังไม่ส่ง = เก็บไว้ส่งตาม', () {
    const remote = SyncRow(table: 'a', id: '1', values: {'x': 1, 'y': 1}, stamps: {'x': 50, 'y': 50});
    expect(serverFirst(null, remote, lastSync: 100).values, {'x': 1, 'y': 1});
    const mine = SyncRow(table: 'a', id: '1', values: {'x': 9, 'y': 0}, stamps: {'x': 150, 'y': 10});
    final m = serverFirst(mine, remote, lastSync: 100);
    expect(m.values, {'x': 9, 'y': 1});
    const del = SyncRow(table: 'a', id: '1', values: {'x': 1}, stamps: {'x': 10}, deletedAt: 120);
    expect(serverFirst(del, remote, lastSync: 100).deleted, isTrue);
  });

  testWidgets('เปิดแอป: ยังไม่เข้าระบบ = หน้าเข้าระบบ · จำเครื่องติ๊กไว้ · ลองข้อมูลตัวอย่างได้ · เข้าแล้ว = ใช้แอป', (tester) async {
    late CloudSyncService s;
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('noir_gate_');
      final db = await databaseFactoryFfi.openDatabase('${dir.path}/n.db',
          options: OpenDatabaseOptions(version: appSchemaVersion, onCreate: (db, _) => createAllTables(db)));
      s = CloudSyncService(db, SqliteCalendarRepository(db));
      await s.start();
    });
    Widget app() => MaterialApp(
          theme: AppTheme.of(themeChoices.first),
          home: LoginGate(service: s, child: const Scaffold(body: Text('แอปหลัก'))),
        );
    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.byKey(const Key('login-title')), findsOneWidget);
    expect(find.text('แอปหลัก'), findsNothing);
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('cloud-remember'))).value, isTrue);

    // ลองดูโดยไม่เข้าระบบ → โหมดข้อมูลตัวอย่าง
    await tester.ensureVisible(find.byKey(const Key('login-demo')));
    await tester.tap(find.byKey(const Key('login-demo')));
    await tester.pump();
    expect(demoMode.value, isTrue);
    expect(find.text('แอปหลัก'), findsOneWidget);
    demoMode.value = false;
    await tester.pump();

    // เข้าระบบแล้ว → ใช้แอปได้เลย
    s.api.session = const CloudSession(accessToken: 'a', refreshToken: 'r', expiresAt: 4102444800, userId: 'u', email: 'a@b.c');
    s.status.value = s.status.value.copyWith(state: CloudState.idle, email: 'a@b.c');
    await tester.pump();
    expect(find.text('แอปหลัก'), findsOneWidget);
  });
}
