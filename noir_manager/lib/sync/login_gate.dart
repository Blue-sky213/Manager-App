/// หน้าเข้าระบบก่อนใช้แอป (รอบ 21 · ออนไลน์ก่อน แบบ Notion · preview https://claude.ai/artifact/RDV7i9C5y5bz9K8pvn99tk)
/// เข้าครั้งเดียวแล้วจำเครื่อง · ลองดูได้โดยไม่เข้าระบบ (ข้อมูลตัวอย่าง ไม่แตะข้อมูลจริง)
library;

import 'package:flutter/material.dart';

import '../data/demo_year.dart' show demoMode;
import '../theme/noir_colors.dart';
import 'account_section.dart';
import 'cloud_sync.dart';

class LoginGate extends StatelessWidget {
  const LoginGate({super.key, required this.child, this.service});

  final Widget child;

  /// null = ข้อมูลตัวอย่าง / เทส → ไม่มีหน้าเข้าระบบ
  final CloudSyncService? service;

  @override
  Widget build(BuildContext context) {
    final s = service;
    if (s == null) return child;
    return ValueListenableBuilder(
      valueListenable: demoMode,
      builder: (context, demo, _) => demo
          ? child
          : ValueListenableBuilder(
              valueListenable: s.ready,
              builder: (context, ready, _) => !ready
                  ? const Scaffold(body: Center(child: CircularProgressIndicator()))
                  : ValueListenableBuilder(
                      valueListenable: s.status,
                      builder: (context, st, _) => st.state == CloudState.signedOut ? LoginPage(service: s) : child,
                    ),
            ),
    );
  }
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key, required this.service});
  final CloudSyncService service;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('Noir Manager',
                        key: const Key('login-title'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: c.text)),
                    const SizedBox(height: 4),
                    Text('ปฏิทิน · การเรียน · สกิล · งานและเงิน',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.muted)),
                    const SizedBox(height: 6),
                    Text('เข้าระบบครั้งเดียว ใช้ได้ทุกเครื่อง ข้อมูลตรงกันทันที',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.muted)),
                    const SizedBox(height: 20),
                    AccountSection(service: service),
                    const SizedBox(height: 12),
                    TextButton(
                      key: const Key('login-demo'),
                      onPressed: () => demoMode.value = true,
                      child: const Text('ลองดูโดยไม่เข้าระบบ (ข้อมูลตัวอย่าง)'),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
