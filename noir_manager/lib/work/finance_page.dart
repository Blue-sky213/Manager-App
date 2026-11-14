/// การเงิน (รอบ 8D): สรุปเดือน · ค่าบริการรายเดือน (ติ๊กตัดเงินแล้ว + งบ) · เงินลงทุน → คืนทุน · รายการ · 6 เดือน · ส่งออก CSV
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../calendar/calendar_repository.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/dialogs.dart';
import '../widgets/mini_form.dart';
import '../widgets/toast.dart';
import 'money_calc.dart';
import 'money_forms.dart';
import 'money_models.dart';
import 'work_repository.dart';

class FinancePage extends StatefulWidget {
  const FinancePage({super.key});

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  CalendarRepository? _cal;
  WorkRepository? _repo;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<MoneyEntry> _all = const []; // 12 เดือนล่าสุด (สรุป + คืนทุน + กราฟ)
  List<Subscription> _subs = const [];
  List<Investment> _invs = const [];
  double? _budget;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cal = CalendarScope.of(context);
    if (cal != _cal) {
      _repo?.removeListener(_load);
      _cal = cal;
      _repo = cal.workRepo..addListener(_load);
      _load();
    }
  }

  @override
  void dispose() {
    _repo?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final repo = _repo!;
    final m = _month;
    final from = DateTime(m.year - 1, m.month + 1, 1);
    final to = DateTime(m.year, m.month + 1, 0);
    // เงินลงทุนคิดจากรายรับทั้งหมด (ไม่ใช่แค่ 12 เดือน)
    final all = await repo.entries(DateTime(2000), DateTime(2100));
    final subs = await repo.subscriptions();
    final invs = await repo.investments();
    final budget = double.tryParse(await _cal!.getSetting(subBudgetKey) ?? '');
    if (!mounted) return;
    setState(() {
      _all = [for (final e in all) if (!e.day.isBefore(from) && !e.day.isAfter(to) || e.investmentId != null) e];
      _subs = subs;
      _invs = invs;
      _budget = budget;
    });
  }

  void _shift(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
    _load();
  }

  Future<void> _export() async {
    final rows = [for (final e in _all) if (e.day.year == _month.year && e.day.month == _month.month) e];
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(dir.path, 'NoirManager'));
      await folder.create(recursive: true);
      final file = File(p.join(folder.path, 'money_${_month.year}-${_month.month.toString().padLeft(2, '0')}.csv'));
      await file.writeAsString('﻿${moneyCsv(rows)}'); // BOM = Excel อ่านไทยถูก
      if (mounted) showToast(context, 'ส่งออกแล้ว · ${file.path}');
    } catch (e) {
      if (mounted) showToast(context, 'ส่งออกไม่ได้: $e');
    }
  }

  Future<void> _editBudget() async {
    final c = TextEditingController(text: _budget == null ? '' : _budget!.round().toString());
    final ok = await showMiniForm<bool>(
      context,
      (ctx) => MiniForm(
        title: 'งบค่าบริการต่อเดือน',
        primaryLabel: 'บันทึก',
        onPrimary: () => Navigator.pop(ctx, true),
        onSecondary: () => Navigator.pop(ctx, false),
        children: [
          MiniBigField(key: const Key('budget'), controller: c, hint: '฿ 1000', keyboardType: TextInputType.number),
        ],
      ),
    );
    if (ok != true) return;
    await _cal!.setSetting(subBudgetKey, c.text.trim());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final repo = _repo!;
    final sum = monthSummary(_all, _month);
    final monthRows = [for (final e in _all) if (e.day.year == _month.year && e.day.month == _month.month) e];
    final today = DateTime.now();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 24, 32), children: [
      Row(children: [
        IconButton(tooltip: 'เดือนก่อน', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
        Text(thaiMonthYear(_month), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.text)),
        IconButton(tooltip: 'เดือนถัดไป', onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
        const Spacer(),
        IconButton(tooltip: 'ส่งออก CSV', onPressed: _export, icon: const Icon(Icons.file_download_outlined)),
        FilledButton.icon(
          key: const Key('money-add'),
          onPressed: () => editEntryForm(context, repo, day: _month.month == today.month && _month.year == today.year ? today : _month),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('จดรายการ'),
        ),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 12, children: [
        _kpi(c, 'รายรับ', baht(sum.income), c.good, key: 'kpi-in'),
        _kpi(c, 'รายจ่าย', baht(sum.expense), c.bad, key: 'kpi-out'),
        _kpi(c, 'คงเหลือ', baht(sum.net), sum.net >= 0 ? c.text : c.bad, key: 'kpi-net'),
      ]),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, box) {
        final two = box.maxWidth >= 760;
        final subs = _subsCard(context, c, repo, today);
        final invs = _invCard(context, c, repo, today);
        return two
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: subs),
                const SizedBox(width: 12),
                Expanded(child: invs),
              ])
            : Column(children: [subs, const SizedBox(height: 12), invs]);
      }),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('6 เดือนล่าสุด', style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
            const SizedBox(height: 8),
            SizedBox(height: 120, child: CustomPaint(painter: _Bars(lastMonths(_all, _month), c.good, c.bad, c.muted))),
            if (sum.byCategory.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('จ่ายมากสุด: ${sum.byCategory.take(3).map((e) => '${e.$1} ${baht(e.$2)}').join(' · ')}',
                  style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Text('รายการเดือนนี้', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
      const SizedBox(height: 4),
      if (monthRows.isEmpty) Text('ยังไม่มี · กด "จดรายการ"', style: TextStyle(fontSize: 12, color: c.muted)),
      for (final e in monthRows) _entryRow(context, c, repo, e),
    ]);
  }

  Widget _kpi(NoirColors c, String k, String v, Color color, {required String key}) => Container(
        width: 200,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: TextStyle(fontSize: 12, color: c.muted)),
          Text(v, key: Key(key), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
        ]),
      );

  Widget _subsCard(BuildContext context, NoirColors c, WorkRepository repo, DateTime today) {
    final active = _subs.where((s) => s.active).toList();
    final perMonth = subscriptionsPerMonth(_subs);
    final over = _budget != null && perMonth > _budget!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('ค่าบริการ', style: TextStyle(fontWeight: FontWeight.w600, color: c.text))),
            ActionChip(
              key: const Key('budget-chip'),
              label: Text(_budget == null ? 'ตั้งงบ' : 'ใช้ ${baht(perMonth)} / ${baht(_budget!)}'),
              labelStyle: TextStyle(fontSize: 12, color: over ? c.warn : c.muted),
              onPressed: _editBudget,
            ),
            IconButton(
                key: const Key('sub-add'),
                tooltip: 'เพิ่มค่าบริการ',
                onPressed: () => editSubscriptionForm(context, repo),
                icon: const Icon(Icons.add)),
          ]),
          if (_budget != null && _budget! > 0) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (perMonth / _budget!).clamp(0, 1).toDouble(),
                minHeight: 6,
                backgroundColor: c.surface2,
                color: over ? c.warn : c.good,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text('ติ๊ก = ตัดเงินแล้วเดือนนี้ (ลงรายจ่ายให้) · ยอดเปลี่ยน = ส้ม · ใกล้ตัด 3 วัน = เตือน',
              style: TextStyle(fontSize: 11, color: c.muted)),
          if (_subs.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('ยังไม่มี · เช่น Adobe · บริการ AI · โดเมน', style: TextStyle(fontSize: 12, color: c.muted)),
            ),
          for (final s in [...active, ..._subs.where((s) => !s.active)]) _subRow(context, c, repo, s, today),
        ]),
      ),
    );
  }

  Widget _subRow(BuildContext context, NoirColors c, WorkRepository repo, Subscription s, DateTime today) {
    final (state, paid) = billState(s, _all, _month, today);
    final (text, color) = switch (state) {
      BillState.paid => ('ตัดแล้ว', c.good),
      BillState.changed => ('ยอดเปลี่ยน ${baht(paid!.amount)}', c.warn),
      BillState.overdue => ('เลยวันตัด', c.bad),
      BillState.dueSoon => ('ใกล้ตัด', c.warn),
      BillState.later => ('ตัดวันที่ ${s.billDay}', c.muted),
      BillState.notThisMonth => ('รายปี · ${thaiMonthsShort[(s.billMonth ?? 1) - 1]}', c.muted),
    };
    final done = paid != null;
    Future<void> menu(Offset at) async {
      final v = await showContextMenuAt<String>(context, at, [
        ctxItem('edit', Icons.edit_outlined, 'แก้ไข'),
        ctxItem('delete', Icons.delete_outline, 'ลบ', danger: true),
      ]);
      if (v == 'edit' && context.mounted) await editSubscriptionForm(context, repo, sub: s);
      if (v == 'delete') await repo.deleteSubscription(s.id);
    }

    return GestureDetector(
      onSecondaryTapUp: (e) => menu(e.globalPosition),
      onLongPressStart: (e) => menu(e.globalPosition),
      child: Opacity(
        opacity: s.active ? 1 : 0.45,
        child: Row(children: [
          Checkbox(
            key: ValueKey('sub-paid-${s.id}'),
            value: done,
            onChanged: !s.active || state == BillState.notThisMonth && !done
                ? null
                : (v) async {
                    if (v == true) {
                      await payBill(context, repo, s, _month);
                    } else if (paid != null) {
                      await repo.deleteEntry(paid.id);
                    }
                  },
          ),
          Expanded(child: Text(s.name, style: TextStyle(color: c.text))),
          Text(text, style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: Text(s.amount == null ? '—' : baht(s.amount!), textAlign: TextAlign.right, style: TextStyle(color: c.text)),
          ),
        ]),
      ),
    );
  }

  Widget _invCard(BuildContext context, NoirColors c, WorkRepository repo, DateTime today) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('เงินลงทุน → คืนทุน', style: TextStyle(fontWeight: FontWeight.w600, color: c.text))),
              IconButton(
                  key: const Key('inv-add'),
                  tooltip: 'เพิ่มเงินลงทุน',
                  onPressed: () => editInvestmentForm(context, repo),
                  icon: const Icon(Icons.add)),
            ]),
            if (_invs.isEmpty)
              Text('เช่น คอมสตรีม · อุปกรณ์ · ทุนโปรเจกต์ · รายรับที่ติ๊ก "ช่วยคืนทุน" จะนับคืนให้',
                  style: TextStyle(fontSize: 12, color: c.muted)),
            for (final inv in _invs)
              () {
                final pb = paybackOf(inv, _all, today);
                Future<void> menu(Offset at) async {
                  final v = await showContextMenuAt<String>(context, at, [
                    ctxItem('edit', Icons.edit_outlined, 'แก้ไข'),
                    ctxItem('delete', Icons.delete_outline, 'ลบ', danger: true),
                  ]);
                  if (v == 'edit' && context.mounted) await editInvestmentForm(context, repo, inv: inv);
                  if (v == 'delete') await repo.deleteInvestment(inv.id);
                }

                return GestureDetector(
                  key: ValueKey('inv-${inv.id}'),
                  onSecondaryTapUp: (e) => menu(e.globalPosition),
                  onLongPressStart: (e) => menu(e.globalPosition),
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(child: Text(inv.name, style: TextStyle(fontWeight: FontWeight.w600, color: c.text))),
                        Text('ลงทุน ${baht(inv.amount)}', style: TextStyle(fontSize: 12, color: c.muted)),
                      ]),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: pb.ratio, minHeight: 6, backgroundColor: c.surface, color: c.accent),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pb.ratio >= 1
                            ? 'คืนทุนแล้ว 🎉'
                            : 'คืนแล้ว ${baht(pb.returned)} (${(pb.ratio * 100).round()}%)'
                                '${pb.eta == null ? '' : ' · ตามอัตราตอนนี้ ≈ ${thaiMonthYear(pb.eta!)}'}',
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                    ]),
                  ),
                );
              }(),
          ]),
        ),
      );

  Widget _entryRow(BuildContext context, NoirColors c, WorkRepository repo, MoneyEntry e) {
    Future<void> menu(Offset at) async {
      final v = await showContextMenuAt<String>(context, at, [
        ctxItem('edit', Icons.edit_outlined, 'แก้ไข'),
        ctxItem('delete', Icons.delete_outline, 'ลบ', danger: true),
      ]);
      if (v == 'edit' && context.mounted) await editEntryForm(context, repo, entry: e);
      if (v == 'delete') await repo.deleteEntry(e.id);
    }

    final inc = e.kind == MoneyKind.income;
    return GestureDetector(
      onSecondaryTapUp: (x) => menu(x.globalPosition),
      onLongPressStart: (x) => menu(x.globalPosition),
      child: InkWell(
        key: ValueKey('money-${e.id}'),
        onTap: () => editEntryForm(context, repo, entry: e),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
          child: Row(children: [
            SizedBox(width: 70, child: Text(thaiShortDate(e.day), style: TextStyle(fontSize: 12, color: c.muted))),
            Expanded(
              child: Text('${e.category}${e.note == null ? '' : ' · ${e.note}'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.text)),
            ),
            Text('${inc ? '+' : '-'}${baht(e.amount)}', style: TextStyle(fontWeight: FontWeight.w600, color: inc ? c.good : c.bad)),
          ]),
        ),
      ),
    );
  }
}

/// แท่งรายรับ (เขียว) / รายจ่าย (แดง) 6 เดือน
class _Bars extends CustomPainter {
  _Bars(this.data, this.inc, this.exp, this.label);
  final List<(DateTime, double, double)> data;
  final Color inc, exp, label;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = data.fold(1.0, (m, d) => [m, d.$2, d.$3].reduce((a, b) => a > b ? a : b));
    final h = size.height - 18;
    final slot = size.width / data.length;
    final bw = (slot * 0.28).clamp(4.0, 22.0);
    for (final (i, d) in data.indexed) {
      final x = slot * i + slot / 2;
      final hi = h * d.$2 / maxV, he = h * d.$3 / maxV;
      final r = Radius.circular(bw / 3);
      canvas.drawRRect(RRect.fromLTRBAndCorners(x - bw - 1, h - hi, x - 1, h, topLeft: r, topRight: r), Paint()..color = inc);
      canvas.drawRRect(RRect.fromLTRBAndCorners(x + 1, h - he, x + bw + 1, h, topLeft: r, topRight: r), Paint()..color = exp);
      final tp = TextPainter(
        text: TextSpan(text: thaiMonthsShort[d.$1.month - 1], style: TextStyle(fontSize: 10, color: label)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, h + 4));
    }
  }

  @override
  bool shouldRepaint(_Bars old) => old.data != data;
}
