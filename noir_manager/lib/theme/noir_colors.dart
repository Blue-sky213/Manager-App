import 'package:flutter/material.dart';

/// ชุดสีของ Noir Manager (คัดลอกค่าจาก Mockup 2D Dark/Light)
///
/// ใช้ ThemeExtension เพื่อ "แนบ" สีของเราเข้าไปใน Theme ของ Flutter
/// เวลาใช้: `final c = context.noir;` แล้วเรียก `c.surface`, `c.muted` ...
@immutable
class NoirColors extends ThemeExtension<NoirColors> {
  const NoirColors({
    required this.bg,
    required this.side,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.line2,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.navBg,
    required this.navText,
    required this.good,
    required this.warn,
    required this.bad,
    required this.flag,
    required this.flagText,
    required this.amberBg,
    required this.amberText,
  });

  final Color bg; // พื้นหลังทั้งหน้า
  final Color side; // แถบเมนูด้านซ้าย
  final Color surface; // การ์ด
  final Color surface2; // กล่องย่อยในการ์ด
  final Color line; // เส้นขอบบาง
  final Color line2; // เส้นขอบปุ่ม
  final Color text; // ตัวหนังสือหลัก
  final Color muted; // ตัวหนังสือรอง (สีจาง)
  final Color accent; // สีเน้น (ปุ่มหลัก)
  final Color onAccent; // ตัวหนังสือบนสีเน้น
  final Color navBg; // พื้นเมนูที่ถูกเลือก
  final Color navText; // ตัวหนังสือเมนูที่ถูกเลือก
  final Color good; // คะแนน >80%
  final Color warn; // คะแนน 60–80%
  final Color bad; // คะแนน <60%
  final Color flag; // ขอบป้าย "ธงอาจออกสอบ"
  final Color flagText; // ตัวหนังสือป้ายธง
  final Color amberBg; // พื้นป้ายเตือน (เช็กซ้ำ)
  final Color amberText; // ตัวหนังสือป้ายเตือน

  static const dark = NoirColors(
    bg: Color(0xFF111316),
    side: Color(0xFF16191D),
    surface: Color(0xFF1A1D22),
    surface2: Color(0xFF20252C),
    line: Color(0xFF262A31),
    line2: Color(0xFF343944),
    text: Color(0xFFECEEF1),
    muted: Color(0xFFA3A9B3),
    accent: Color(0xFF5B9DFF),
    onAccent: Color(0xFF0B1220),
    navBg: Color(0xFF23324A),
    navText: Color(0xFFECEEF1),
    good: Color(0xFF4CC38A),
    warn: Color(0xFFF2B33D),
    bad: Color(0xFFF06A6A),
    flag: Color(0xFF8C6BD9),
    flagText: Color(0xFFCBB8F5),
    amberBg: Color(0xFF3A2E17),
    amberText: Color(0xFFF2C66D),
  );

  static const light = NoirColors(
    bg: Color(0xFFF6F7F9),
    side: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF0F2F5),
    line: Color(0xFFE3E6EB),
    line2: Color(0xFFCDD2DA),
    text: Color(0xFF15181D),
    muted: Color(0xFF5B6270),
    accent: Color(0xFF1F6FEB),
    onAccent: Color(0xFFFFFFFF),
    navBg: Color(0xFFE3EDFF),
    navText: Color(0xFF0F3F99),
    good: Color(0xFF1E9E62),
    warn: Color(0xFFC98A0B),
    bad: Color(0xFFD64545),
    flag: Color(0xFF7A55C9),
    flagText: Color(0xFF5B3A8F),
    amberBg: Color(0xFFFFF0C9),
    amberText: Color(0xFF7A5300),
  );

  @override
  NoirColors copyWith({
    Color? bg,
    Color? side,
    Color? surface,
    Color? surface2,
    Color? line,
    Color? line2,
    Color? text,
    Color? muted,
    Color? accent,
    Color? onAccent,
    Color? navBg,
    Color? navText,
    Color? good,
    Color? warn,
    Color? bad,
    Color? flag,
    Color? flagText,
    Color? amberBg,
    Color? amberText,
  }) {
    return NoirColors(
      bg: bg ?? this.bg,
      side: side ?? this.side,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      line: line ?? this.line,
      line2: line2 ?? this.line2,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      navBg: navBg ?? this.navBg,
      navText: navText ?? this.navText,
      good: good ?? this.good,
      warn: warn ?? this.warn,
      bad: bad ?? this.bad,
      flag: flag ?? this.flag,
      flagText: flagText ?? this.flagText,
      amberBg: amberBg ?? this.amberBg,
      amberText: amberText ?? this.amberText,
    );
  }

  /// lerp = ผสมสีระหว่าง 2 ธีม ทำให้ตอนสลับมืด/สว่าง สีค่อย ๆ เปลี่ยน (ไม่กระตุก)
  @override
  NoirColors lerp(ThemeExtension<NoirColors>? other, double t) {
    if (other is! NoirColors) return this;
    return NoirColors(
      bg: Color.lerp(bg, other.bg, t)!,
      side: Color.lerp(side, other.side, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      line: Color.lerp(line, other.line, t)!,
      line2: Color.lerp(line2, other.line2, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      navBg: Color.lerp(navBg, other.navBg, t)!,
      navText: Color.lerp(navText, other.navText, t)!,
      good: Color.lerp(good, other.good, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      bad: Color.lerp(bad, other.bad, t)!,
      flag: Color.lerp(flag, other.flag, t)!,
      flagText: Color.lerp(flagText, other.flagText, t)!,
      amberBg: Color.lerp(amberBg, other.amberBg, t)!,
      amberText: Color.lerp(amberText, other.amberText, t)!,
    );
  }
}

/// ทางลัด: เขียน `context.noir` แทน `Theme.of(context).extension<NoirColors>()!`
extension NoirColorsX on BuildContext {
  NoirColors get noir => Theme.of(this).extension<NoirColors>()!;
}
