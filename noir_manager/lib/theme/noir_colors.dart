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
    required this.greenBg,
    required this.greenText,
    required this.purpleBg,
    required this.purpleText,
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
  final Color greenBg; // พื้นงานหมวดเขียว (ออกกำลังกาย)
  final Color greenText; // ตัวหนังสือหมวดเขียว
  final Color purpleBg; // พื้นงานหมวดม่วง (สตรีม)
  final Color purpleText; // ตัวหนังสือหมวดม่วง

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
    greenBg: Color(0xFF1D2A22),
    greenText: Color(0xFFBFEBD2),
    purpleBg: Color(0xFF2A2233),
    purpleText: Color(0xFFDCCBF2),
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
    greenBg: Color(0xFFE4F6EC),
    greenText: Color(0xFF1E6B43),
    purpleBg: Color(0xFFF1EAFB),
    purpleText: Color(0xFF5B3A8F),
  );

  /// ธีมพาสเทล = ธีมสว่างที่ย้อมพื้น เมนู และสีเน้นเป็นโทนเดียวกัน (อ่านง่ายเท่าธีมสว่าง)
  static NoirColors pastel({required Color bg, required Color side, required Color nav, required Color accent, required Color navText}) =>
      light.copyWith(
        bg: bg,
        side: side,
        surface2: Color.lerp(light.surface2, nav, 0.35),
        line: Color.lerp(light.line, nav, 0.5),
        accent: accent,
        navBg: nav,
        navText: navText,
      );

  /// พาสเทลโหมดมืด = ธีมมืดที่ย้อมพื้นเป็นโทนเข้มของสีนั้น · สีเน้นเป็นพาสเทลสว่างให้อ่านออก
  static NoirColors pastelDark({
    required Color bg,
    required Color side,
    required Color surface,
    required Color surface2,
    required Color line,
    required Color nav,
    required Color accent,
    required Color navText,
  }) =>
      dark.copyWith(
        bg: bg,
        side: side,
        surface: surface,
        surface2: surface2,
        line: line,
        line2: Color.lerp(line, accent, 0.25),
        accent: accent,
        onAccent: const Color(0xFF14101A),
        navBg: nav,
        navText: navText,
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
    Color? greenBg,
    Color? greenText,
    Color? purpleBg,
    Color? purpleText,
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
      greenBg: greenBg ?? this.greenBg,
      greenText: greenText ?? this.greenText,
      purpleBg: purpleBg ?? this.purpleBg,
      purpleText: purpleText ?? this.purpleText,
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
      greenBg: Color.lerp(greenBg, other.greenBg, t)!,
      greenText: Color.lerp(greenText, other.greenText, t)!,
      purpleBg: Color.lerp(purpleBg, other.purpleBg, t)!,
      purpleText: Color.lerp(purpleText, other.purpleText, t)!,
    );
  }
}

/// ทางลัด: เขียน `context.noir` แทน `Theme.of(context).extension<NoirColors>()!`
extension NoirColorsX on BuildContext {
  NoirColors get noir => Theme.of(this).extension<NoirColors>()!;
}

/// ธีมที่เลือกได้ในหน้าตั้งค่า (id เก็บในตาราง setting key = 'theme')
class ThemeChoice {
  const ThemeChoice(this.id, this.name, this.dark, this.colors);
  final String id;
  final String name;
  final bool dark;
  final NoirColors colors;
}

final List<ThemeChoice> themeChoices = [
  const ThemeChoice('dark', 'มืด', true, NoirColors.dark),
  const ThemeChoice('light', 'สว่าง', false, NoirColors.light),
  ThemeChoice('pink', 'ชมพูพาสเทล', false, NoirColors.pastel(
      bg: const Color(0xFFFDF4F7), side: const Color(0xFFFFFAFC), nav: const Color(0xFFF9DCE7),
      accent: const Color(0xFFD9467D), navText: const Color(0xFF8A2350))),
  ThemeChoice('mint', 'เขียวมิ้นต์', false, NoirColors.pastel(
      bg: const Color(0xFFF2FAF6), side: const Color(0xFFF9FDFB), nav: const Color(0xFFD5F0E2),
      accent: const Color(0xFF1F8F5F), navText: const Color(0xFF145C3D))),
  ThemeChoice('sea', 'น้ำทะเล', false, NoirColors.pastel(
      bg: const Color(0xFFF1F8FB), side: const Color(0xFFF8FCFE), nav: const Color(0xFFD3ECF5),
      accent: const Color(0xFF117FA6), navText: const Color(0xFF0B5370))),
  ThemeChoice('lavender', 'ลาเวนเดอร์', false, NoirColors.pastel(
      bg: const Color(0xFFF6F4FC), side: const Color(0xFFFBFAFE), nav: const Color(0xFFE5DEF8),
      accent: const Color(0xFF6B4FC8), navText: const Color(0xFF452F8F))),
  ThemeChoice('peach', 'พีช', false, NoirColors.pastel(
      bg: const Color(0xFFFDF6F1), side: const Color(0xFFFFFBF8), nav: const Color(0xFFFBE2D2),
      accent: const Color(0xFFC8622A), navText: const Color(0xFF80391A))),
  // ---- พาสเทลโหมดมืด ----
  ThemeChoice('pink-dark', 'ชมพู (มืด)', true, NoirColors.pastelDark(
      bg: const Color(0xFF1A1216), side: const Color(0xFF1F151A), surface: const Color(0xFF241920),
      surface2: const Color(0xFF2E1F28), line: const Color(0xFF3A2833), nav: const Color(0xFF4A2338),
      accent: const Color(0xFFF28DB2), navText: const Color(0xFFFFD9E7))),
  ThemeChoice('mint-dark', 'มิ้นต์ (มืด)', true, NoirColors.pastelDark(
      bg: const Color(0xFF0F1714), side: const Color(0xFF131D19), surface: const Color(0xFF17231E),
      surface2: const Color(0xFF1E2D27), line: const Color(0xFF29392F), nav: const Color(0xFF1F4434),
      accent: const Color(0xFF6FD3A3), navText: const Color(0xFFCFF5E2))),
  ThemeChoice('sea-dark', 'น้ำทะเล (มืด)', true, NoirColors.pastelDark(
      bg: const Color(0xFF0E1519), side: const Color(0xFF121B20), surface: const Color(0xFF162229),
      surface2: const Color(0xFF1C2C34), line: const Color(0xFF26363F), nav: const Color(0xFF1B4152),
      accent: const Color(0xFF6CC6E8), navText: const Color(0xFFD0F0FB))),
  ThemeChoice('lavender-dark', 'ลาเวนเดอร์ (มืด)', true, NoirColors.pastelDark(
      bg: const Color(0xFF141220), side: const Color(0xFF191626), surface: const Color(0xFF1E1A2D),
      surface2: const Color(0xFF262139), line: const Color(0xFF322C46), nav: const Color(0xFF352A5E),
      accent: const Color(0xFFA894F2), navText: const Color(0xFFE6DEFF))),
  ThemeChoice('peach-dark', 'พีช (มืด)', true, NoirColors.pastelDark(
      bg: const Color(0xFF19130F), side: const Color(0xFF1F1813), surface: const Color(0xFF251C16),
      surface2: const Color(0xFF2F241C), line: const Color(0xFF3B2E24), nav: const Color(0xFF4D2F1E),
      accent: const Color(0xFFF2A477), navText: const Color(0xFFFFE2D0))),
];

/// คู่สว่าง ↔ มืด ของธีมเดียวกัน (ปุ่มลัดในเมนูสลับภายในโทนสีเดิม)
String pairedTheme(String id) {
  if (id == 'dark') return 'light';
  if (id == 'light') return 'dark';
  return id.endsWith('-dark') ? id.substring(0, id.length - 5) : '$id-dark';
}

ThemeChoice themeChoiceOf(String? id) => themeChoices.firstWhere((t) => t.id == id, orElse: () => themeChoices.first);
