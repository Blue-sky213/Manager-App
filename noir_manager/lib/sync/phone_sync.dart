/// เชื่อม PC ↔ iPhone (รอบ 14) ผ่านโฟลเดอร์ iCloud Drive ของแอป Scriptable
/// ไม่มี Mac → ทำแอป iPhone เต็มไม่ได้ · ใช้ Scriptable (ฟรี) ทำ widget + หน้าแก้ไขแทน
/// PC = ตัวหลัก: เขียน snapshot.json ให้มือถืออ่าน · มือถือเขียน "คำสั่ง" ลง inbox/ ให้ PC ทำ
/// คำสั่งทุกอันมี id · ทำแล้วจำไว้ → ไฟล์ซ้ำ / iCloud ส่งซ้ำ ไม่ทำสองรอบ
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../calendar/calendar_models.dart';
import '../calendar/calendar_repository.dart';
import '../skills/skill_models.dart';
import '../skills/skill_tree.dart';
import 'scriptable_script.dart';

const phoneSyncDirKey = 'phone_sync_dir';
const phoneSyncOnKey = 'phone_sync_on';
const _doneIdsKey = 'phone_sync_done_ids';
const snapshotVersion = 1;

/// วันที่ส่งไปมือถือ: วันนี้ + 7 วันข้างหน้า
const snapshotDays = 8;

/// โฟลเดอร์ของ Scriptable ใน iCloud for Windows (ชื่อแบบนี้เสมอ: iCloud~<bundle id>)
String? defaultPhoneSyncDir({Map<String, String>? env, String? os}) {
  env ??= Platform.environment;
  if ((os ?? Platform.operatingSystem) != 'windows') return null;
  final home = env['USERPROFILE'];
  if (home == null) return null;
  return '$home\\iCloudDrive\\iCloud~dk~simonbs~Scriptable\\NoirManager';
}

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "19:30" → นาทีตั้งแต่เที่ยงคืน · ผิดรูปแบบ = null
int? parseHm(Object? v) {
  if (v is! String) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(v.trim());
  if (m == null) return null;
  final h = int.parse(m[1]!), mi = int.parse(m[2]!);
  return h < 24 && mi < 60 ? h * 60 + mi : null;
}

DateTime? parseDay(Object? v) {
  if (v is! String) return null;
  final d = DateTime.tryParse(v);
  return d == null ? null : dayOnly(d);
}

// ---------------- PC → มือถือ ----------------

/// ภาพข้อมูลที่มือถือต้องใช้ (ไม่มี generatedAt · ใช้เทียบว่าเปลี่ยนไหม)
Future<Map<String, Object?>> buildSnapshot(CalendarRepository cal, DateTime now) async {
  final today = dayOnly(now);
  final skillRepo = cal.skillRepo;
  final skills = await skillRepo.skills();
  final skillOfAct = <int, int>{};
  for (final s in skills) {
    for (final a in await skillRepo.activitiesOf(s.id)) {
      skillOfAct[a] = s.id;
    }
  }
  final days = <Map<String, Object?>>[];
  for (var i = 0; i < snapshotDays; i++) {
    final d = today.add(Duration(days: i));
    final occ = (await cal.occurrencesOn(d))
        .where((o) => o.status == OccurrenceStatus.planned || o.status == OccurrenceStatus.done)
        .toList();
    days.add({
      'date': dayKey(d),
      'items': [
        for (final o in occ)
          {
            'occ': o.id,
            'act': o.activityId,
            'title': o.title,
            'start': o.startAt == null ? null : _hm(o.startAt!),
            'end': o.endAt == null ? null : _hm(o.endAt!),
            'done': o.status == OccurrenceStatus.done,
            'cat': o.categoryId,
            'imp': o.importance,
            if (o.session != null) 'session': o.session!.total == null ? '${o.session!.n}' : '${o.session!.n}/${o.session!.total}',
            if (skillOfAct[o.activityId] != null) 'skill': skillOfAct[o.activityId],
          }
      ],
    });
  }
  final cats = await cal.categories();
  final packs = await cal.stickerPacks();
  final checkin = await cal.checkin(today);
  final nodes = await skillRepo.nodes();
  final topics = await skillRepo.topics();
  return {
    'v': snapshotVersion,
    'today': dayKey(today),
    'days': days,
    'categories': [
      for (final c in cats)
        if (!c.hidden) {'id': c.id, 'name': c.name, 'icon': c.icon, 'color': c.colorKey, 'minutes': c.defaultMinutes}
    ],
    // สติกเกอร์รูปภาพยังไม่ส่ง (ไฟล์ใหญ่ · รอบหน้า) · ส่งเฉพาะอีโมจิ
    'stickers': [
      for (final p in packs)
        if (p.enabled)
          for (final s in p.stickers)
            if (s.emoji != null) {'id': s.id, 'name': s.name, 'emoji': s.emoji}
    ],
    'checkin': checkin == null
        ? null
        : {
            'energy': checkin.energy,
            'sleptAt': checkin.sleptAt == null ? null : _hm(checkin.sleptAt!),
            'wokeAt': checkin.wokeAt == null ? null : _hm(checkin.wokeAt!),
          },
    'skills': [
      for (final s in skills)
        if (s.status == SkillStatus.active) _skillJson(s, nodes, topics),
    ],
  };
}

Map<String, Object?> _skillJson(Skill s, List<SkillNode> allNodes, List<SkillTopic> allTopics) {
  final nodes = allNodes.where((n) => n.skillId == s.id).toList()
    ..sort((a, b) => a.sort != b.sort ? a.sort - b.sort : a.id - b.id);
  final ids = {for (final n in nodes) n.id};
  final topics = allTopics.where((t) => ids.contains(t.nodeId)).toList();
  final cur = nodes.where((n) => !nodePassed(n, topics)).firstOrNull;
  Map<String, Object?> t(SkillTopic x) => {'id': x.id, 'name': x.name, 'score': x.score, 'url': x.url};
  return {
    'id': s.id,
    'name': s.name,
    'icon': s.icon,
    'green': topics.where((x) => x.green).length,
    'scored': topics.where((x) => x.score != null).length,
    'total': topics.length,
    'current': cur == null
        ? null
        : {'id': cur.id, 'name': cur.name, 'url': cur.url, 'topics': [for (final x in topics) if (x.nodeId == cur.id) t(x)]},
    'review': [for (final x in topics) if (x.score != null && !x.green) t(x)],
  };
}

// ---------------- มือถือ → PC ----------------

enum CmdOutcome { applied, skipped, failed }

typedef CmdResult = ({CmdOutcome outcome, String message});

CmdResult _ok(String m) => (outcome: CmdOutcome.applied, message: m);
CmdResult _fail(String m) => (outcome: CmdOutcome.failed, message: m);

/// หางานครั้งนั้น: ใช้ id ก่อน · ไม่เจอ (เช่น PC แก้งานจนสร้างครั้งใหม่) → หาจากงานเดียวกันในวันเดียวกัน
Future<Occurrence?> _findOcc(CalendarRepository cal, Map cmd) async {
  final day = parseDay(cmd['date']);
  if (day == null) return null;
  final list = await cal.occurrencesOn(day);
  return list.where((o) => o.id == cmd['occ']).firstOrNull ??
      list.where((o) => o.activityId == cmd['act'] && o.status != OccurrenceStatus.moved).firstOrNull;
}

/// ทำ 1 คำสั่งจากมือถือ · ข้อมูลผิด / งานหายไปแล้ว = failed (ไม่เดา ไม่ทำแทน)
Future<CmdResult> applyPhoneCommand(CalendarRepository cal, Map cmd, DateTime now) async {
  switch (cmd['type']) {
    case 'done':
      final o = await _findOcc(cal, cmd);
      if (o == null) return _fail('ไม่พบงานนี้แล้ว (อาจถูกลบ / ย้ายบน PC)');
      await cal.setDone(o.id, cmd['done'] != false);
      return _ok('${cmd['done'] == false ? 'เลิกติ๊ก' : 'ทำแล้ว'}: ${o.title}');

    case 'add':
      final name = (cmd['name'] as String?)?.trim() ?? '';
      final day = parseDay(cmd['date']);
      if (name.isEmpty || day == null) return _fail('เพิ่มงาน: ไม่มีชื่อ / วัน');
      final cats = await cal.categories();
      final cat = cats.where((c) => c.id == cmd['cat']).firstOrNull ?? cats.firstOrNull;
      if (cat == null) return _fail('เพิ่มงาน: ยังไม่มีหมวด');
      final start = parseHm(cmd['start']);
      final minutes = (cmd['minutes'] as num?)?.toInt() ?? cat.defaultMinutes ?? 30;
      await cal.addActivity(NewActivity(
        name: name,
        categoryId: cat.id,
        importance: ((cmd['imp'] as num?)?.toInt() ?? cat.defaultImportance ?? 2).clamp(1, 3),
        timed: start != null,
        day: day,
        startMinute: start,
        durationMin: start == null ? null : minutes.clamp(5, 24 * 60),
      ));
      return _ok('เพิ่มงาน: $name');

    case 'move':
      final o = await _findOcc(cal, cmd);
      final to = parseDay(cmd['toDate']);
      if (o == null) return _fail('ไม่พบงานนี้แล้ว (อาจถูกลบ / ย้ายบน PC)');
      if (to == null) return _fail('เลื่อนงาน: ไม่มีวันใหม่');
      final s = parseHm(cmd['toStart']) ?? (o.startAt == null ? null : o.startAt!.hour * 60 + o.startAt!.minute);
      final len = o.startAt == null || o.endAt == null ? null : o.endAt!.difference(o.startAt!);
      final start = s == null ? null : to.add(Duration(minutes: s));
      await cal.moveOccurrence(o.id, to, start: start, end: start == null || len == null ? null : start.add(len));
      return _ok('เลื่อน: ${o.title} → ${dayKey(to)}${start == null ? '' : ' ${_hm(start)}'}');

    case 'checkin':
      final day = parseDay(cmd['date']);
      if (day == null) return _fail('เช็กอิน: ไม่มีวัน');
      final old = await cal.checkin(day) ?? Checkin(day: day);
      // นอนหลัง 18:00 = คืนก่อนหน้า · ก่อนนั้น = หลังเที่ยงคืนของวันนี้
      DateTime? at(int? m, {bool night = false}) =>
          m == null ? null : (night && m >= 18 * 60 ? day.subtract(const Duration(days: 1)) : day).add(Duration(minutes: m));
      final slept = parseHm(cmd['sleptAt']), woke = parseHm(cmd['wokeAt']);
      final energy = (cmd['energy'] as num?)?.toInt();
      await cal.saveCheckin(Checkin(
        day: day,
        sleptAt: at(slept, night: true) ?? old.sleptAt,
        wokeAt: at(woke) ?? old.wokeAt,
        energy: energy == null ? old.energy : energy.clamp(1, 5),
        missReason: old.missReason,
      ));
      final sticker = (cmd['sticker'] as num?)?.toInt();
      if (sticker != null) {
        final all = [for (final p in await cal.stickerPacks()) ...p.stickers];
        if (all.any((s) => s.id == sticker)) await cal.stickDay(day, sticker, note: (cmd['note'] as String?)?.trim());
      }
      return _ok('เช็กอิน ${dayKey(day)}');

    case 'skillLog':
      final r = cal.skillRepo;
      final skill = (await r.skills()).where((s) => s.id == cmd['skill']).firstOrNull;
      final day = parseDay(cmd['date']) ?? dayOnly(now);
      if (skill == null) return _fail('บันทึกรอบ: ไม่พบสกิลนี้แล้ว');
      final topic = (cmd['topic'] as num?)?.toInt(), score = (cmd['score'] as num?)?.toInt();
      if (topic != null && score != null && (await r.topics()).any((t) => t.id == topic)) {
        await r.addTopicScore(topic, score.clamp(0, 100), at: day);
      }
      await r.saveLog(SkillLog(
        skillId: skill.id,
        day: day,
        minutes: (cmd['minutes'] as num?)?.toInt(),
        rating: (cmd['rating'] as num?)?.toInt(),
        better: cmd['note'] as String?,
      ));
      return _ok('บันทึกรอบ: ${skill.name}');

    case 'topicScore':
      final r = cal.skillRepo;
      final topic = (await r.topics()).where((t) => t.id == cmd['topic']).firstOrNull;
      final score = (cmd['score'] as num?)?.toInt();
      if (topic == null || score == null) return _fail('ให้คะแนน: ไม่พบหัวข้อนี้แล้ว');
      await r.addTopicScore(topic.id, score.clamp(0, 100), at: parseDay(cmd['date']) ?? dayOnly(now));
      return _ok('${topic.name}: $score');
  }
  return _fail('ไม่รู้จักคำสั่ง "${cmd['type']}" (Scriptable ใหม่กว่า PC? อัปเดตแอป PC)');
}

// ---------------- ตัวรันบน PC ----------------

class SyncReport {
  const SyncReport({this.applied = const [], this.failed = const [], this.wrote = false});
  final List<String> applied;
  final List<String> failed;
  final bool wrote;
}

/// 1 รอบ: ทำคำสั่งใน inbox/ → เขียน snapshot.json ถ้าข้อมูลเปลี่ยน
class PhoneSync {
  PhoneSync(this.cal, this.dir);
  final CalendarRepository cal;
  final Directory dir;
  String? _last;

  File get snapshotFile => File('${dir.path}${Platform.pathSeparator}snapshot.json');
  Directory get inboxDir => Directory('${dir.path}${Platform.pathSeparator}inbox');

  /// โค้ด Scriptable อยู่ที่โฟลเดอร์แม่ (ราก Scriptable) → โผล่เป็นสคริปต์ในแอปบน iPhone เอง
  File get scriptFile => File('${dir.parent.path}${Platform.pathSeparator}$scriptableFileName');

  Future<SyncReport> runOnce(DateTime now) async {
    await inboxDir.create(recursive: true);
    if (!scriptFile.existsSync() || scriptFile.readAsStringSync() != scriptableSource) {
      await scriptFile.writeAsString(scriptableSource);
    }
    final applied = <String>[], failed = <String>[];
    final doneIds = ((await cal.getSetting(_doneIdsKey)) ?? '').split(',').where((s) => s.isNotEmpty).toList();
    final files = inboxDir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => a.path.compareTo(b.path)); // ชื่อไฟล์ขึ้นต้นด้วยเวลา → ทำตามลำดับที่กด
    for (final f in files) {
      Map? cmd;
      try {
        cmd = jsonDecode(await f.readAsString()) as Map?;
      } catch (_) {
        // iCloud ยังโหลดไฟล์ไม่ครบ → รอบหน้าค่อยอ่าน
        continue;
      }
      final id = cmd?['id']?.toString() ?? f.path;
      if (cmd != null && !doneIds.contains(id)) {
        try {
          final r = await applyPhoneCommand(cal, cmd, now);
          (r.outcome == CmdOutcome.applied ? applied : failed).add(r.message);
        } catch (e) {
          failed.add('${cmd['type']}: $e');
        }
        doneIds.add(id);
      }
      try {
        await f.delete();
      } catch (_) {/* ลบไม่ได้ = ครั้งหน้าเจอ id เดิม ข้าม */}
    }
    if (applied.isNotEmpty || failed.isNotEmpty) {
      final keep = doneIds.length > 500 ? doneIds.sublist(doneIds.length - 500) : doneIds;
      await cal.setSetting(_doneIdsKey, keep.join(','));
    }
    final data = await buildSnapshot(cal, now);
    final body = jsonEncode(data);
    var wrote = false;
    if (body != _last || !snapshotFile.existsSync()) {
      // เขียนไฟล์ชั่วคราวแล้วเปลี่ยนชื่อ → มือถือไม่เจอไฟล์ครึ่ง ๆ
      final tmp = File('${snapshotFile.path}.tmp');
      await tmp.writeAsString(jsonEncode({...data, 'generatedAt': now.toIso8601String()}));
      await tmp.rename(snapshotFile.path);
      _last = body;
      wrote = true;
    }
    return SyncReport(applied: applied, failed: failed, wrote: wrote);
  }
}

/// สถานะให้หน้าตั้งค่าแสดง
class PhoneSyncStatus {
  const PhoneSyncStatus({this.dir, this.on = false, this.lastWrite, this.lastRun, this.applied = 0, this.recent = const [], this.error});
  final String? dir;
  final bool on;
  final DateTime? lastWrite;
  final DateTime? lastRun;
  final int applied;

  /// ล่าสุดก่อน (สูงสุด 20)
  final List<String> recent;
  final String? error;
}

/// ทำงานเบื้องหลังตอนแอป PC เปิดอยู่: ทุก 30 วินาที + หลังข้อมูลเปลี่ยน 2 วินาที
class PhoneSyncService {
  PhoneSyncService(this.cal, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final CalendarRepository cal;
  final DateTime Function() _clock;
  final status = ValueNotifier(const PhoneSyncStatus());

  /// ตัวที่แอปจริงใช้ (โหมดข้อมูลตัวอย่างไม่มี → ไม่เขียนทับไฟล์ของจริง)
  static PhoneSyncService? instance;

  PhoneSync? _sync;
  Timer? _timer, _debounce;
  bool _running = false;

  Future<void> start() async {
    final on = await cal.getSetting(phoneSyncOnKey) == 'on';
    final dir = await cal.getSetting(phoneSyncDirKey) ?? defaultPhoneSyncDir();
    status.value = PhoneSyncStatus(dir: dir, on: on);
    if (on && dir != null) _begin(dir);
  }

  void _begin(String dir) {
    _sync = PhoneSync(cal, Directory(dir));
    cal.addListener(_onChange);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => runNow());
    runNow();
  }

  void _onChange() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), runNow);
  }

  /// เปิด / ปิด + เปลี่ยนโฟลเดอร์ (จากหน้าตั้งค่า)
  Future<void> configure({required bool on, required String dir}) async {
    await cal.setSetting(phoneSyncOnKey, on ? 'on' : 'off');
    await cal.setSetting(phoneSyncDirKey, dir);
    stop();
    status.value = PhoneSyncStatus(dir: dir, on: on);
    if (on) _begin(dir);
  }

  void stop() {
    _timer?.cancel();
    _debounce?.cancel();
    cal.removeListener(_onChange);
    _sync = null;
  }

  Future<SyncReport?> runNow() async {
    final s = _sync;
    if (s == null || _running) return null;
    _running = true;
    final old = status.value;
    try {
      final r = await s.runOnce(_clock());
      final now = _clock();
      status.value = PhoneSyncStatus(
        dir: old.dir,
        on: true,
        lastRun: now,
        lastWrite: r.wrote ? now : old.lastWrite,
        applied: old.applied + r.applied.length,
        recent: [...r.failed.map((m) => '⚠ $m'), ...r.applied, ...old.recent].take(20).toList(),
      );
      return r;
    } catch (e) {
      status.value = PhoneSyncStatus(
          dir: old.dir, on: true, lastRun: _clock(), lastWrite: old.lastWrite, applied: old.applied, recent: old.recent, error: '$e');
      return null;
    } finally {
      _running = false;
    }
  }
}
