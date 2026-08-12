package com.pondz.ngoen_ku_pai_nai

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        BankNotificationPlugin.register(applicationContext, flutterEngine)
    }
}
