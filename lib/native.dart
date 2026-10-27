import 'package:flutter/services.dart';

/// Thin wrapper over the Kotlin side (MainActivity.kt).
class Native {
  static const _ch = MethodChannel('ledger/native');

  static Future<Map<String, bool>> permissionStatus() async {
    try {
      final r = await _ch.invokeMapMethod<String, bool>('permissionStatus');
      return r ?? {};
    } catch (_) {
      return {};
    }
  }

  static Future<Map<String, bool>> requestPermissions({bool sms = true}) async {
    try {
      final r = await _ch.invokeMapMethod<String, bool>('requestPermissions', {'sms': sms});
      return r ?? {};
    } catch (_) {
      return {};
    }
  }

  static Future<List<Map<String, dynamic>>> readSms(int sinceMillis, {int? untilMillis}) async {
    final r = await _ch.invokeListMethod<dynamic>('readSms', {
      'since': sinceMillis,
      if (untilMillis != null) 'until': untilMillis,
    });
    return (r ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> notify(int id, String title, String body) async {
    try {
      await _ch.invokeMethod('notify', {'id': id, 'title': title, 'body': body});
    } catch (_) {}
  }

  static Future<void> scheduleReminder(int hour, int minute) async {
    try {
      await _ch.invokeMethod('scheduleReminder', {'hour': hour, 'minute': minute});
    } catch (_) {}
  }

  static Future<void> cancelReminder() async {
    try {
      await _ch.invokeMethod('cancelReminder');
    } catch (_) {}
  }

  static Future<void> setPref(String key, bool value) async {
    try {
      await _ch.invokeMethod('setPref', {'key': key, 'value': value});
    } catch (_) {}
  }
}
