/// ซิงก์บัญชี (รอบ 16): แปลง SQLite ในเครื่อง ↔ "รายการกลาง" ที่เหมือนกันทุกเครื่อง
///
/// - id ในเครื่อง (1, 2, 3 …) แต่ละเครื่องไม่ตรงกัน → ทุกแถวมี "รหัสกลาง" (sync id) เก็บคู่ไว้ใน sync_map
/// - ช่องที่อ้างถึงแถวอื่น (เช่น activity_id) ส่งขึ้นเป็นรหัสกลาง แล้วแปลงกลับเป็น id ของเครื่องที่รับ
/// - sync_shadow = ค่าล่าสุดที่รู้ + เวลาที่แก้แต่ละช่อง · สแกนแล้วเจอช่องเปลี่ยน = ประทับเวลาตอนนั้น
///   (สแกนทุกครั้งที่ข้อมูลเปลี่ยน แม้ไม่มีเน็ต → "เวลาที่กดแก้" ใกล้ความจริง)
/// - ไม่แก้ตารางเดิม ไม่เพิ่มคอลัมน์ในตารางเดิม
library;

import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import 'merge.dart';
import 'sync_remote.dart';

/// ตารางที่ไม่ซิงก์
const _skipTables = {'sync_map', 'sync_shadow', 'android_metadata', 'sqlite_sequence'};

/// ช่องที่อ้างถึงแถวอื่นแต่ไม่ได้ประกาศ REFERENCES ไว้ (ตารางเก่า) · ต้องครบ ไม่งั้นเครื่องอื่นได้ id ผิด
const extraRefs = <String, Map<String, String>>{
  'activity': {'subject_id': 'subject'},
  'project_task': {'activity_id': 'activity'},
  'project_payment': {'entry_id': 'money_entry'},
  'money_entry': {'project_id': 'project'},
  'skill_log': {'occurrence_id': 'occurrence'},
  'skill_activity': {'activity_id': 'activity'},
  'class_log': {'task_activity_id': 'activity'},
  'skill': {'branch_id': 'skill_branch'},
};

/// setting ที่เป็นของเครื่องนี้ (ไม่ซิงก์): บัญชี · iCloud · หน้าต่าง · และค่าที่เก็บ id ในเครื่อง
const _deviceOnlySettings = {
  'fullscreen',
  'device_preview',
  'auto_sticker_missed',
  'auto_sticker_late',
  'commit_ids',
  'sim_timetable_ids',
  'clash_ignored',
};

bool deviceOnlySetting(String key) =>
    key.startsWith('cloud_') || key.startsWith('phone_sync') || _deviceOnlySettings.contains(key);

/// v24: ตารางของระบบซิงก์ (เพิ่มอย่างเดียว ไม่แตะตารางเดิม)
Future<void> createSyncV24(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sync_map (
      tbl      TEXT    NOT NULL,
      local_id INTEGER NOT NULL,
      sid      TEXT    NOT NULL,
      PRIMARY KEY (tbl, local_id)
    )''');
  await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS sync_map_sid ON sync_map(tbl, sid)');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sync_shadow (
      tbl        TEXT    NOT NULL,
      sid        TEXT    NOT NULL,
      vals       TEXT    NOT NULL,
      stamps     TEXT    NOT NULL,
      deleted_at INTEGER,
      dirty      INTEGER NOT NULL DEFAULT 0,
      pending    INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (tbl, sid)
    )''');
}

class TableSpec {
  TableSpec(this.name, this.columns, this.pk, this.refs, this.notNull);

  final String name;
  final List<String> columns;
  final List<String> pk;

  /// ช่อง → ตารางที่อ้างถึง
  final Map<String, String> refs;
  final Set<String> notNull;

  bool get intId => pk.length == 1 && pk.first == 'id';
  bool get selfRef => refs.values.contains(name);
}

/// อ่านโครงตารางจาก DB จริง · เรียงแม่ก่อนลูก
Future<List<TableSpec>> readSpecs(DatabaseExecutor db) async {
  final names = [
    for (final r in await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"))
      r['name'] as String,
  ].where((n) => !_skipTables.contains(n) && !n.startsWith('sqlite_')).toList();
  final specs = <String, TableSpec>{};
  for (final n in names) {
    final info = await db.rawQuery('PRAGMA table_info($n)');
    final cols = [for (final c in info) c['name'] as String];
    final pkCols = [for (final c in info.where((c) => (c['pk'] as int) > 0).toList()..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int))) c['name'] as String];
    final notNull = {for (final c in info) if (c['notnull'] == 1) c['name'] as String};
    final refs = <String, String>{};
    for (final f in await db.rawQuery('PRAGMA foreign_key_list($n)')) {
      refs[f['from'] as String] = f['table'] as String;
    }
    for (final e in (extraRefs[n] ?? const <String, String>{}).entries) {
      if (cols.contains(e.key) && names.contains(e.value)) refs[e.key] = e.value;
    }
    refs.removeWhere((_, t) => !names.contains(t));
    specs[n] = TableSpec(n, cols, pkCols.isEmpty ? ['rowid'] : pkCols, refs, notNull);
  }
  // แม่ก่อนลูก (ไม่นับอ้างตัวเอง)
  final out = <TableSpec>[];
  final done = <String>{};
  void visit(String n, Set<String> path) {
    if (done.contains(n) || path.contains(n)) return;
    path.add(n);
    for (final p in specs[n]!.refs.values) {
      if (p != n) visit(p, path);
    }
    path.remove(n);
    if (done.add(n)) out.add(specs[n]!);
  }

  for (final n in names) {
    visit(n, {});
  }
  return out;
}

String _canon(Map<String, Object?> v) {
  final keys = v.keys.toList()..sort();
  return jsonEncode([for (final k in keys) [k, v[k]]]);
}

bool _sameVal(Object? a, Object? b) => a == b || (a is num && b is num && a.toDouble() == b.toDouble());

bool sameValues(Map<String, Object?> a, Map<String, Object?> b) =>
    a.length == b.length && a.keys.every((k) => b.containsKey(k) && _sameVal(a[k], b[k]));

bool sameRow(SyncRow? a, SyncRow? b) {
  if (a == null || b == null) return a == b;
  return a.deletedAt == b.deletedAt &&
      sameValues(a.values, b.values) &&
      a.stamps.length == b.stamps.length &&
      a.stamps.keys.every((k) => a.stamps[k] == b.stamps[k]);
}

class RoundResult {
  RoundResult({this.pulled = 0, this.applied = 0, this.pushed = 0, this.conflicts = const [], this.wiped = false});
  final int pulled;
  final int applied;
  final int pushed;
  final List<SyncConflict> conflicts;

  /// เครื่องใหม่ (ยังไม่มีข้อมูลจริง) → ล้างข้อมูลตั้งต้นแล้วดึงจากบัญชีทั้งหมด
  final bool wiped;
}

/// ตัวกลางระหว่าง SQLite ในเครื่อง กับรายการกลาง
class LocalMirror {
  LocalMirror(this.db, {Random? random}) : _rnd = random ?? Random.secure();

  final Database db;
  final Random _rnd;

  List<TableSpec> specs = const [];
  final _byName = <String, TableSpec>{};

  /// tbl → (id ในเครื่อง → รหัสกลาง) และกลับกัน
  final _l2s = <String, Map<int, String>>{};
  final _s2l = <String, Map<String, int>>{};
  final _newMaps = <(String, int, String)>[];

  /// tbl → รหัสกลาง → แถวล่าสุดที่รู้
  final _shadow = <String, Map<String, SyncRow>>{};
  final _dirty = <String>{}; // 'tbl\tsid'
  final _pending = <String>{};
  final _touched = <String>{};

  bool _loaded = false;

  Future<void> load() async {
    specs = await readSpecs(db);
    _byName
      ..clear()
      ..addEntries(specs.map((s) => MapEntry(s.name, s)));
    _l2s.clear();
    _s2l.clear();
    for (final r in await db.query('sync_map')) {
      final t = r['tbl'] as String, l = r['local_id'] as int, s = r['sid'] as String;
      (_l2s[t] ??= {})[l] = s;
      (_s2l[t] ??= {})[s] = l;
    }
    _shadow.clear();
    _dirty.clear();
    _pending.clear();
    for (final r in await db.query('sync_shadow')) {
      final t = r['tbl'] as String, s = r['sid'] as String;
      final row = SyncRow(
        table: t,
        id: s,
        values: (jsonDecode(r['vals'] as String) as Map).cast<String, Object?>(),
        stamps: (jsonDecode(r['stamps'] as String) as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())),
        deletedAt: r['deleted_at'] as int?,
      );
      (_shadow[t] ??= {})[s] = row;
      if (r['dirty'] == 1) _dirty.add('$t\t$s');
      if (r['pending'] == 1) _pending.add('$t\t$s');
    }
    _loaded = true;
  }

  int get dirtyCount => _dirty.length;

  /// เคยซิงก์อะไรไปแล้วหรือยัง
  bool get hasShadow => _shadow.values.any((m) => m.isNotEmpty);

  SyncRow? shadowOf(String table, String sid) => _shadow[table]?[sid];

  String _uuid() {
    final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  void _map(String t, int local, String sid) {
    final old = _s2l[t]?[sid];
    if (old != null && old != local) _l2s[t]?.remove(old);
    (_l2s[t] ??= {})[local] = sid;
    (_s2l[t] ??= {})[sid] = local;
    _newMaps.add((t, local, sid));
  }

  /// ค่าในรูปกลาง: ช่องอ้างถึง → รหัสกลาง · ไม่รวม id ของเครื่อง
  Map<String, Object?> _toSync(TableSpec t, Map<String, Object?> row) {
    final out = <String, Object?>{};
    for (final c in t.columns) {
      if (t.intId && c == 'id') continue;
      final v = row[c];
      final parent = t.refs[c];
      out[c] = (parent != null && v != null) ? (_l2s[parent] ?? const {})[(v as num).toInt()] : v;
    }
    return out;
  }

  /// รหัสกลางของแถวที่ไม่มี id ตัวเลข = ค่าคีย์หลัก (แปลงช่องอ้างถึงแล้ว) · null = แม่ยังไม่มีรหัส
  String? _naturalSid(TableSpec t, Map<String, Object?> syncVals) {
    final parts = <String>[];
    for (final c in t.pk) {
      final v = syncVals[c];
      if (v == null && t.refs.containsKey(c)) return null;
      parts.add('$v');
    }
    return parts.join('|');
  }

  String _sidFor(TableSpec t, Map<String, Object?> row, Map<String, Object?> pre, Map<String, String>? content) {
    if (!t.intId) return _naturalSid(t, pre)!;
    final id = (row['id'] as num).toInt();
    final known = _l2s[t.name]?[id];
    if (known != null) return known;
    String sid;
    // ครั้งที่เกิดจากงานซ้ำ: ทุกเครื่องสร้างเองได้ → รหัสคงที่ ไม่ซ้ำกัน
    if (t.name == 'occurrence' && row['origin_day'] != null && pre['activity_id'] != null) {
      sid = 'o:${pre['activity_id']}@${row['origin_day']}';
    } else {
      final match = content?[_canon(pre)];
      final taken = match != null && (_s2l[t.name] ?? const <String, int>{}).containsKey(match);
      sid = (match != null && !taken) ? match : _uuid();
    }
    _map(t.name, id, sid);
    return sid;
  }

  /// สแกนข้อมูลในเครื่อง → ช่องที่เปลี่ยนได้เวลา [now] · แถวที่หายไป = ลบเมื่อ [now]
  /// [content] (ซิงก์ครั้งแรก) = ค่าเหมือนกันทุกช่องกับรายการในบัญชี → ใช้รหัสเดียวกัน (กันซ้ำ)
  Future<void> scan(int now, {Map<String, Map<String, String>>? content}) async {
    if (!_loaded) await load();
    for (final t in specs) {
      var rows = await db.query(t.name);
      if (t.name == 'setting') rows = rows.where((r) => !deviceOnlySetting('${r['key']}')).toList();
      final keyed = <(String, Map<String, Object?>)>[];
      for (final r in rows) {
        final pre = _toSync(t, r);
        if (!t.intId && _naturalSid(t, pre) == null) continue;
        keyed.add((_sidFor(t, r, pre, content?[t.name]), t.selfRef ? r : pre));
      }
      final sh = _shadow[t.name] ??= {};
      final seen = <String>{};
      for (final (sid, r) in keyed) {
        final vals = t.selfRef ? _toSync(t, r) : r;
        seen.add(sid);
        final old = sh[sid];
        if (old == null || old.deleted) {
          // ครั้งงานซ้ำที่แอปสร้างเอง: ค่าตั้งต้น (ว่าง / planned) = เวลาเก่าสุด → การแก้จริงจากเครื่องอื่นชนะเสมอ
          final auto = old == null && sid.startsWith('o:');
          int stampOf(String k) =>
              auto && (vals[k] == null || (k == 'status' && vals[k] == 'planned') || k == 'activity_id' || k == 'origin_day') ? 1 : now;
          sh[sid] = SyncRow(table: t.name, id: sid, values: vals, stamps: {for (final k in vals.keys) k: stampOf(k)});
          _dirty.add('${t.name}\t$sid');
          _touched.add('${t.name}\t$sid');
          _pending.remove('${t.name}\t$sid');
          continue;
        }
        final changed = [for (final k in vals.keys) if (!old.values.containsKey(k) || !_sameVal(vals[k], old.values[k])) k];
        if (changed.isEmpty) continue;
        sh[sid] = old.copyWith(
          values: {...old.values, ...vals},
          stamps: {...old.stamps, for (final k in changed) k: now},
        );
        _dirty.add('${t.name}\t$sid');
        _touched.add('${t.name}\t$sid');
      }
      for (final e in sh.entries.toList()) {
        if (seen.contains(e.key) || e.value.deleted || _pending.contains('${t.name}\t${e.key}')) continue;
        sh[e.key] = e.value.copyWith(deletedAt: now);
        _dirty.add('${t.name}\t${e.key}');
        _touched.add('${t.name}\t${e.key}');
      }
    }
  }

  /// เขียนแถวกลางลง SQLite ในเครื่อง · false = ยังเขียนไม่ได้ (แม่ยังไม่มา) → ลองใหม่รอบหน้า
  Future<bool> _apply(SyncRow r) async {
    final t = _byName[r.table];
    if (t == null) return true; // ตารางที่เครื่องนี้ยังไม่มี (แอปเวอร์ชันเก่า) → ข้าม
    if (t.name == 'setting' && deviceOnlySetting('${r.values['key'] ?? r.id}')) return true;
    // แปลงกลับเป็นค่าในเครื่อง
    final local = <String, Object?>{};
    for (final e in r.values.entries) {
      if (!t.columns.contains(e.key) || (t.intId && e.key == 'id')) continue;
      final parent = t.refs[e.key];
      if (parent != null && e.value != null) {
        final id = _s2l[parent]?['${e.value}'];
        if (id == null && !r.deleted) {
          if (parent == t.name) {
            local[e.key] = null; // อ้างตัวเอง (เช่น ย้ายมาจาก) · แม่ยังไม่มา = ปล่อยว่าง
            continue;
          }
          if (t.notNull.contains(e.key) || t.pk.contains(e.key)) return false;
        }
        local[e.key] = id;
      } else {
        local[e.key] = e.value;
      }
    }
    if (t.intId) {
      final id = _s2l[t.name]?[r.id];
      if (r.deleted) {
        if (id != null) await db.delete(t.name, where: 'id = ?', whereArgs: [id]);
        return true;
      }
      if (id != null && (await db.query(t.name, columns: ['id'], where: 'id = ?', whereArgs: [id])).isNotEmpty) {
        await db.update(t.name, local, where: 'id = ?', whereArgs: [id]);
        return true;
      }
      try {
        _map(t.name, await db.insert(t.name, local), r.id);
      } on DatabaseException catch (e) {
        if (!e.isUniqueConstraintError() || t.name != 'occurrence') rethrow;
        // ครั้งงานซ้ำวันเดียวกัน เครื่องนี้สร้างไว้แล้ว → ใช้แถวเดิม
        final ex = await db.query('occurrence',
            columns: ['id'], where: 'activity_id = ? AND origin_day = ?', whereArgs: [local['activity_id'], local['origin_day']]);
        if (ex.isEmpty) rethrow;
        final exId = ex.first['id'] as int;
        _map(t.name, exId, r.id);
        await db.update(t.name, local, where: 'id = ?', whereArgs: [exId]);
      }
      return true;
    }
    final where = t.pk.map((c) => '$c = ?').join(' AND ');
    final args = [for (final c in t.pk) local[c]];
    if (args.contains(null)) return r.deleted;
    if (r.deleted) {
      await db.delete(t.name, where: where, whereArgs: args);
      return true;
    }
    final exists = (await db.query(t.name, where: where, whereArgs: args, limit: 1)).isNotEmpty;
    if (exists) {
      final set = {for (final e in local.entries) if (!t.pk.contains(e.key)) e.key: e.value};
      if (set.isNotEmpty) await db.update(t.name, set, where: where, whereArgs: args);
    } else {
      await db.insert(t.name, local);
    }
    return true;
  }

  /// ใช้ค่าที่รวมแล้ว: เขียนลงเครื่อง + จำเป็นค่าล่าสุด · [push] = ต้องส่งขึ้นบัญชีด้วย
  Future<bool> put(SyncRow merged, {required bool push}) async {
    final key = '${merged.table}\t${merged.id}';
    final ok = await _apply(merged);
    (_shadow[merged.table] ??= {})[merged.id] = merged;
    ok ? _pending.remove(key) : _pending.add(key);
    push ? _dirty.add(key) : _dirty.remove(key);
    _touched.add(key);
    return ok;
  }

  /// เครื่องนี้ยังไม่มีข้อมูลจริง (มีแค่ค่าตั้งต้นตอนติดตั้ง)
  Future<bool> isFresh() async {
    for (final t in const ['activity', 'checkin', 'money_entry', 'project', 'skill_log', 'day_sticker', 'class_log']) {
      if (!_byName.containsKey(t)) continue;
      final n = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $t')) ?? 0;
      if (n > 0) return false;
    }
    return true;
  }

  /// ล้างข้อมูลตั้งต้นของเครื่องใหม่ (ลูกก่อนแม่) · setting ของเครื่องนี้เก็บไว้
  Future<void> wipeLocal() async {
    for (final t in specs.reversed) {
      if (t.name == 'setting') {
        final keys = [for (final r in await db.query('setting', columns: ['key'])) '${r['key']}'];
        for (final k in keys.where((k) => !deviceOnlySetting(k))) {
          await db.delete('setting', where: 'key = ?', whereArgs: [k]);
        }
      } else {
        await db.delete(t.name);
      }
    }
    await db.delete('sync_map');
    await db.delete('sync_shadow');
    await load();
  }

  /// บันทึกคู่รหัส + ค่าล่าสุดลงเครื่อง
  Future<void> save() async {
    await db.transaction((txn) async {
      for (final (t, l, s) in _newMaps) {
        await txn.delete('sync_map', where: 'tbl = ? AND sid = ?', whereArgs: [t, s]);
        await txn.insert('sync_map', {'tbl': t, 'local_id': l, 'sid': s}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final key in _touched) {
        final [t, s] = key.split('\t');
        final r = _shadow[t]?[s];
        if (r == null) continue;
        await txn.insert(
          'sync_shadow',
          {
            'tbl': t,
            'sid': s,
            'vals': jsonEncode(r.values),
            'stamps': jsonEncode(r.stamps),
            'deleted_at': r.deletedAt,
            'dirty': _dirty.contains(key) ? 1 : 0,
            'pending': _pending.contains(key) ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    _newMaps.clear();
    _touched.clear();
  }

  /// แถวที่ต้องส่งขึ้นบัญชี
  List<SyncRow> dirtyRows() => [
        for (final k in _dirty) ?_shadow[k.split('\t')[0]]?[k.split('\t')[1]],
      ];

  void markPushed(Iterable<SyncRow> rows) {
    for (final r in rows) {
      final k = '${r.table}\t${r.id}';
      if (_dirty.remove(k)) _touched.add(k);
    }
  }

  /// 1 รอบซิงก์: สแกน → ดึง → รวม → เขียนลงเครื่อง → ส่งขึ้น
  /// [lastSync] = เวลาซิงก์สำเร็จครั้งก่อน (ms) · [lastRev] = เลขลำดับล่าสุดที่เคยดึง
  Future<(RoundResult, int)> round(SyncRemote remote, {required int now, required int lastSync, required int lastRev}) async {
    if (!_loaded) await load();
    var wiped = false;
    List<RemoteRow> pulled;
    if (lastRev == 0) {
      // ครั้งแรกของเครื่องนี้: ดึงก่อน แล้วค่อยสแกน (จับคู่รายการที่เหมือนกันทุกช่อง ไม่ให้ซ้ำ)
      pulled = await remote.pull(0);
      if (pulled.isNotEmpty && !hasShadow && await isFresh()) {
        await wipeLocal();
        wiped = true;
      }
      final content = <String, Map<String, String>>{};
      for (final p in pulled) {
        if (!p.row.deleted) (content[p.row.table] ??= {})[_canon(p.row.values)] = p.row.id;
      }
      final had = {for (final e in _shadow.entries) for (final k in e.value.keys) '${e.key}\t$k'};
      await scan(now, content: content);
      // รอบ 20 (บั๊กย้ายเครื่อง): รายการที่ทั้งเครื่องนี้และบัญชีมี แต่เครื่องนี้ยังไม่เคยซิงก์
      // = ค่าตั้งต้นตอนติดตั้ง (เช่น เวลานอน 12:00) → ให้ค่าในบัญชีชนะ ไม่นับเป็นค่าต่าง
      for (final p in pulled) {
        final key = '${p.row.table}\t${p.row.id}';
        final mine = _shadow[p.row.table]?[p.row.id];
        if (mine == null || had.contains(key)) continue;
        _shadow[p.row.table]![p.row.id] = mine.copyWith(stamps: {for (final k in mine.stamps.keys) k: 0});
      }
    } else {
      // สแกนก่อนเสมอ (เน็ตหลุดก็ยังประทับเวลาที่แก้จริงได้)
      await scan(now);
      await save();
      pulled = await remote.pull(lastRev);
    }

    final conflicts = <SyncConflict>[];
    var applied = 0;
    final order = {for (final (i, s) in specs.indexed) s.name: i};
    pulled.sort((a, b) {
      final c = (order[a.row.table] ?? 999).compareTo(order[b.row.table] ?? 999);
      return c != 0 ? c : a.rev.compareTo(b.rev);
    });
    var maxRev = lastRev;
    for (final p in pulled) {
      if (p.rev > maxRev) maxRev = p.rev;
      final key = '${p.row.table}\t${p.row.id}';
      final mine = _shadow[p.row.table]?[p.row.id];
      // เครื่องนี้ยังเขียนไม่ได้ (pending) = ยังไม่มีค่าของตัวเอง
      final local = _pending.contains(key) ? null : mine;
      final m = mergeRow(local, p.row, lastSync: lastSync);
      conflicts.addAll(m.conflicts);
      final merged = m.row!;
      final changedHere = !sameRow(merged, mine) || _pending.contains(key);
      final needPush = !sameRow(merged, p.row);
      if (changedHere) {
        await put(merged, push: needPush || _dirty.contains(key));
        applied++;
      } else if (!needPush) {
        _dirty.remove(key);
        _touched.add(key);
      }
    }
    // แถวที่ค้างจากรอบก่อน (แม่ยังไม่มา) → ลองใหม่
    for (final k in _pending.toList()) {
      final [t, s] = k.split('\t');
      final r = _shadow[t]?[s];
      if (r != null && await _apply(r)) {
        _pending.remove(k);
        _touched.add(k);
        applied++;
      }
    }
    await save();

    final out = dirtyRows();
    if (out.isNotEmpty) {
      await remote.push(out);
      markPushed(out);
      await save();
    }
    return (RoundResult(pulled: pulled.length, applied: applied, pushed: out.length, conflicts: conflicts, wiped: wiped), maxRev);
  }

  /// กด "ใช้อีกค่า" ของรายการที่ต่างกัน
  Future<void> useOtherValue(SyncConflict c, int now) async {
    final cur = _shadow[c.table]?[c.id];
    if (cur == null) return;
    await put(useOther(cur, c, now: now), push: true);
    await save();
  }
}
