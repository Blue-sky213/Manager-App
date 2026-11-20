/// ตั้งค่า › บัญชี (รอบ 16 · preview https://claude.ai/artifact/8aiRTd4W5ipTr5P3jRzGj7)
/// ไม่เข้าระบบ = ใช้ในเครื่องได้ทุกอย่าง · เข้าระบบ = ซิงก์อัตโนมัติ ไม่มีหน้าเลือก
library;

import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';
import '../widgets/mini_form.dart';
import '../widgets/toast.dart';
import 'cloud_sync.dart';
import 'merge.dart';
import 'supabase_api.dart' show CloudError;

String _ago(DateTime? t) {
  if (t == null) return '–';
  final m = DateTime.now().difference(t).inMinutes;
  if (m < 1) return 'เมื่อกี้';
  if (m < 60) return '$m นาทีก่อน';
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

String _show(Object? v) => v == null ? '(ว่าง)' : '$v';

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

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final s = widget.service;
    if (s == null) {
      return Text('ใช้ได้กับข้อมูลจริงบน PC เท่านั้น (ตอนนี้เปิดโหมดข้อมูลตัวอย่าง)', style: TextStyle(fontSize: 13, color: c.muted));
    }
    return ValueListenableBuilder(
      valueListenable: s.status,
      builder: (context, st, _) => st.state == CloudState.signedOut ? _signedOut(c, st) : _signedIn(c, s, st),
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
      const SizedBox(height: 12),
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
      const SizedBox(height: 8),
      Text('ไม่เข้าระบบก็ใช้ได้ทุกอย่าง (ข้อมูลอยู่ในเครื่อง) · เข้าด้วย Google มารอบถัดไป',
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
      if (st.message != null && st.state != CloudState.ok)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(st.message!, style: TextStyle(fontSize: 12.5, color: st.state == CloudState.offline ? c.warn : c.bad)),
        ),
      if (st.conflicts.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('แก้ต่างกันบน 2 เครื่อง (ใช้ค่าล่าสุดแล้ว)', style: TextStyle(fontSize: 12.5, color: c.warn)),
        for (final x in st.conflicts.take(6)) _conflict(c, s, x),
      ],
      const SizedBox(height: 8),
      Text('แก้ข้อมูล → ส่งเองใน 5 วิ · ดึงของเครื่องอื่นทุก 1 นาที · แตะ "ซิงก์แล้ว" = ซิงก์ตอนนี้',
          style: TextStyle(fontSize: 12, color: c.muted)),
    ]);
  }

  Widget _conflict(NoirColors c, CloudSyncService s, SyncConflict x) {
    final kept = x.keptLocal ? x.local : x.remote;
    final other = x.keptLocal ? x.remote : x.local;
    final what = x.field == null ? 'ลบ / แก้' : x.field!;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        Expanded(
          child: Text(
            '${x.table} · $what\nใช้: ${_show(kept)} (${_clock(x.keptLocal ? x.localAt : x.remoteAt)}) · อีกค่า: ${_show(other)}',
            style: TextStyle(fontSize: 12.5, color: c.text),
          ),
        ),
        TextButton(onPressed: () => s.useOtherValue(x), child: const Text('ใช้อีกค่า')),
      ]),
    );
  }
}
