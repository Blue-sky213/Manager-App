/// สติกเกอร์อารมณ์รายวัน (สมุดแปะสติกเกอร์)
/// แต่ละสติกเกอร์อยู่ใน "ชุด" · ชุดในตัวแอปซ่อนได้แต่ลบไม่ได้ · ชุดของผู้ใช้เพิ่ม / ลบได้
/// สติกเกอร์ 1 ชิ้น = อีโมจิ (ตอนนี้) หรือรูปภาพ (`imagePath` เตรียมไว้ รอระบบเลือกไฟล์)
library;

class Sticker {
  const Sticker({required this.id, required this.packId, required this.name, this.emoji, this.imagePath});
  final int id;
  final int packId;
  final String name;
  final String? emoji;
  final String? imagePath;

  /// สิ่งที่วาดบนจอ: อีโมจิ หรือตัวแรกของชื่อถ้ายังไม่มีรูป
  String get glyph => emoji ?? (name.isEmpty ? '?' : String.fromCharCode(name.runes.first));
}

class StickerPack {
  const StickerPack({required this.id, required this.name, this.builtin = false, this.enabled = true, this.stickers = const []});
  final int id;
  final String name;
  final bool builtin;
  final bool enabled;
  final List<Sticker> stickers;
}

/// สติกเกอร์ที่แปะในวันหนึ่ง (แปะได้หลายชิ้นต่อวัน)
class DaySticker {
  const DaySticker({
    required this.id,
    required this.day,
    required this.sticker,
    this.note,
    this.x,
    this.y,
    this.highlight = false,
    this.auto,
  });
  final int id;
  final DateTime day;
  final Sticker sticker;
  final String? note;

  /// ตำแหน่งในช่องวัน (0–1 จากซ้าย/บน) · null = วางตามลำดับ (v17)
  final double? x;
  final double? y;

  /// ⭐ ตัวใหญ่กลางช่อง (วันละ 1 ชิ้น)
  final bool highlight;

  /// แปะอัตโนมัติ: 'missed' (พลาดงาน) · 'late' (เสร็จย้อนหลัง) · null = แปะเอง
  final String? auto;

  DaySticker copyWith({String? note, bool clearNote = false, double? x, double? y, bool? highlight, Sticker? sticker, String? auto}) =>
      DaySticker(
        id: id,
        day: day,
        sticker: sticker ?? this.sticker,
        note: clearNote ? null : (note ?? this.note),
        x: x ?? this.x,
        y: y ?? this.y,
        highlight: highlight ?? this.highlight,
        auto: auto ?? this.auto,
      );
}

/// ตัวที่โชว์ใหญ่กลางช่อง: ⭐ ที่เลือกไว้ · ไม่ได้เลือก = ชิ้นแรกที่แปะ
/// ติดได้วันละกี่ชิ้น: ⭐ ใหญ่ 1 + เล็ก 3 = เห็นครบทุกชิ้นในช่องเดือน (เกินแล้วบางชิ้นถูกซ่อนเป็น +n)
const maxDayStickers = 4;

DaySticker? highlightOf(List<DaySticker> items) =>
    items.where((d) => d.highlight).firstOrNull ?? items.firstOrNull;

/// ชุดในตัวแอป (ชื่อ, [(ชื่อ, อีโมจิ)])
const builtinStickerPacks = [
  ('อารมณ์', [
    ('ภูมิใจ', '🥳'),
    ('แฮปปี้', '😊'),
    ('สบายใจ', '😌'),
    ('เฉย ๆ', '😐'),
    ('เหนื่อยมาก', '😩'),
    ('ผิดหวัง', '😞'),
    ('เศร้า', '😢'),
    ('หงุดหงิด', '😤'),
  ]),
  ('การทำงาน', [
    ('ทำได้ตามแผน', '🎯'),
    ('โฟกัส', '🔥'),
    ('ขยัน', '💪'),
    ('มีไอเดีย', '💡'),
    ('ง่วง', '😴'),
    ('ป่วย', '🤒'),
  ]),
];

/// ชื่อชุดที่เก็บสติกเกอร์ทีละชิ้นที่ผู้ใช้เพิ่มเอง
const myStickerPackName = 'สติกเกอร์ของฉัน';

/// สติกเกอร์ของแต่ละวันที่หน้าปฏิทินโหลดไว้ล่าสุด (หัววันในสัปดาห์ · ตารางเดือนอ่านจากตรงนี้)
Map<DateTime, List<Sticker>> stickersByDay = {};

/// สติกเกอร์ที่แปะพร้อมตำแหน่ง / ไฮไลต์ (ใช้วาดช่องเดือน)
Map<DateTime, List<DaySticker>> placedByDay = {};

/// วันหยุดของช่วงที่ปฏิทินโหลดอยู่ (วัน → ชื่อ) · ให้หัววันในมุมมองสัปดาห์โชว์ "หยุด"
Map<DateTime, String> holidaysByDay = {};
