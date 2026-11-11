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
  const DaySticker({required this.id, required this.day, required this.sticker, this.note});
  final int id;
  final DateTime day;
  final Sticker sticker;
  final String? note;
}

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
