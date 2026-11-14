/// แผ่นดูอย่างเดียว (รอบ 8 · A): คอม = การ์ดเล็กลอยข้างจุดที่คลิก · มือถือ = แผ่นล่างเหมือนเดิม (นิ้วโป้งเอื้อมถึง)
library;

import 'package:flutter/material.dart';

import '../shell/app_nav.dart' show lastPointerDown;
import '../theme/noir_colors.dart';

/// จอกว้างเท่านี้ขึ้นไป = การ์ดลอย
const infoCardBreakpoint = 700.0;

Future<void> showInfoCard(BuildContext context, {required WidgetBuilder builder, Offset? at, double width = 340}) {
  final screen = MediaQuery.sizeOf(context);
  if (screen.width < infoCardBreakpoint) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 20), child: builder(ctx)),
      ),
    );
  }
  final p = at ?? lastPointerDown;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'ปิด',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, _, _) {
      final c = ctx.noir;
      const gap = 12.0;
      final maxH = screen.height * 0.7;
      // ขวาของเมาส์ถ้าพอ ไม่งั้นซ้าย · ไม่ล้นขอบจอ
      final left = p.dx + gap + width < screen.width - 8 ? p.dx + gap : (p.dx - gap - width).clamp(8.0, screen.width - width - 8);
      final top = (p.dy - 24).clamp(8.0, screen.height - 120);
      return Stack(children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Material(
              key: const Key('info-card'),
              color: c.surface2,
              elevation: 10,
              shadowColor: Colors.black54,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.line)),
              child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: builder(ctx)),
            ),
          ),
        ),
      ]);
    },
    transitionBuilder: (ctx, a, _, child) => FadeTransition(opacity: a, child: child),
  );
}
