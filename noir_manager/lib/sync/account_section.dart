/// ตั้งค่า › บัญชี (รอบ 16 · preview https://claude.ai/artifact/8aiRTd4W5ipTr5P3jRzGj7)
/// ไม่เข้าระบบ = ใช้ในเครื่องได้ทุกอย่าง · เข้าระบบ = ซิงก์อัตโนมัติ ไม่มีหน้าเลือก
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';
import '../utils/open_link.dart';
import '../widgets/mini_form.dart';
import '../widgets/toast.dart';
import 'cloud_sync.dart';
import 'conflict_text.dart';
import 'duplicate_plan.dart';
import 'merge.dart';
import 'supabase_api.dart' show CloudError;

String _ago(DateTime? t) {
  if (t == null) return '–';
  final m = DateTime.now().difference(t).inMinutes;
  if (m < 1) return 'เมื่อกี้';
  if (m < 60) return '$m นาทีก่อน';
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

String _clock(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class AccountSection extends StatefulWidget {
  const AccountSection({super.key, this.service});

  /// null = ข้อมูลตัวอย่าง / เทส → ปิดใช้
  final CloudSyncService? service;

  @override
  State<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<AccountSection> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  bool _showAll = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _go(bool signUp) async {
    final s = widget.service!;
    if (_email.text.trim().isEmpty || _pass.text.isEmpty) {
      return showToast(context, 'ใส่อีเมลและรหัสผ่านก่อน', kind: ToastKind.warn);
    }
    setState(() => _busy = true);
    try {
      if (signUp) {
        final ok = await s.signUp(_email.text, _pass.text);
        if (!mounted) return;
        showToast(context, ok ? '✓ สมัครแล้ว · เริ่มซิงก์' : '📧 ส่งลิงก์ยืนยันไปที่อีเมลแล้ว · กดลิงก์แล้วกลับมากด "เข้าสู่ระบบ"',
            kind: ok ? ToastKind.success : ToastKind.info);
      } else {
        await s.signIn(_email.text, _pass.text);
        if (!mounted) return;
        showToast(context, '✓ เข้าระบบแล้ว · เริ่มซิงก์', kind: ToastKind.success);
      }
      _pass.clear();
    } on CloudError catch (e) {
      if (mounted) showToast(context, e.message, kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    final s = widget.service!;
    setState(() => _busy = true);
    if (!kIsWeb) showToast(context, 'เปิดหน้า Google ในเบราว์เซอร์แล้ว · เลือกบัญชีแล้วกลับมาที่แอป', kind: ToastKind.info);
    try {
      final ok = await s.signInWithGoogle((url) => openLink(context, url));
      if (!mounted) return;
      if (ok) showToast(context, '✓ เข้าด้วย Google แล้ว · เริ่มซิงก์', kind: ToastKind.success);
      if (!ok && !kIsWeb) showToast(context, 'หมดเวลารอ Google · กดใหม่ได้', kind: ToastKind.warn);
    } on CloudError catch (e) {
      if (mounted) showToast(context, e.message, kind: ToastKind.error);
    } catch (e) {
      if (mounted) showToast(context, 'เข้าด้วย Google ไม่สำเร็จ: $e', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final s = widget.service;
    if (s == null) {
      return Text('ใช้ไม่ได้ในโหมดข้อมูลตัวอย่าง', style: TextStyle(fontSize: 13, color: c.muted));
    }
    return ValueListenableBuilder(
      valueListenable: s.status,
      builder: (context, st, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        st.state == CloudState.signedOut ? _signedOut(c, st) : _signedIn(c, s, st),
        // รอบ 20: งานซ้ำจากการย้ายเครื่อง (โหลดใหม่ทุกครั้งที่ซิงก์เสร็จ)
        if (st.state != CloudState.signedOut) _DuplicateCard(key: ValueKey(st.lastSync), service: s),
      ]),
    );
  }

  Widget _signedOut(NoirColors c, CloudStatus st) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (st.message != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(st.message!, style: TextStyle(fontSize: 12.5, color: c.warn)),
        ),
      TextField(
        key: const Key('cloud-email'),
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(labelText: 'อีเมล', isDense: true),
      ),
      const SizedBox(height: 8),
      TextField(
        key: const Key('cloud-pass'),
        controller: _pass,
        obscureText: _hide,
        onSubmitted: (_) => _go(false),
        decoration: InputDecoration(
          labelText: 'รหัสผ่าน (อย่างน้อย 6 ตัว)',
          isDense: true,
          suffixIcon: IconButton(
            tooltip: _hide ? 'แสดงรหัส' : 'ซ่อนรหัส',
            icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
            onPressed: () => setState(() => _hide = !_hide),
          ),
        ),
      ),
      // รอบ 21: จำเครื่องนี้ (ค่าเริ่ม = จำ · ปิด = เปิดแอปครั้งหน้าต้องเข้าระบบใหม่)
      ValueListenableBuilder(
        valueListenable: widget.service!.remember,
        builder: (context, on, _) => CheckboxListTile(
          key: const Key('cloud-remember'),
          value: on,
          onChanged: (v) => widget.service!.setRemember(v ?? true),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: Text('จำเครื่องนี้ (ไม่ต้องเข้าระบบอีก)', style: TextStyle(fontSize: 14, color: c.text)),
        ),
      ),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            key: const Key('cloud-signup'),
            onPressed: _busy ? null : () => _go(true),
            child: const Text('สมัครใหม่'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            key: const Key('cloud-signin'),
            onPressed: _busy ? null : () => _go(false),
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('เข้าสู่ระบบ'),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: Divider(color: c.line)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('หรือ', style: TextStyle(fontSize: 12, color: c.muted))),
        Expanded(child: Divider(color: c.line)),
      ]),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        key: const Key('cloud-google'),
        onPressed: _busy ? null : _google,
        icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        label: const Text('เข้าด้วย Google'),
      ),
      const SizedBox(height: 8),
      Text('ไม่เข้าระบบก็ใช้ได้ทุกอย่าง (ข้อมูลอยู่ในเครื่อง) · Gmail เดียวกับที่สมัครอีเมล = บัญชีเดียวกัน',
          style: TextStyle(fontSize: 12, color: c.muted)),
    ]);
  }

  Widget _signedIn(NoirColors c, CloudSyncService s, CloudStatus st) {
    final (dot, label) = switch (st.state) {
      CloudState.syncing => (c.accent, 'กำลังซิงก์…'),
      CloudState.ok => (c.good, 'ซิงก์แล้ว'),
      CloudState.offline => (c.warn, 'ไม่มีเน็ต · เก็บไว้ส่งทีหลัง'),
      CloudState.error => (c.bad, 'ซิงก์ไม่สำเร็จ'),
      _ => (c.muted, 'รอซิงก์'),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MiniRow(
        icon: Icons.person_outline,
        label: st.email ?? '',
        trailing: TextButton(
          key: const Key('cloud-signout'),
          onPressed: () async {
            final ok = await confirmMini(context,
                title: 'ออกจากระบบ?',
                message: 'ข้อมูลในเครื่องยังอยู่ครบ · แค่หยุดซิงก์',
                okLabel: 'ออก');
            if (ok) await s.signOut();
          },
          child: const Text('ออก'),
        ),
      ),
      MiniRow(
        iconWidget: Container(width: 10, height: 10, margin: const EdgeInsets.symmetric(horizontal: 5), decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        label: label,
        valueText: _ago(st.lastSync),
        onTap: st.state == CloudState.syncing ? null : s.syncNow,
      ),
      MiniRow(icon: Icons.hourglass_empty, label: 'รอส่ง', valueText: '${st.pending} รายการ'),
      if (st.message != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(st.message!, style: TextStyle(fontSize: 12.5, color: st.state == CloudState.error ? c.bad : c.warn)),
        ),
      if (st.conflicts.isNotEmpty) ...[
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text('⚠ มีข้อมูลที่แก้ไม่ตรงกันระหว่างเครื่อง',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.warn)),
          ),
          TextButton(key: const Key('cloud-conflicts-ok'), onPressed: s.clearConflicts, child: const Text('เข้าใจแล้ว')),
        ]),
        Text('แอปเลือกค่าที่แก้ล่าสุดให้แล้ว · ถ้าอยากได้ค่าของอีกเครื่อง กดปุ่มข้างรายการนั้น',
            style: TextStyle(fontSize: 12, color: c.muted)),
        for (final x in st.conflicts.take(_showAll ? 50 : 5)) _conflict(c, s, x),
        if (st.conflicts.length > 5 && !_showAll)
          TextButton(onPressed: () => setState(() => _showAll = true), child: Text('ดูอีก ${st.conflicts.length - 5} รายการ')),
      ],
      const SizedBox(height: 8),
      Text('แก้ข้อมูล → ส่งเองใน 5 วิ · ดึงของเครื่องอื่นทุก 1 นาที · แตะ "ซิงก์แล้ว" = ซิงก์ตอนนี้',
          style: TextStyle(fontSize: 12, color: c.muted)),
    ]);
  }

  Widget _conflict(NoirColors c, CloudSyncService s, SyncConflict x) {
    final kept = conflictValue(x.field, x.keptLocal ? x.local : x.remote);
    final other = conflictValue(x.field, x.keptLocal ? x.remote : x.local);
    final row = s.mirror.shadowOf(x.table, x.id)?.values;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(conflictTitle(x, row), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
            Text('ตอนนี้ใช้: $kept  (แก้ล่าสุด ${_clock(x.keptLocal ? x.localAt : x.remoteAt)})',
                style: TextStyle(fontSize: 12.5, color: c.text)),
            Text('อีกเครื่องเป็น: $other', style: TextStyle(fontSize: 12.5, color: c.muted)),
          ]),
        ),
        TextButton(onPressed: () => s.useOtherValue(x), child: Text('ใช้ $other')),
      ]),
    );
  }
}

/// การ์ด "งานซ้ำจากการย้ายเครื่อง" · ไม่มีงานซ้ำ = ไม่โชว์อะไร
class _DuplicateCard extends StatefulWidget {
  const _DuplicateCard({super.key, required this.service});
  final CloudSyncService service;

  @override
  State<_DuplicateCard> createState() => _DuplicateCardState();
}

class _DuplicateCardState extends State<_DuplicateCard> {
  List<DuplicateActivity> _dups = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await findDuplicateActivities(widget.service.db);
    if (mounted) setState(() => _dups = d);
  }

  Future<void> _clean() async {
    final n = _dups.fold(0, (a, d) => a + d.removeIds.length);
    final ok = await confirmMini(
      context,
      title: 'ลบงานซ้ำ $n รายการ?',
      message: '${_dups.map((d) => d.name).take(6).join(' · ')}${_dups.length > 6 ? ' …' : ''}\n'
          'เก็บตัวที่มีประวัติ (ติ๊กแล้ว / เลื่อน) ไว้ · ลบเฉพาะตัวที่ยังไม่เคยใช้ · ทุกเครื่องจะหายตาม',
      okLabel: 'ลบตัวซ้ำ',
    );
    if (!ok || !mounted) return;
    final cal = widget.service.cal;
    for (final d in _dups) {
      for (final id in d.removeIds) {
        await cal.deleteActivity(id);
      }
    }
    if (!mounted) return;
    showToast(context, '✓ ลบงานซ้ำ $n รายการแล้ว', kind: ToastKind.success);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final removable = _dups.fold(0, (a, d) => a + d.removeIds.length);
    final manual = _dups.where((d) => d.keepWithHistory.isNotEmpty).toList();
    if (removable == 0 && manual.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('cloud-duplicates'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('⚠ พบงานซ้ำ ${_dups.length} งาน (ขึ้น 2 อันในวันเดียวกัน)',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.warn)),
        const SizedBox(height: 4),
        Text('เกิดจากทั้งเครื่องเก่าและเครื่องใหม่สร้างแผนชุดเดียวกันไว้ แล้วรวมกันตอนเข้าบัญชี',
            style: TextStyle(fontSize: 12, color: c.muted)),
        const SizedBox(height: 6),
        for (final d in _dups.take(8))
          Text('• ${d.name}${d.keepWithHistory.isNotEmpty ? '  (มีประวัติทั้ง 2 อัน · ลบเองในปฏิทิน)' : ''}',
              style: TextStyle(fontSize: 12.5, color: c.text)),
        if (removable > 0)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(key: const Key('cloud-duplicates-clean'), onPressed: _clean, child: Text('ลบตัวซ้ำ $removable รายการ')),
          ),
      ]),
    );
  }
}
