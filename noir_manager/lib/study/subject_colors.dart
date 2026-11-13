/// สีประจำวิชา: ค่าเริ่มต้นวนตามลำดับ id · เปลี่ยนเองได้ (เก็บในคอลัมน์ subject.color ตั้งแต่ v10)
library;

import 'package:flutter/material.dart';

import '../data/study_models.dart';
import '../data/study_repository.dart';

/// 8 สีที่อ่านตัวหนังสือขาวได้ทั้งโหมดมืดและสว่าง
const List<Color> subjectPalette = [
  Color(0xFF3B6FD9), // น้ำเงิน
  Color(0xFF7A55C7), // ม่วง
  Color(0xFF1F8F86), // เขียวหัวเป็ด
  Color(0xFFC2671E), // ส้ม
  Color(0xFFB8457A), // ชมพูเข้ม
  Color(0xFF4F7D2E), // เขียวมะกอก
  Color(0xFF8A6A1F), // ทองเข้ม
  Color(0xFF5B6475), // เทาฟ้า
];

/// สีตามระดับความสำคัญ (สูง / กลาง / น้อย)
const Map<int, Color> importancePalette = {
  3: Color(0xFFC94A4A),
  2: Color(0xFFE8822E), // ส้ม
  1: Color(0xFF3C8F64),
};

const Map<int, String> importanceNames = {3: 'สำคัญสูง', 2: 'กลาง', 1: 'น้อย'};

/// สีของทุกวิชา: id → สี
Future<Map<int, Color>> loadSubjectColors(StudyRepository repo) async => {
      for (final s in await repo.subjects()) s.id: subjectColorOf(s),
    };

/// สีของวิชาเดียว
Color subjectColorOf(Subject s) => subjectPalette[(s.colorIndex ?? s.id) % subjectPalette.length];

/// สีตัวหนังสือที่อ่านออกบนพื้น [bg]
Color onColor(Color bg) =>
    bg.computeLuminance() > 0.45 ? const Color(0xFF111316) : Colors.white;

/// สีประจำวิชาของทั้งแอป (id → สี) · ปฏิทิน / วันนี้ / ตารางเรียน / แผนผัง ใช้ชุดเดียวกัน
/// โหลดตอนเปิดแอป และหน้าวิชาอัปเดตทุกครั้งที่โหลดใหม่ (เปลี่ยนสี / เพิ่มวิชา)
final subjectColors = ValueNotifier<Map<int, Color>>({});

Future<void> refreshSubjectColors(StudyRepository repo) async {
  subjectColors.value = await loadSubjectColors(repo);
}
