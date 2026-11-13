/// ตัดสินวัน (รอบ 7 · M / M+): ผ่านวันไปแล้วงานสำคัญไม่ครบ → แปะสติกเกอร์ "พลาด" อัตโนมัติ
/// เวลาตัดสิน = เวลาตื่นของเช้าวันถัดไป (ไม่ใช่เที่ยงคืน) · โต้รุ่งต่อเวลาได้ · ปิดวันเองได้
/// ทำเสร็จทีหลัง → เปลี่ยนเป็นสติกเกอร์ "เสร็จย้อนหลัง" (หรือแค่ป้าย) ตามตั้งค่า
library;

import 'calendar_models.dart';
import 'calendar_repository.dart';

const autoStickerKey = 'auto_sticker'; // on (ค่าเริ่มต้น) / off
const missedStickerKey = 'auto_sticker_missed'; // id สติกเกอร์ "พลาดงาน"
const lateStickerKey = 'auto_sticker_late'; // id สติกเกอร์ "เสร็จย้อนหลัง"
const lateModeKey = 'auto_sticker_late_mode'; // swap (ค่าเริ่มต้น) / tag

/// ต่อเวลาตัดสินของวันนั้น (ISO) · ปิดวันเอง = ตัดสินทันที
String extendKey(DateTime day) => 'day_extend:${dayKey(day)}';
String closedKey(DateTime day) => 'day_closed:${dayKey(day)}';

/// สติกเกอร์ตั้งต้น (ถ้ายังไม่ได้เลือก): ชื่อในชุดของแอป
const _defaultMissed = 'เหนื่อยมาก';
const _defaultLate = 'ภูมิใจ';

/// งานสำคัญของวัน (●●● · ต้องทำจริง · ไม่นับว่างจากงาน / ยกเลิก / ย้ายออก)
List<Occurrence> importantOf(Iterable<Occurrence> items) =>
    items.where((o) => o.importance >= 3 && o.required).toList();

/// ยังมีงานสำคัญที่ไม่ได้ทำ
bool importantPending(Iterable<Occurrence> items) =>
    importantOf(items).any((o) => o.status == OccurrenceStatus.planned);

/// เวลาตัดสินตามปกติ = เวลาตื่นของเช้าวันถัดไป
DateTime defaultCutoff(DateTime day, List<LifeBaseDay> lifeBase) {
  final next = DateTime(day.year, day.month, day.day + 1);
  return atMinute(next, lifeBase[next.weekday - 1].wakeMinute);
}

/// วันที่ยังทำต่อได้ตอนนี้: ยังไม่ถึงเวลาตื่น = ยังเป็น "เมื่อวาน" (โต้รุ่ง)
DateTime openDay(DateTime now, List<LifeBaseDay> lifeBase) {
  final today = dayOnly(now);
  final wake = atMinute(today, lifeBase[today.weekday - 1].wakeMinute);
  return now.isBefore(wake) ? today.subtract(const Duration(days: 1)) : today;
}

/// เลยเวลานอนของ [day] แล้วไหม (เวลานอนก่อนเที่ยง = หลังเที่ยงคืน)
bool pastBedtime(DateTime now, DateTime day, List<LifeBaseDay> lifeBase) {
  final bed = lifeBase[day.weekday - 1].bedMinute;
  final at = bed < 12 * 60 ? atMinute(day.add(const Duration(days: 1)), bed) : atMinute(day, bed);
  return !now.isBefore(at);
}

Future<DateTime> cutoffOf(CalendarRepository repo, DateTime day, List<LifeBaseDay> lifeBase) async {
  final ext = DateTime.tryParse(await repo.getSetting(extendKey(day)) ?? '');
  return ext ?? defaultCutoff(day, lifeBase);
}

Future<Sticker?> _stickerFor(CalendarRepository repo, String key, String fallbackName) async {
  final all = [for (final p in await repo.stickerPacks()) ...p.stickers];
  final id = int.tryParse(await repo.getSetting(key) ?? '');
  return all.where((s) => s.id == id).firstOrNull ?? all.where((s) => s.name == fallbackName).firstOrNull;
}

Future<Sticker?> missedSticker(CalendarRepository repo) => _stickerFor(repo, missedStickerKey, _defaultMissed);
Future<Sticker?> lateSticker(CalendarRepository repo) => _stickerFor(repo, lateStickerKey, _defaultLate);

DateTime? _lastRun;

/// ตัดสินวันที่ผ่านมา (ย้อน 14 วัน) · คืนจำนวนวันที่แปะ "พลาด"
/// [force] = ไม่สนตัวกันรันถี่ (เทส / ปิดวันเอง)
Future<int> judgeDays(CalendarRepository repo, {DateTime? now, bool force = false}) async {
  final t = now ?? DateTime.now();
  if (!force && _lastRun != null && t.difference(_lastRun!).inSeconds.abs() < 30) return 0;
  _lastRun = t;
  if ((await repo.getSetting(autoStickerKey)) == 'off') return 0;
  final missed = await missedSticker(repo);
  if (missed == null) return 0;
  final lifeBase = await repo.lifeBase();
  final holidays = {for (final h in await repo.holidays()) dayKey(h.day)};
  final today = dayOnly(t);
  final occ = await repo.occurrencesBetween(today.subtract(const Duration(days: 14)), today);
  var placed = 0;
  for (var i = 14; i >= 0; i--) {
    final d = today.subtract(Duration(days: i));
    if (holidays.contains(dayKey(d))) continue;
    final closed = (await repo.getSetting(closedKey(d))) == 'on';
    if (!closed && t.isBefore(await cutoffOf(repo, d, lifeBase))) continue;
    final stuck = await repo.daySticker(d, d);
    if (stuck.any((s) => s.auto != null)) continue; // ตัดสินไปแล้ว
    if (!importantPending(occ[d] ?? await repo.occurrencesOn(d))) continue;
    await repo.stickDay(d, missed.id, highlight: true, auto: 'missed');
    placed++;
  }
  return placed;
}

/// หลังกด "ทำแล้ว": วันนั้นเคยถูกตัดสินว่าพลาด และตอนนี้งานสำคัญครบแล้ว → เสร็จย้อนหลัง
/// คืนข้อความ "ช้า …" (null = ไม่เกี่ยว)
Future<String?> afterDone(CalendarRepository repo, DateTime day, {DateTime? now}) async {
  final d = dayOnly(day);
  final auto = (await repo.daySticker(d, d)).where((s) => s.auto == 'missed').firstOrNull;
  if (auto == null) return null;
  if (importantPending(await repo.occurrencesOn(d))) return null;
  final late = (now ?? DateTime.now()).difference(await cutoffOf(repo, d, await repo.lifeBase()));
  final h = late.inHours, m = late.inMinutes % 60;
  final text = 'ทำย้อนหลัง · ช้า ${h > 0 ? '$h ชม. ' : ''}${m > 0 || h == 0 ? '$m นาที' : ''}'.trim();
  final swap = (await repo.getSetting(lateModeKey)) != 'tag';
  final lateS = await lateSticker(repo);
  if (swap && lateS != null) {
    await repo.swapDaySticker(auto.id, lateS.id, auto: 'late');
  } else {
    await repo.swapDaySticker(auto.id, auto.sticker.id, auto: 'late');
  }
  if (auto.note == null || auto.note!.isEmpty) await repo.updateDaySticker(auto.id, note: text);
  return text;
}
