/// งาน › เข้างาน (รอบ 22 · หน้าตัวอย่างอนุมัติ 24 พ.ย.)
/// กดปุ่มเดียว เข้างาน / เลิกงาน → แยกชั่วโมงปกติ / OT + คิดค่าจ้างให้เอง · ตั้งค่าไว้ให้พร้อมใช้
/// คอม: 2 ฝั่ง (เช็คอิน | ค่าจ้าง + รายวัน) · รายวันเป็นบล็อกเลื่อนในตัว (ลูกกลิ้ง / ลากนิ้ว)
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../calendar/calendar_repository.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/dialogs.dart';
import '../widgets/mini_form.dart';
import '../widgets/mini_segments.dart';
import '../widgets/toast.dart';
import 'money_models.dart';
import 'pay_calc.dart';
import 'work_repository.dart';

const _wd = ['จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'];

enum _Sub { today, month, settings }

class CheckinView extends StatefulWidget {
  const CheckinView({super.key, this.clock});

  /// เวลาตอนนี้ (เทสส่งเวลาตายตัว)
  final DateTime Function()? clock;

  @override
  State<CheckinView> createState() => _CheckinViewState();
}

class _CheckinViewState extends State<CheckinView> {
  WorkRepository? _repo;
  PayConfig _cfg = const PayConfig();
  List<WorkSession> _sessions = const [];
  Map<DateTime, AbsenceKind> _abs = const {};
  late DateTime _month;
  _Sub _sub = _Sub.today;
  bool _loaded = false;
  Timer? _tick;

  DateTime get _now => widget.clock?.call() ?? DateTime.now();
  DateTime get _today => dateOf(_now);
  int get _nowMin => _now.hour * 60 + _now.minute;

  @override
  void initState() {
    super.initState();
    _month = DateTime(_now.year, _now.month);
    // นาฬิกาเดินทุก 30 วิ (ตัวเลขชั่วโมงที่ทำอยู่ขยับตาม)
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = CalendarScope.of(context).workRepo;
    if (r != _repo) {
      _repo?.removeListener(_load);
      _repo = r..addListener(_load);
      _load();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _repo?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final r = _repo!;
    // ดึงเผื่อเดือนก่อน: รอบที่ลืมกดเลิกตั้งแต่เมื่อวาน (ข้ามเดือน)
    final from = DateTime(_month.year, _month.month - 1, 25);
    final to = DateTime(_month.year, _month.month + 1, 0);
    final cfg = await r.payConfig();
    final ss = await r.workSessions(from, to);
    final ab = await r.absences(from, to);
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _sessions = ss;
      _abs = ab;
      _loaded = true;
    });
  }

  MonthResult _calc() => calcMonth(_cfg, _month.year, _month.month, _sessions, _abs,
      today: _month.year == _today.year && _month.month == _today.month ? _today : DateTime(_month.year, _month.month + 1, 0),
      nowMin: _nowMin);

  /// รอบที่ยังไม่กดเลิก (วันนี้ หรือลืมกดตั้งแต่วันก่อน)
  WorkSession? get _open {
    for (final s in _sessions.reversed) {
      if (s.open && !dateOf(s.day).isAfter(_today)) return s;
    }
    return null;
  }

  List<WorkSession> _on(DateTime d) => [for (final s in _sessions) if (isSameDate(s.day, d)) s];

  // ---------------- การกระทำ ----------------

  Future<void> _checkIn() async {
    final t = _today;
    DateTime? comp;
    if (!_cfg.workDays.contains(t.weekday) && _cfg.timed) {
      final m = calcMonth(_cfg, t.year, t.month, _sessions, _abs, today: t, nowMin: _nowMin);
      final cands = [...m.absent, ...m.unresolved]..sort();
      final pick = await showMiniChoice<Object>(context, title: 'วันนี้วันหยุด · นับเป็นอะไร?', items: [
        for (final d in cands.reversed.take(4))
          miniChoice<Object>(d, 'ทำแทนวันที่ขาด · ${thaiShortDate(d)}', detail: 'สลับวันหยุด: 8 ชม. แรกแทนวันนั้น (ไม่หัก) · เกินจากนั้น = OT ×${_cfg.otRate}'),
        miniChoice<Object>('hol', 'ทำงานวันหยุด', detail: 'คิดอัตราวันหยุด'),
      ]);
      if (pick == null) return;
      if (pick is DateTime) {
        comp = pick;
        if (_abs[pick] == null) await _repo!.setAbsence(pick, AbsenceKind.absent);
      }
    }
    await _repo!.saveWorkSession(WorkSession(day: t, startMin: _nowMin, compFor: comp));
    if (mounted) showToast(context, 'เข้างาน ${clock(_nowMin)}${comp != null ? ' · แทนวันที่ ${comp.day}' : ''}', kind: ToastKind.success);
  }

  Future<void> _checkOut(WorkSession s) async {
    final end = _nowMin + _today.difference(dateOf(s.day)).inDays * 1440;
    int? pcs;
    if (_cfg.type == PayType.piece) {
      final t = await askText(context, title: 'วันนี้ทำได้กี่ชิ้น', label: 'จำนวนชิ้น', confirmLabel: 'บันทึก');
      pcs = int.tryParse(t ?? '');
    }
    await _repo!.saveWorkSession(s.copyWith(endMin: end, pieces: pcs));
    if (!mounted) return;
    final done = calcDay(_cfg, s.day, [..._on(s.day).where((x) => x.id != s.id), s.copyWith(endMin: end)]);
    showToast(context, 'เลิกงาน ${clock(end)} · ทำ ${hrsText(done.worked)}', kind: ToastKind.success);
  }

  Future<int?> _pickTime(String help, int initial) async {
    final t = await showTimePicker(
      context: context,
      helpText: help,
      initialTime: TimeOfDay(hour: (initial ~/ 60) % 24, minute: initial % 60),
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  /// แตะแถววัน: แก้เวลา / เพิ่มย้อนหลัง / บอกว่าวันนั้นเป็นอะไร
  Future<void> _editDay(DateTime d) async {
    final ss = _on(d);
    final items = <MiniChoice<String>>[
      for (final s in ss) ...[
        miniChoice('in:${s.id}', 'แก้เวลาเข้า ${clock(s.startMin)}'),
        if (!s.open) miniChoice('out:${s.id}', 'แก้เวลาเลิก ${clock(s.endMin!)}'),
        miniChoice('del:${s.id}', 'ลบรอบ ${clock(s.startMin)} – ${s.open ? '…' : clock(s.endMin!)}'),
      ],
      miniChoice('add', ss.isEmpty ? 'เพิ่มเวลาทำงาน (ลืมกด)' : 'เพิ่มอีกรอบ'),
      if (ss.isEmpty && _cfg.workDays.contains(d.weekday)) ...[
        for (final k in AbsenceKind.values) miniChoice('abs:${k.name}', absenceLabel[k]!),
        if (_abs[d] != null) miniChoice('abs:clear', 'ล้าง (ยังไม่ระบุ)'),
      ],
    ];
    final pick = await showMiniChoice<String>(context, title: thaiShortDate(d), items: items);
    if (pick == null) return;
    if (!mounted) return;
    final r = _repo!;
    final [what, arg] = pick.contains(':') ? pick.split(':') : [pick, ''];
    WorkSession byId() => ss.firstWhere((s) => '${s.id}' == arg);
    switch (what) {
      case 'in':
        final s = byId();
        final v = await _pickTime('เวลาเข้างาน', s.startMin);
        if (v != null) await r.saveWorkSession(s.copyWith(startMin: v));
      case 'out':
        final s = byId();
        final v = await _pickTime('เวลาเลิกงาน', s.endMin!);
        if (v != null) await r.saveWorkSession(s.copyWith(endMin: v < s.startMin ? v + 1440 : v));
      case 'del':
        if (await confirmDelete(context, 'รอบทำงานนี้')) await r.deleteWorkSession(byId().id);
      case 'add':
        final a = await _pickTime('เวลาเข้างาน', 8 * 60);
        if (a == null) return;
        final b = await _pickTime('เวลาเลิกงาน', a + 9 * 60);
        if (b == null) return;
        await r.saveWorkSession(WorkSession(day: d, startMin: a, endMin: b < a ? b + 1440 : b));
        if (_abs[d] != null) await r.setAbsence(d, null);
      case 'abs':
        await r.setAbsence(d, arg == 'clear' ? null : AbsenceKind.values.byName(arg));
    }
  }

  Future<void> _saveCfg(PayConfig c) => _repo!.savePayConfig(c);

  Future<void> _editAmount(String title, double current, PayConfig Function(double v) apply) async {
    final t = await askText(context, title: title, label: 'บาท', initial: money2(current).replaceAll(',', ''), confirmLabel: 'บันทึก');
    final v = double.tryParse((t ?? '').replaceAll(',', ''));
    if (v != null && v >= 0) await _saveCfg(apply(v));
  }

  Future<void> _addExtra(bool plus) async {
    final name = await askText(context,
        title: plus ? 'เพิ่มเงินเพิ่ม' : 'เพิ่มเงินหัก', label: 'ชื่อ', hint: plus ? 'เช่น เบี้ยขยัน' : 'เช่น ประกันสังคม');
    if (name == null) return;
    if (!mounted) return;
    final t = await askText(context, title: name, label: 'บาทต่อเดือน', confirmLabel: 'บันทึก');
    final v = double.tryParse((t ?? '').replaceAll(',', ''));
    if (v == null || v <= 0) return;
    await _saveCfg(_cfg.copyWith(extras: [..._cfg.extras, PayExtra(name, plus ? v : -v)]));
  }

  Future<void> _saveIncome(MonthResult m) async {
    final r = _repo!;
    final payDay = DateTime(_month.year, _month.month + 1, _cfg.payDay.clamp(1, 28));
    final note = 'ค่าจ้าง ${thaiMonthYear(_month)}';
    final same = (await r.entries(payDay, payDay)).where((e) => e.note == note).toList();
    await r.saveEntry(MoneyEntry(
      id: same.isEmpty ? 0 : same.first.id,
      day: payDay,
      kind: MoneyKind.income,
      amount: (m.pay * 100).round() / 100,
      category: 'เงินเดือน',
      note: note,
    ));
    if (mounted) showToast(context, 'บันทึกรายรับ ${money2(m.pay)} บาท · วันที่ ${payDay.day} ${thaiMonthsShort[payDay.month - 1]}');
  }

  // ---------------- หน้าจอ ----------------

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final m = _calc();
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 900;
      final subs = wide
          ? const [(_Sub.today, 'วันนี้'), (_Sub.settings, 'ตั้งค่า')]
          : const [(_Sub.today, 'วันนี้'), (_Sub.month, 'เดือนนี้'), (_Sub.settings, 'ตั้งค่า')];
      final sub = wide && _sub == _Sub.month ? _Sub.today : _sub;
      final pad = wide ? 20.0 : 12.0;
      Widget body;
      if (sub == _Sub.settings) {
        body = SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 4, pad, 24),
          child: Align(alignment: Alignment.topLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620), child: _settings())),
        );
      } else if (wide && box.maxHeight >= 600) {
        body = Padding(
          padding: EdgeInsets.fromLTRB(pad, 4, pad, pad),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_checkCard(m), ..._unresolved(m)]),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _payCard(m),
                const SizedBox(height: 14),
                Expanded(child: _listCard(m, scroll: true)),
              ]),
            ),
          ]),
        );
      } else {
        final kids = sub == _Sub.month || wide
            ? [_payCard(m), const SizedBox(height: 12), _listCard(m, scroll: false)]
            : [_checkCard(m), ..._unresolved(m), const SizedBox(height: 12), _payCard(m)];
        if (wide) kids.insertAll(0, [_checkCard(m), ..._unresolved(m), const SizedBox(height: 12)]);
        body = ListView(key: const Key('checkin-scroll'), padding: EdgeInsets.fromLTRB(pad, 4, pad, 24), children: kids);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 8, pad, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: wide ? 260 : double.infinity,
              child: MiniSegments<_Sub>(key: const Key('checkin-sub'), value: sub, items: subs, onChanged: (v) => setState(() => _sub = v)),
            ),
          ),
        ),
        Expanded(child: body),
      ]);
    });
  }

  BoxDecoration _box(NoirColors c, {Color? bg}) =>
      BoxDecoration(color: bg ?? c.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line));

  Widget _checkCard(MonthResult m) {
    final c = context.noir;
    final t = _today;
    final open = _open;
    final holiday = !_cfg.workDays.contains(t.weekday);
    final todaySessions = _on(t);
    final d = calcDay(_cfg, t, todaySessions, nowMin: _nowMin);
    final stale = open != null && !isSameDate(open.day, t);
    String state;
    if (open != null) {
      state = stale
          ? 'ยังไม่ได้กดเลิกงานของ ${thaiShortDate(open.day)}'
          : 'กำลังทำงาน · ${open.compFor != null ? 'แทนวันที่ ${open.compFor!.day} ${thaiMonthsShort[open.compFor!.month - 1]}' : holiday ? 'วันหยุด' : 'วันทำงาน'}';
    } else if (todaySessions.isNotEmpty) {
      state = 'เลิกงานแล้ว · ทำ ${hrsText(d.worked)}';
    } else {
      state = holiday ? 'วันหยุด · ถ้าทำงาน กดเข้างานได้เลย' : 'ยังไม่ได้เข้างาน';
    }
    final big = open != null
        ? FilledButton(
            key: const Key('checkin-out'),
            style: FilledButton.styleFrom(
                backgroundColor: c.bad, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(64), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () => _checkOut(open),
            child: const Text('เลิกงาน', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          )
        : FilledButton(
            key: const Key('checkin-in'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: _checkIn,
            child: Text(todaySessions.isEmpty ? 'เข้างาน' : 'เข้างานอีกรอบ', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          );
    final info = <Widget>[];
    if (_cfg.timed && (todaySessions.isNotEmpty)) {
      final parts = <String>[
        if (d.normal > 0) 'ปกติ ${hrsText(d.normal)}',
        if (d.holN > 0) 'วันหยุด ${hrsText(d.holN)}',
        if (d.ot > 0) 'OT ${hrsText(d.ot)}',
        if (d.holOT > 0) 'OT วันหยุด ${hrsText(d.holOT)}',
        if (d.breakMin > 0) 'พัก ${hrsText(d.breakMin)}',
      ];
      if (parts.isNotEmpty) info.add(Text(parts.join(' · '), textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.muted)));
    }
    if (open != null && !stale && _cfg.timed && !(holiday && open.compFor == null) && d.normal < _cfg.normalMin) {
      final bank = _cfg.type == PayType.monthly ? m.bank : 0;
      final extra = bank < 0 ? -bank : 0;
      info.add(Text.rich(
        key: const Key('checkin-finish'),
        TextSpan(children: [
          TextSpan(text: 'ครบ ${hrsText(_cfg.normalMin)} · เลิกได้ '),
          TextSpan(text: clock(finishAt(_cfg, todaySessions.first.startMin)), style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
          if (extra > 0) ...[
            const TextSpan(text: '\nชั่วโมงติดลบ '),
            TextSpan(text: hrsText(extra), style: TextStyle(fontWeight: FontWeight.w700, color: c.bad)),
            const TextSpan(text: ' · อยู่ถึง '),
            TextSpan(text: clock(finishAt(_cfg, todaySessions.first.startMin, extraMin: extra)), style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
            const TextSpan(text: ' เพื่อชดเชย'),
          ],
        ]),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: c.muted),
      ));
    }
    if (_cfg.type == PayType.monthly && _cfg.timed && m.bank > 0 && open != null) {
      info.add(Text('ชั่วโมงสะสมเดือนนี้ +${hrsText(m.bank)} · เลิกก่อนครบจะหักจากตรงนี้ก่อน',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.good)));
    }
    return Container(
      key: const Key('checkin-card'),
      padding: const EdgeInsets.all(18),
      decoration: _box(c),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${thaiShortDate(t)} ${buddhistYear(t)}${holiday ? ' · วันหยุด' : ''}', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.muted)),
        const SizedBox(height: 4),
        Text(clock(_nowMin),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 48, height: 1.1, fontWeight: FontWeight.w700, color: c.text, fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(height: 6),
        Text(state, key: const Key('checkin-state'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: open != null ? c.good : c.muted)),
        const SizedBox(height: 14),
        big,
        if (todaySessions.isNotEmpty || stale) ...[
          const SizedBox(height: 10),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 6, children: [
            for (final s in [if (stale) open!, ...todaySessions])
              ActionChip(
                label: Text('${clock(s.startMin)} – ${s.open ? '…' : clock(s.endMin!)}'),
                avatar: const Icon(Icons.edit_outlined, size: 16),
                onPressed: () => _editDay(dateOf(s.day)),
              ),
          ]),
        ],
        for (final w in info) Padding(padding: const EdgeInsets.only(top: 8), child: w),
      ]),
    );
  }

  List<Widget> _unresolved(MonthResult m) {
    if (m.unresolved.isEmpty) return const [];
    final c = context.noir;
    return [
      const SizedBox(height: 12),
      Container(
        key: const Key('checkin-unresolved'),
        padding: const EdgeInsets.all(14),
        decoration: _box(c, bg: c.amberBg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('วันทำงานที่ไม่มีเช็คอิน · เลือกว่าเป็นอะไร', style: TextStyle(fontWeight: FontWeight.w600, color: c.amberText)),
          for (final d in m.unresolved.reversed.take(5)) ...[
            const SizedBox(height: 10),
            Text(thaiShortDate(d), style: TextStyle(fontSize: 13, color: c.text)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in AbsenceKind.values)
                OutlinedButton(
                  key: Key('abs-${d.day}-${k.name}'),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => _repo!.setAbsence(d, k),
                  child: Text(k == AbsenceKind.absent && _cfg.type == PayType.monthly ? 'ขาดงาน (−${money2(_cfg.dayRate)})' : absenceLabel[k]!),
                ),
              TextButton(onPressed: () => _editDay(d), child: const Text('ลืมกด · ใส่เวลา')),
            ]),
          ],
          if (m.unresolved.length > 5)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('และอีก ${m.unresolved.length - 5} วัน (ดูในรายวัน)', style: TextStyle(fontSize: 12, color: c.muted))),
        ]),
      ),
    ];
  }

  Widget _payCard(MonthResult m) {
    final c = context.noir;
    final cfg = _cfg;
    Widget ln(String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(k, style: TextStyle(fontSize: 14, color: c.text))),
            Text(v, style: TextStyle(fontSize: 14, color: color ?? c.text, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        );
    final lines = <Widget>[];
    String note;
    switch (cfg.type) {
      case PayType.monthly:
        lines.add(ln('เงินเดือน', money2(cfg.monthly)));
        if (m.absent.isNotEmpty) lines.add(ln('ขาดงาน ${m.absent.length} วัน', '−${money2(m.absent.length * cfg.dayRate)}', color: c.bad));
        if (m.compensated.isNotEmpty) lines.add(ln('ขาดงาน ${m.compensated.length} วัน (ทำวันหยุดแทนแล้ว)', '0.00', color: c.muted));
        if (m.ot > 0 || m.shortDed > 0) {
          lines.add(ln('OT ${hrsText(m.ot)} − ชั่วโมงที่ขาด ${hrsText(m.shortDed)}', m.bank >= 0 ? '= +${hrsText(m.bank)}' : '= −${hrsText(-m.bank)}', color: c.muted));
          lines.add(m.bank >= 0
              ? ln('OT ที่ได้เงิน ×${cfg.otRate}', '+${money2(m.bank / 60 * cfg.otHour)}', color: c.good)
              : ln('ชั่วโมงที่ยังขาด', '−${money2(-m.bank / 60 * cfg.hourRate)}', color: c.bad));
        }
        note = 'นับช่วงละ ${cfg.roundMin} นาที · OT ชดเชยชั่วโมงที่ขาดก่อน แล้วค่อยจ่ายส่วนที่เหลือ';
      case PayType.daily || PayType.hourly:
        lines.add(ln('ชั่วโมงปกติ ${hrsText(m.normal)} × ${money2(cfg.hourRate)}', money2(m.normal / 60 * cfg.hourRate)));
        if (m.ot > 0) lines.add(ln('OT ${hrsText(m.ot)} ×${cfg.otRate}', '+${money2(m.ot / 60 * cfg.otHour)}', color: c.good));
        note = '${payTypeLabel[cfg.type]}: ได้ตามที่ทำจริง · ทำวันหยุด ×2';
      case PayType.piece:
        lines.add(ln('${m.pieces} ชิ้น × ${money2(cfg.piece)}', money2(m.pieces * cfg.piece)));
        lines.add(ln('เวลาที่ใช้', hrsText(m.worked), color: c.muted));
        note = 'ใส่จำนวนชิ้นตอนกดเลิกงาน';
      case PayType.project:
        lines.add(ln('รายได้ดูที่บอร์ดโปรเจกต์', '—', color: c.muted));
        lines.add(ln('เวลาที่ใช้', hrsText(m.worked), color: c.muted));
        note = 'เช็คอินไว้นับชั่วโมงที่ใช้กับงาน';
    }
    if (m.holN > 0) lines.add(ln('ทำงานวันหยุด ${hrsText(m.holN)}', '+${money2(m.holN / 60 * cfg.holHour)}', color: c.good));
    if (m.holOT > 0) lines.add(ln('OT วันหยุด ${hrsText(m.holOT)}', '+${money2(m.holOT / 60 * cfg.holOtHour)}', color: c.good));
    for (final e in cfg.extras) {
      lines.add(ln(e.name, '${e.amount >= 0 ? '+' : '−'}${money2(e.amount.abs())}', color: e.amount >= 0 ? c.good : c.bad));
    }
    final payDay = DateTime(_month.year, _month.month + 1, cfg.payDay.clamp(1, 28));
    final current = _month.year == _today.year && _month.month == _today.month;
    return Container(
      key: const Key('checkin-pay'),
      padding: const EdgeInsets.all(16),
      decoration: _box(c),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('ค่าจ้าง ${thaiMonthsShort[_month.month - 1]}${current ? ' (ถึงวันนี้)' : ''} · ${payTypeLabel[cfg.type]}',
                style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
          ),
          Text('จ่าย ${payDay.day} ${thaiMonthsShort[payDay.month - 1]}', style: TextStyle(fontSize: 12, color: c.muted)),
        ]),
        const SizedBox(height: 4),
        Text('${money2(m.pay)} บาท',
            key: const Key('checkin-pay-total'),
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: c.text, fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(height: 6),
        ...lines,
        const SizedBox(height: 8),
        Text(note, style: TextStyle(fontSize: 12, color: c.muted)),
        if (cfg.type != PayType.project)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('checkin-save-income'),
              onPressed: () => _saveIncome(m),
              icon: const Icon(Icons.savings_outlined, size: 18),
              label: const Text('บันทึกเป็นรายรับ'),
            ),
          ),
      ]),
    );
  }

  Widget _listCard(MonthResult m, {required bool scroll}) {
    final c = context.noir;
    final days = m.days.keys.toList()..sort((a, b) => b.compareTo(a));
    Widget row(DateTime d) {
      final r = m.days[d]!;
      final ss = _on(d);
      final ab = _abs[d];
      final chips = <(String, Color, Color)>[];
      if (r.live) chips.add(('กำลังทำ', c.greenBg, c.greenText));
      if (r.swap) chips.add(('แทนวันที่ ${ss.firstWhere((s) => s.compFor != null).compFor!.day}', c.navBg, c.navText));
      if (r.ot > 0) chips.add(('OT ${hrsText(r.ot)}', c.purpleBg, c.purpleText));
      if (r.holOT > 0) chips.add(('OT วันหยุด ${hrsText(r.holOT)}', c.purpleBg, c.purpleText));
      if (_cfg.type == PayType.monthly && r.shortDed > 0) chips.add(('ขาด ${hrsText(r.shortDed)}', c.amberBg, c.bad));
      if (r.pieces > 0) chips.add(('${r.pieces} ชิ้น', c.navBg, c.navText));
      String times;
      if (ss.isNotEmpty) {
        times = ss.map((s) => '${clock(s.startMin)} – ${s.open ? '…' : clock(s.endMin!)}').join(', ');
      } else if (ab != null) {
        times = absenceLabel[ab]!;
        chips.add((m.compensated.contains(d) ? 'ทำแทนแล้ว' : absenceLabel[ab]!, ab == AbsenceKind.absent ? c.amberBg : c.navBg, ab == AbsenceKind.absent ? c.bad : c.navText));
      } else if (m.unresolved.contains(d)) {
        times = 'ไม่มีเช็คอิน';
        chips.add(('ยังไม่ระบุ', c.amberBg, c.amberText));
      } else {
        times = _cfg.workDays.contains(d.weekday) ? '—' : 'วันหยุด';
      }
      return InkWell(
        key: Key('checkin-day-${d.day}'),
        onTap: () => _editDay(d),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
          child: Row(children: [
            SizedBox(
              width: 44,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${d.day}', style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                Text(_wd[d.weekday - 1], style: TextStyle(fontSize: 12, color: c.muted)),
              ]),
            ),
            Expanded(child: Text(times, maxLines: 2, style: TextStyle(fontSize: 13, color: c.muted))),
            const SizedBox(width: 8),
            Flexible(
              child: Wrap(alignment: WrapAlignment.end, spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (ss.isNotEmpty) Text(hrsText(r.worked), style: TextStyle(fontSize: 14, color: c.text)),
                for (final (t, bg, fg) in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
                    child: Text(t, style: TextStyle(fontSize: 11, color: fg)),
                  ),
              ]),
            ),
          ]),
        ),
      );
    }

    final header = Row(children: [
      IconButton(
        key: const Key('checkin-prev-month'),
        tooltip: 'เดือนก่อน',
        icon: const Icon(Icons.chevron_left),
        onPressed: () {
          setState(() => _month = DateTime(_month.year, _month.month - 1));
          _load();
        },
      ),
      Expanded(child: Text(thaiMonthYear(_month), textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, color: c.text))),
      IconButton(
        key: const Key('checkin-next-month'),
        tooltip: 'เดือนถัดไป',
        icon: const Icon(Icons.chevron_right),
        onPressed: !_month.isBefore(DateTime(_today.year, _today.month))
            ? null
            : () {
                setState(() => _month = DateTime(_month.year, _month.month + 1));
                _load();
              },
      ),
    ]);
    return Container(
      key: const Key('checkin-list'),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: _box(c),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: scroll ? MainAxisSize.max : MainAxisSize.min, children: [
        header,
        if (scroll)
          // บล็อกเลื่อนในตัว: ชี้เมาส์แล้วหมุนลูกกลิ้ง / ลากนิ้ว · ส่วนอื่นอยู่กับที่ (นัวร์ขอ 24 พ.ย.)
          Expanded(child: Scrollbar(child: ListView.builder(primary: false, itemCount: days.length, itemBuilder: (_, i) => row(days[i]))))
        else
          for (final d in days) row(d),
      ]),
    );
  }

  Widget _settings() {
    final c = context.noir;
    final cfg = _cfg;
    Widget r(String k, String v, {VoidCallback? onTap, Key? key}) => InkWell(
          key: key,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
            child: Row(children: [
              Expanded(child: Text(k, style: TextStyle(fontSize: 14, color: c.text))),
              Text(v, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
              if (onTap != null) Icon(Icons.chevron_right, size: 18, color: c.muted),
            ]),
          ),
        );
    final rows = <Widget>[
      switch (cfg.type) {
        PayType.monthly => r('เงินเดือน', '${money2(cfg.monthly)} บาท',
            key: const Key('pay-amount'), onTap: () => _editAmount('เงินเดือน', cfg.monthly, (v) => cfg.copyWith(monthly: v))),
        PayType.daily => r('ค่าแรงต่อวัน', '${money2(cfg.daily)} บาท',
            key: const Key('pay-amount'), onTap: () => _editAmount('ค่าแรงต่อวัน', cfg.daily, (v) => cfg.copyWith(daily: v))),
        PayType.hourly => r('ค่าแรงต่อชั่วโมง', '${money2(cfg.hourly)} บาท',
            key: const Key('pay-amount'), onTap: () => _editAmount('ค่าแรงต่อชั่วโมง', cfg.hourly, (v) => cfg.copyWith(hourly: v))),
        PayType.piece => r('ราคาต่อชิ้น', '${money2(cfg.piece)} บาท',
            key: const Key('pay-amount'), onTap: () => _editAmount('ราคาต่อชิ้น', cfg.piece, (v) => cfg.copyWith(piece: v))),
        PayType.project => r('รายได้', 'มาจากบอร์ดโปรเจกต์'),
      },
      if (cfg.timed) ...[
        r('ค่าแรงต่อวัน / ชม.', '${money2(cfg.dayRate)} / ${money2(cfg.hourRate)}'),
        r('ชั่วโมงปกติต่อวัน', '${hrsText(cfg.normalMin)} · พัก ${hrsText(cfg.breakMin)} อัตโนมัติ'),
        r('OT', '×${cfg.otRate} = ${money2(cfg.otHour)} บาท/ชม.'),
        r('นับเวลา', 'ช่วงละ ${cfg.roundMin} นาที (ปัดลง)'),
        if (cfg.type == PayType.monthly) ...[
          r('ขาดงานทั้งวัน', 'หัก ${money2(cfg.dayRate)}'),
          r('ทำไม่ครบ', 'หักจาก OT ก่อน · ไม่พอค่อยหักเงิน'),
        ],
        r('ทำวันหยุดแทนวันที่ขาด', 'สลับวันหยุด = วันธรรมดา'),
        r('ทำงานวันหยุดเพิ่ม', '×${cfg.type == PayType.monthly ? 1 : 2} · OT ×${cfg.holOtRate}'),
      ],
      r('วันจ่าย', 'วันที่ ${cfg.payDay} ของเดือนถัดไป'),
    ];
    return Container(
      key: const Key('checkin-settings'),
      padding: const EdgeInsets.all(16),
      decoration: _box(c),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('รูปแบบค่าจ้าง', style: TextStyle(fontSize: 12, color: c.muted)),
        const SizedBox(height: 6),
        MiniSegments<PayType>(
          key: const Key('pay-type'),
          value: cfg.type,
          items: [for (final t in PayType.values) (t, payTypeLabel[t]!)],
          onChanged: (t) => _saveCfg(cfg.copyWith(type: t)),
        ),
        const SizedBox(height: 8),
        ...rows,
        const SizedBox(height: 14),
        Text('วันทำงาน', style: TextStyle(fontSize: 12, color: c.muted)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var w = 1; w <= 7; w++)
            FilterChip(
              key: Key('workday-$w'),
              label: Text(_wd[w - 1]),
              selected: cfg.workDays.contains(w),
              onSelected: (on) => _saveCfg(cfg.copyWith(workDays: on ? {...cfg.workDays, w} : ({...cfg.workDays}..remove(w)))),
            ),
        ]),
        const SizedBox(height: 14),
        Text('เงินเพิ่ม / เงินหัก (ทุกเดือน)', style: TextStyle(fontSize: 12, color: c.muted)),
        for (var i = 0; i < cfg.extras.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
            child: Row(children: [
              Expanded(child: Text(cfg.extras[i].name, style: TextStyle(color: c.text))),
              Text('${cfg.extras[i].amount >= 0 ? '+' : '−'}${money2(cfg.extras[i].amount.abs())}',
                  style: TextStyle(color: cfg.extras[i].amount >= 0 ? c.good : c.bad)),
              IconButton(
                tooltip: 'ลบ',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _saveCfg(cfg.copyWith(extras: [...cfg.extras]..removeAt(i))),
              ),
            ]),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(key: const Key('extra-plus'), onPressed: () => _addExtra(true), icon: const Icon(Icons.add, size: 18), label: const Text('เงินเพิ่ม')),
          OutlinedButton.icon(key: const Key('extra-minus'), onPressed: () => _addExtra(false), icon: const Icon(Icons.remove, size: 18), label: const Text('เงินหัก')),
        ]),
        const SizedBox(height: 10),
        Text('อัตรา OT และวันหยุดตั้งตามขั้นต่ำของกฎหมายแรงงาน · ที่ทำงานให้มากกว่านี้ได้', style: TextStyle(fontSize: 12, color: c.muted)),
      ]),
    );
  }
}
