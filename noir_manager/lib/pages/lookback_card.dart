import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../calendar/calendar_models.dart';
import '../calendar/calendar_ui.dart' show CategoryIcon;
import '../calendar/lookback.dart';
import '../theme/noir_colors.dart';

/// การ์ด "สถิติย้อนหลัง · พลาดเพราะอะไร" (รอบ 7 · O)
class LookbackCard extends StatelessWidget {
  const LookbackCard({super.key, required this.lookback, required this.categories});

  final Lookback lookback;
  final Map<int, ActivityCategory> categories;

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final folder = Directory(p.join(dir.path, 'NoirManager'));
      await folder.create(recursive: true);
      final file = File(p.join(folder.path, 'lookback_${dayKey(now)}.csv'));
      // BOM = Excel อ่านภาษาไทยถูก
      await file.writeAsString('﻿${lookbackCsv(lookback)}');
      messenger.showSnackBar(SnackBar(content: Text('ส่งออกแล้ว · ${file.path}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('ส่งออกไม่ได้: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final lb = lookback;
    final rate = lb.onTimeRate;
    Widget bars(String title, List<(String, int, int)> rows) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: TextStyle(fontSize: 12, color: c.muted)),
            const SizedBox(height: 6),
            for (final (name, ok, n) in rows) ...[
              Row(children: [
                Expanded(child: Text(name, style: TextStyle(fontSize: 13, color: c.text))),
                Text(n == 0 ? '—' : '${(ok * 100 / n).round()}% · $n วัน', style: TextStyle(fontSize: 12, color: c.muted)),
              ]),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: n == 0 ? 0 : ok / n,
                  minHeight: 8,
                  backgroundColor: c.surface2,
                  color: n == 0 ? c.surface2 : (ok / n >= 0.85 ? c.good : (ok / n >= 0.6 ? const Color(0xFFE8822E) : c.bad)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
    final topCats = (lb.missedByCat.entries.toList()..sort((a, b) => b.value - a.value)).take(4).toList();
    return Card(
      key: const Key('lookback-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('สถิติย้อนหลัง · พลาดเพราะอะไร', style: TextStyle(fontWeight: FontWeight.w600, color: c.text))),
            TextButton.icon(
              key: const Key('lookback-export'),
              onPressed: lb.logs.isEmpty ? null : () => _export(context),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('ส่งออก CSV'),
            ),
          ]),
          if (lb.total == 0)
            Text('ยังไม่มีงานสำคัญ (●●●) ที่ผ่านไปแล้วในช่วงนี้', style: TextStyle(fontSize: 13, color: c.muted))
          else ...[
            Text(
              'งานสำคัญ ${lb.total} งาน · ตรงเวลา ${lb.onTime} · เสร็จย้อนหลัง ${lb.late} · พลาด ${lb.missed}'
              '${rate == null ? '' : ' · ${rate.round()}% ตรงเวลา'}',
              style: TextStyle(fontSize: 13, color: c.text),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 16, runSpacing: 12, children: [
              SizedBox(width: 260, child: bars('ชั่วโมงนอนคืนก่อน → วันนั้นทำครบทันเวลา', lb.sleep)),
              SizedBox(width: 260, child: bars('พลังตอนเช้า (เช็กอิน) → ทำครบทันเวลา', lb.energy)),
              if (topCats.isNotEmpty)
                SizedBox(
                  width: 220,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('พลาดบ่อยสุด', style: TextStyle(fontSize: 12, color: c.muted)),
                    const SizedBox(height: 6),
                    for (final e in topCats)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          CategoryIcon(categories[e.key], size: 22),
                          const SizedBox(width: 8),
                          Expanded(child: Text(categories[e.key]?.name ?? 'ไม่มีหมวด', style: TextStyle(color: c.text))),
                          Text('${e.value} ครั้ง', style: TextStyle(fontSize: 12, color: c.muted)),
                        ]),
                      ),
                  ]),
                ),
            ]),
            if (lb.insights.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (final t in lb.insights)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('💡 $t', style: TextStyle(fontSize: 13, color: c.text)),
                ),
            ] else
              Text('ข้อสังเกตจะขึ้นเมื่อมีข้อมูลพอ (อย่างน้อย 3 วันต่อกลุ่ม) · เช็กอินตอนเช้าในหน้าวันนี้',
                  style: TextStyle(fontSize: 12, color: c.muted)),
          ],
        ]),
      ),
    );
  }
}
