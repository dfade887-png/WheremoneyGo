import 'package:flutter/material.dart';

void main() => runApp(const CoreHarnessApp());

/// Temporary shell only. Production UI is intentionally deferred until UX freeze.
class CoreHarnessApp extends StatelessWidget {
  const CoreHarnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Financial Core — no production UI')),
      ),
    );
  }
}
