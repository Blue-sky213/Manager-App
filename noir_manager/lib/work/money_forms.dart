/// ฟอร์มการเงิน (MiniForm)
library;

import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/mini_form.dart';
import '../widgets/mini_segments.dart';
import 'money_models.dart';
import 'work_repository.dart';

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '').replaceAll('฿', ''));
String _plain(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

Future<DateTime?> _pickDay(BuildContext context, DateTime initial) => showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

/// จดรายการเงิน · 3 ช่องจบ: จำนวน → หมวด → (วัน / โน้ต / ผูกเงินลงทุน)
Future<int?> editEntryForm(BuildContext context, WorkRepository repo,
    {MoneyEntry? entry, MoneyKind kind = MoneyKind.expense, DateTime? day, int? projectId}) async {
  final invs = await repo.investments();
  if (!context.mounted) return null;
  var k = entry?.kind ?? kind;
  final amount = TextEditingController(text: entry == null ? '' : _plain(entry.amount));
  final note = TextEditingController(text: entry?.note ?? '');
  var cat = entry?.category;
  var when = entry?.day ?? day ?? DateTime.now();
  var inv = entry?.investmentId;
  var showErr = false;
  final ok = await showMiniForm<bool>(
    context,
    (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final c = ctx.noir;
      final cats = k == MoneyKind.income ? incomeCategories : expenseCategories;
      // อ่านค่าตอนกด (ไม่ใช่ตอนวาด) กันค่าค้าง
      bool bad() => (_num(amount.text) ?? 0) <= 0;
      return MiniForm(
        title: entry == null ? 'จดรายการ' : 'แก้รายการ',
        primaryLabel: 'บันทึก',
        onPrimary: () {
          if (bad()) return setLocal(() => showErr = true);
          Navigator.pop(ctx, true);
        },
        onSecondary: () => Navigator.pop(ctx, false),
        children: [
          MiniSegments<MoneyKind>(
            key: const Key('money-kind'),
            value: k,
            items: const [(MoneyKind.expense, 'จ่าย'), (MoneyKind.income, 'รับ')],
            onChanged: (v) => setLocal(() {
              k = v;
              cat = null;
            }),
          ),
          const SizedBox(height: 8),
          MiniBigField(
            key: const Key('money-amount'),
            controller: amount,
            hint: '฿ 0',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setLocal(() {}),
          ),
          if (showErr && bad()) Text('ใส่จำนวนเงิน', style: TextStyle(fontSize: 12, color: c.bad)),
          const MiniLabel('หมวด'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final x in cats)
              ChoiceChip(
                key: ValueKey('money-cat-$x'),
                showCheckmark: false,
                label: Text(x),
                selected: (cat ?? cats.last) == x,
                onSelected: (_) => setLocal(() => cat = x),
              ),
          ]),
          const SizedBox(height: 8),
          MiniRow(
            icon: Icons.event,
            label: 'วันที่',
            valueText: thaiShortDate(when),
            onTap: () async {
              final d = await _pickDay(ctx, when);
              if (d != null) setLocal(() => when = d);
            },
          ),
          if (k == MoneyKind.income && invs.isNotEmpty)
            MiniRow(
              icon: Icons.savings_outlined,
              label: 'ช่วยคืนทุน',
              valueText: invs.where((i) => i.id == inv).firstOrNull?.name ?? 'ไม่ผูก',
              onTap: () async {
                final v = await showMiniChoice<int>(ctx,
                    title: 'ผูกกับเงินลงทุน', current: inv ?? -1, items: [miniChoice(-1, 'ไม่ผูก'), for (final i in invs) miniChoice(i.id, i.name)]);
                if (v != null) setLocal(() => inv = v == -1 ? null : v);
              },
            ),
          MiniRow(
            icon: Icons.notes,
            label: 'โน้ต',
            last: true,
            value: MiniInlineField(controller: note, hint: 'เช่น ค่าน้ำมันไปหน้างาน', width: 200),
          ),
        ],
      );
    }),
  );
  if (ok != true) return null;
  final cats = k == MoneyKind.income ? incomeCategories : expenseCategories;
  return repo.saveEntry(MoneyEntry(
    id: entry?.id ?? 0,
    day: when,
    kind: k,
    amount: _num(amount.text)!,
    category: cats.contains(cat) ? cat! : cats.last,
    note: note.text.trim().isEmpty ? null : note.text.trim(),
    projectId: entry?.projectId ?? projectId,
    investmentId: k == MoneyKind.income ? inv : null,
    subscriptionId: entry?.subscriptionId,
  ));
}

/// เพิ่ม / แก้ค่าบริการ
Future<int?> editSubscriptionForm(BuildContext context, WorkRepository repo, {Subscription? sub}) async {
  final name = TextEditingController(text: sub?.name ?? '');
  final amount = TextEditingController(text: sub?.amount == null ? '' : _plain(sub!.amount!));
  final dayC = TextEditingController(text: '${sub?.billDay ?? 1}');
  var cycle = sub?.cycle ?? BillCycle.monthly;
  var month = sub?.billMonth ?? DateTime.now().month;
  var active = sub?.active ?? true;
  var showErr = false;
  final ok = await showMiniForm<bool>(
    context,
    (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final c = ctx.noir;
      return MiniForm(
        title: sub == null ? 'ค่าบริการใหม่' : 'แก้ค่าบริการ',
        primaryLabel: 'บันทึก',
        onPrimary: () {
          if (name.text.trim().isEmpty) return setLocal(() => showErr = true);
          Navigator.pop(ctx, true);
        },
        onSecondary: () => Navigator.pop(ctx, false),
        children: [
          MiniBigField(key: const Key('sub-name'), controller: name, hint: 'เช่น Adobe'),
          if (showErr && name.text.trim().isEmpty) Text('ใส่ชื่อบริการ', style: TextStyle(fontSize: 12, color: c.bad)),
          MiniSegments<BillCycle>(
            value: cycle,
            items: const [(BillCycle.monthly, 'รายเดือน'), (BillCycle.yearly, 'รายปี')],
            onChanged: (v) => setLocal(() => cycle = v),
          ),
          const SizedBox(height: 8),
          MiniRow(
            icon: Icons.payments_outlined,
            label: 'ยอด (บาท)',
            value: MiniInlineField(
                key: const Key('sub-amount'),
                controller: amount,
                hint: 'ไม่รู้ = เว้นไว้',
                width: 120,
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
          ),
          MiniRow(
            icon: Icons.event_repeat,
            label: 'ตัดเงินวันที่',
            value: MiniInlineField(controller: dayC, hint: '1', width: 60, keyboardType: TextInputType.number),
          ),
          if (cycle == BillCycle.yearly)
            MiniRow(
              icon: Icons.calendar_month,
              label: 'เดือนที่ตัด',
              valueText: thaiMonthsLong[month - 1],
              onTap: () async {
                final v = await showMiniChoice<int>(ctx,
                    title: 'เดือนที่ตัด', current: month, items: [for (var m = 1; m <= 12; m++) miniChoice(m, thaiMonthsLong[m - 1])]);
                if (v != null) setLocal(() => month = v);
              },
            ),
          MiniSwitchRow(
            icon: Icons.check_circle_outline,
            label: 'ยังใช้อยู่',
            detail: 'ปิด = เลิกใช้ (ไม่นับในงบ)',
            value: active,
            last: true,
            onChanged: (v) => setLocal(() => active = v),
          ),
        ],
      );
    }),
  );
  if (ok != true) return null;
  return repo.saveSubscription(Subscription(
    id: sub?.id ?? 0,
    name: name.text.trim(),
    amount: _num(amount.text),
    cycle: cycle,
    billDay: (int.tryParse(dayC.text.trim()) ?? 1).clamp(1, 31),
    billMonth: cycle == BillCycle.yearly ? month : null,
    active: active,
  ));
}

/// ติ๊ก "ตัดเงินแล้ว": ยอดตามที่ตั้ง (ไม่มียอด = ถาม)
Future<bool> payBill(BuildContext context, WorkRepository repo, Subscription s, DateTime month) async {
  var amount = s.amount;
  if (amount == null) {
    final c = TextEditingController();
    final ok = await showMiniForm<bool>(
      context,
      (ctx) => MiniForm(
        title: '${s.name} · ตัดเงินเท่าไร',
        primaryLabel: 'บันทึก',
        onPrimary: () => Navigator.pop(ctx, true),
        onSecondary: () => Navigator.pop(ctx, false),
        children: [
          MiniBigField(
              key: const Key('pay-amount'), controller: c, hint: '฿ 0', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        ],
      ),
    );
    amount = ok == true ? _num(c.text) : null;
    if (amount == null || amount <= 0) return false;
  }
  final now = DateTime.now();
  final day = now.year == month.year && now.month == month.month ? now : DateTime(month.year, month.month, s.billDay.clamp(1, 28));
  await repo.saveEntry(MoneyEntry(day: day, kind: MoneyKind.expense, amount: amount, category: 'ค่าบริการ', note: s.name, subscriptionId: s.id));
  return true;
}

/// เพิ่ม / แก้เงินลงทุน
Future<int?> editInvestmentForm(BuildContext context, WorkRepository repo, {Investment? inv}) async {
  final name = TextEditingController(text: inv?.name ?? '');
  final amount = TextEditingController(text: inv == null ? '' : _plain(inv.amount));
  final note = TextEditingController(text: inv?.note ?? '');
  var start = inv?.startDay ?? DateTime.now();
  var showErr = false;
  final ok = await showMiniForm<bool>(
    context,
    (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final c = ctx.noir;
      bool bad() => name.text.trim().isEmpty || (_num(amount.text) ?? 0) <= 0;
      return MiniForm(
        title: inv == null ? 'เงินลงทุนใหม่' : 'แก้เงินลงทุน',
        primaryLabel: 'บันทึก',
        onPrimary: () {
          if (bad()) return setLocal(() => showErr = true);
          Navigator.pop(ctx, true);
        },
        onSecondary: () => Navigator.pop(ctx, false),
        children: [
          MiniBigField(key: const Key('inv-name'), controller: name, hint: 'เช่น คอมสตรีม', onChanged: (_) => setLocal(() {})),
          MiniRow(
            icon: Icons.savings_outlined,
            label: 'ลงทุน (บาท)',
            value: MiniInlineField(
                key: const Key('inv-amount'),
                controller: amount,
                hint: '0',
                width: 120,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setLocal(() {})),
          ),
          MiniRow(
            icon: Icons.event,
            label: 'เริ่ม',
            valueText: thaiShortDate(start),
            onTap: () async {
              final d = await _pickDay(ctx, start);
              if (d != null) setLocal(() => start = d);
            },
          ),
          MiniRow(icon: Icons.notes, label: 'โน้ต', last: true, value: MiniInlineField(controller: note, width: 200)),
          if (showErr && bad()) Text('ใส่ชื่อและจำนวนเงิน', style: TextStyle(fontSize: 12, color: c.bad)),
          Text('รายรับที่เลือก "ช่วยคืนทุน" = เงินที่คืนแล้ว', style: TextStyle(fontSize: 12, color: c.muted)),
        ],
      );
    }),
  );
  if (ok != true) return null;
  return repo.saveInvestment(Investment(
    id: inv?.id ?? 0,
    name: name.text.trim(),
    amount: _num(amount.text)!,
    startDay: start,
    note: note.text.trim().isEmpty ? null : note.text.trim(),
  ));
}
