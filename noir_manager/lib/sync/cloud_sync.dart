/// บัญชี + ซิงก์อัตโนมัติ (รอบ 16)
/// - ข้อมูลแก้ → 5 วิ สแกน + ซิงก์ · ทุก 60 วิ ซิงก์อีกรอบ (ดึงของเครื่องอื่น)
/// - ไม่มีเน็ต = ใช้ต่อได้ · สแกนเก็บเวลาที่แก้ไว้ แล้วส่งตอนออนไลน์
/// - ซิงก์ครั้งแรก: สำรอง .db ก่อนเสมอ
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../calendar/calendar_repository.dart';
import '../calendar/sticker_images.dart' show refreshStickerImages;
import '../data/backup.dart';
import 'google_login.dart';
import 'local_mirror.dart';
import 'sticker_files.dart';
import 'merge.dart';
import 'realtime.dart';
import 'supabase_api.dart';
import 'sync_remote.dart';

const cloudSessionKey = 'cloud_session';
const cloudLastRevKey = 'cloud_last_rev';
const cloudLastSyncKey = 'cloud_last_sync';
const cloudDeviceKey = 'cloud_device';

/// 'off' = ไม่จำเครื่องนี้ (เปิดแอปครั้งหน้าต้องเข้าระบบใหม่)
const cloudRememberKey = 'cloud_remember';

enum CloudState { signedOut, idle, syncing, ok, offline, error }

@immutable
class CloudStatus {
  const CloudStatus({
    this.state = CloudState.signedOut,
    this.email,
    this.lastSync,
    this.pending = 0,
    this.message,
    this.conflicts = const [],
  });

  final CloudState state;
  final String? email;
  final DateTime? lastSync;

  /// แก้แล้วยังไม่ได้ส่ง
  final int pending;
  final String? message;

  /// ค่าที่ต่างกันรอบล่าสุด (ใช้ค่าล่าสุดไปแล้ว · กดสลับได้)
  final List<SyncConflict> conflicts;

  CloudStatus copyWith({
    CloudState? state,
    String? email,
    DateTime? lastSync,
    int? pending,
    String? message,
    bool clearMessage = false,
    List<SyncConflict>? conflicts,
  }) =>
      CloudStatus(
        state: state ?? this.state,
        email: email ?? this.email,
        lastSync: lastSync ?? this.lastSync,
        pending: pending ?? this.pending,
        message: clearMessage ? null : (message ?? this.message),
        conflicts: conflicts ?? this.conflicts,
      );
}

class CloudSyncService {
  CloudSyncService(this.db, this.cal, {this.backup, this.devicePrefix = 'PC', SupabaseApi? api, SyncRemote Function(SupabaseApi api, String device)? remote})
      : api = api ?? SupabaseApi(),
        _remoteOf = remote ?? ((a, d) => SupabaseRemote(a, device: d));

  /// ตัวเดียวทั้งแอป (null = ข้อมูลตัวอย่าง / เทส / เว็บ)
  static CloudSyncService? instance;

  final Database db;
  final CalendarRepository cal;
  final BackupService? backup;

  /// ชื่อเครื่องขึ้นต้น (PC / Web)
  final String devicePrefix;
  final SupabaseApi api;
  final SyncRemote Function(SupabaseApi api, String device) _remoteOf;

  late final LocalMirror mirror = LocalMirror(db);
  late final StickerFileSync _files =
      StickerFileSync(api, readSetting: cal.getSetting, writeSetting: cal.setSetting);
  final status = ValueNotifier(const CloudStatus());

  /// โหลดสถานะเข้าระบบเสร็จแล้ว (ก่อนหน้านี้ยังไม่รู้ว่าต้องโชว์หน้าเข้าระบบไหม)
  final ready = ValueNotifier(false);

  /// จำเครื่องนี้ (ค่าเริ่ม = จำ)
  final remember = ValueNotifier(true);

  RealtimeListener? _rt;
  bool _selfRefresh = false;
  int _ticks = 0;

  /// มีค่าต่างกันใหม่ → หน้าหลักโชว์เม็ดเตือน
  final conflictNotice = ValueNotifier<String?>(null);

  Timer? _timer;
  Timer? _debounce;
  bool _running = false;
  bool _again = false;
  String _device = '';

  int _now() => DateTime.now().millisecondsSinceEpoch;

  /// [authFragment] = เว็บเพิ่งกลับมาจาก Google (token หลัง #) · null = ปกติ
  Future<void> start({String? authFragment}) async {
    _device = await cal.getSetting(cloudDeviceKey) ?? '';
    if (_device.isEmpty) {
      _device = '$devicePrefix-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
      await cal.setSetting(cloudDeviceKey, _device);
    }
    api.onSession = (s) {
      cal.setSetting(cloudSessionKey, s == null ? '' : jsonEncode(s.toJson()));
      _rt?.updateToken();
    };
    remember.value = await cal.getSetting(cloudRememberKey) != 'off';
    // ไม่จำเครื่อง = เปิดแอปใหม่ต้องเข้าระบบใหม่ (ข้อมูลในเครื่องยังอยู่)
    final raw = remember.value ? await cal.getSetting(cloudSessionKey) : null;
    if (raw != null && raw.isNotEmpty) {
      try {
        api.session = CloudSession.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
      } catch (_) {
        api.session = null;
      }
    }
    String? error;
    if (authFragment != null) {
      try {
        api.adoptFragment(authFragment);
      } on CloudError catch (e) {
        error = e.message;
      }
    }
    final last = int.tryParse(await cal.getSetting(cloudLastSyncKey) ?? '');
    status.value = CloudStatus(
      state: api.session == null ? CloudState.signedOut : CloudState.idle,
      email: api.session?.email,
      lastSync: last == null || last == 0 ? null : DateTime.fromMillisecondsSinceEpoch(last),
      message: error,
    );
    ready.value = true;
    if (api.session != null) _begin();
  }

  Future<void> setRemember(bool on) async {
    remember.value = on;
    await cal.setSetting(cloudRememberKey, on ? 'on' : 'off');
  }

  void _begin() {
    cal.addListener(_onChange);
    cal.workRepo.addListener(_onChange);
    cal.skillRepo.addListener(_onChange);
    // รอบ 21: สัญญาณสด (เครื่องอื่นบันทึก → ดึงทันที) · ดึงสำรองทุก 30 วิ (ต่อสัญญาณสดอยู่ = ทุก 2 นาที)
    _rt?.stop();
    _rt = RealtimeListener(api, device: _device, onChange: () {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), syncNow);
    })
      ..start();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      _ticks++;
      if (!(_rt?.connected ?? false) || _ticks % 4 == 0) syncNow();
    });
    syncNow();
  }

  void _stop() {
    _rt?.stop();
    _rt = null;
    _timer?.cancel();
    _debounce?.cancel();
    cal.removeListener(_onChange);
    cal.workRepo.removeListener(_onChange);
    cal.skillRepo.removeListener(_onChange);
  }

  void _onChange() {
    if (_selfRefresh) return; // หน้าจอโหลดใหม่เพราะซิงก์เอง
    if (_running) {
      _again = true; // แก้ระหว่างกำลังซิงก์ → ส่งต่ออีกรอบ
      return;
    }
    // รอบ 21: บันทึกขึ้นบัญชีใน ~1 วิหลังแก้
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), syncNow);
  }

  /// สั่งหน้าจอโหลดใหม่ (ไม่นับเป็นการแก้ของผู้ใช้)
  void _refreshUi({bool stickers = false}) {
    _selfRefresh = true;
    try {
      if (stickers) refreshStickerImages();
      cal.refresh();
      cal.workRepo.refresh();
      cal.skillRepo.refresh();
    } finally {
      _selfRefresh = false;
    }
  }

  /// Google (รอบ 19) · คอม: เปิดเบราว์เซอร์แล้วรอ · เว็บ: เปลี่ยนหน้าไป Google (กลับมาแล้ว [start] รับต่อ)
  /// false = ยังไม่เสร็จ (เว็บกำลังไป Google / หมดเวลา)
  Future<bool> signInWithGoogle(Future<void> Function(String url) open) async {
    final frag = await googleSignInFlow(api.googleAuthorizeUrl, open);
    if (frag == null) return false;
    api.adoptFragment(frag);
    await _signedIn();
    return true;
  }

  Future<void> signIn(String email, String password) async {
    await api.signIn(email, password);
    await _signedIn();
  }

  /// สมัคร · false = ต้องยืนยันอีเมลก่อน
  Future<bool> signUp(String email, String password) async {
    final s = await api.signUp(email, password);
    if (s == null) return false;
    await _signedIn();
    return true;
  }

  Future<void> _signedIn() async {
    status.value = status.value.copyWith(state: CloudState.idle, email: api.session?.email, clearMessage: true);
    _begin();
  }

  /// ออกจากระบบ: ข้อมูลในเครื่องอยู่ครบ · เข้าบัญชีอื่นทีหลัง = เริ่มจับคู่ใหม่
  Future<void> signOut() async {
    _stop();
    await api.signOut();
    await cal.setSetting(cloudLastRevKey, '0');
    await cal.setSetting(cloudLastSyncKey, '0');
    await db.delete('sync_map');
    await db.delete('sync_shadow');
    await mirror.load();
    status.value = const CloudStatus();
  }

  Future<void> syncNow() async {
    if (api.session == null) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    status.value = status.value.copyWith(state: CloudState.syncing);
    try {
      final lastRev = int.tryParse(await cal.getSetting(cloudLastRevKey) ?? '') ?? 0;
      final lastSync = int.tryParse(await cal.getSetting(cloudLastSyncKey) ?? '') ?? 0;
      if (lastRev == 0) await backup?.backupNow(label: 'before_sync');
      final now = _now();
      final (r, maxRev) = await mirror.round(_remoteOf(api, _device), now: now, lastSync: lastSync, lastRev: lastRev);
      await cal.setSetting(cloudLastRevKey, '$maxRev');
      await cal.setSetting(cloudLastSyncKey, '$now');
      if (r.applied > 0 || r.wiped) _refreshUi();
      // รอบ 20: รูปสติกเกอร์ (ส่งที่ยังไม่ส่ง · ดึงที่เครื่องนี้ไม่มี) · พลาด = ไม่ล้มทั้งรอบ
      String? fileMsg;
      try {
        final paths = [
          for (final row in await db.rawQuery('SELECT image_path FROM sticker WHERE image_path IS NOT NULL'))
            row['image_path'] as String,
        ];
        final got = await _files.run(paths);
        if (got > 0) _refreshUi(stickers: true);
      } on CloudError catch (e) {
        fileMsg = e.message;
      }
      final toast = conflictToast(r.conflicts);
      if (toast != null) conflictNotice.value = toast;
      status.value = status.value.copyWith(
        state: CloudState.ok,
        lastSync: DateTime.fromMillisecondsSinceEpoch(now),
        pending: mirror.dirtyCount,
        message: fileMsg,
        clearMessage: fileMsg == null,
        conflicts: r.conflicts.isEmpty ? null : _mergeConflicts(r.conflicts, status.value.conflicts),
      );
    } on CloudError catch (e) {
      final signedOut = api.session == null;
      if (signedOut) _stop();
      status.value = status.value.copyWith(
        state: signedOut ? CloudState.signedOut : (e.offline ? CloudState.offline : CloudState.error),
        pending: mirror.dirtyCount,
        message: e.message,
      );
    } catch (e) {
      status.value = status.value.copyWith(state: CloudState.error, pending: mirror.dirtyCount, message: '$e');
    } finally {
      _running = false;
    }
    if (_again) {
      _again = false;
      unawaited(syncNow());
    }
  }

  /// รายการเดียวกัน (ตาราง + แถว + ช่อง) เก็บอันล่าสุดอันเดียว · สูงสุด 50
  List<SyncConflict> _mergeConflicts(List<SyncConflict> fresh, List<SyncConflict> old) {
    final seen = <String>{};
    return [
      for (final x in [...fresh, ...old])
        if (seen.add('${x.table}|${x.id}|${x.field}')) x,
    ].take(50).toList();
  }

  void clearConflicts() => status.value = status.value.copyWith(conflicts: const []);

  /// กด "ใช้อีกค่า"
  Future<void> useOtherValue(SyncConflict c) async {
    await mirror.useOtherValue(c, _now());
    status.value = status.value.copyWith(conflicts: [for (final x in status.value.conflicts) if (!identical(x, c)) x]);
    cal.refresh();
    cal.workRepo.refresh();
    cal.skillRepo.refresh();
    await syncNow();
  }
}
