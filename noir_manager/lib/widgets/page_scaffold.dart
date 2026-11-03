import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';

/// โครงหน้าที่ทุกเมนูใช้ร่วมกัน: หัวข้อเล็ก + หัวข้อใหญ่ + เนื้อหา (เลื่อนได้)
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.overline,
    required this.title,
    required this.children,
  });

  final String overline; // ข้อความเล็กด้านบน (สีจาง)
  final String title; // หัวข้อใหญ่
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      children: [
        Text(overline, style: TextStyle(fontSize: 13, color: c.muted)),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: c.text,
          ),
        ),
        const SizedBox(height: 20),
        ...children,
      ],
    );
  }
}

/// การ์ดบอกว่า "ฟีเจอร์นี้กำลังจะมา" ใช้ชั่วคราวจนกว่าจะสร้างหน้าจริง
class ComingSoonCard extends StatelessWidget {
  const ComingSoonCard({
    super.key,
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, color: c.muted),
            const SizedBox(width: 16),
            Expanded(
              child: Text(message, style: TextStyle(color: c.muted)),
            ),
          ],
        ),
      ),
    );
  }
}
