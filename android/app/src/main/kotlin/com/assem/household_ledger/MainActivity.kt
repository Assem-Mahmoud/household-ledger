package com.assem.household_ledger

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridge between the Flutter UI and Android:
 * permissions, reading the SMS inbox, notifications and the daily reminder.
 */
class MainActivity : FlutterActivity() {

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ledger/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "permissionStatus" -> result.success(status())

                    "requestPermissions" -> {
                        val wantSms = call.argument<Boolean>("sms") ?: true
                        val missing = mutableListOf<String>()
                        if (wantSms) {
                            if (!has(Manifest.permission.READ_SMS)) missing.add(Manifest.permission.READ_SMS)
                            if (!has(Manifest.permission.RECEIVE_SMS)) missing.add(Manifest.permission.RECEIVE_SMS)
                        }
                        if (Build.VERSION.SDK_INT >= 33 && !has(POST_NOTIFICATIONS)) {
                            missing.add(POST_NOTIFICATIONS)
                        }
                        if (Build.VERSION.SDK_INT >= 23 && missing.isNotEmpty()) {
                            pendingPermissionResult?.success(status())
                            pendingPermissionResult = result
                            requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST)
                        } else {
                            result.success(status())
                        }
                    }

                    "readSms" -> {
                        val since = (call.argument<Number>("since") ?: 0).toLong()
                        val until = (call.argument<Number>("until") ?: Long.MAX_VALUE).toLong()
                        Thread {
                            try {
                                val list = readInbox(since, until)
                                runOnUiThread { result.success(list) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("sms_read_failed", e.message, null) }
                            }
                        }.start()
                    }

                    "notify" -> {
                        Notifier.show(
                            this,
                            call.argument<Int>("id") ?: 1,
                            call.argument<String>("title") ?: "",
                            call.argument<String>("body") ?: ""
                        )
                        result.success(null)
                    }

                    "scheduleReminder" -> {
                        Reminder.save(
                            this,
                            call.argument<Int>("hour") ?: 21,
                            call.argument<Int>("minute") ?: 0,
                            true
                        )
                        Reminder.schedule(this)
                        result.success(null)
                    }

                    "cancelReminder" -> {
                        Reminder.disable(this)
                        result.success(null)
                    }

                    "setPref" -> {
                        val key = call.argument<String>("key") ?: ""
                        val value = call.argument<Boolean>("value") ?: false
                        getSharedPreferences(Reminder.PREFS, Context.MODE_PRIVATE)
                            .edit().putBoolean(key, value).apply()
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun has(permission: String): Boolean {
        if (Build.VERSION.SDK_INT < 23) return true
        return checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun status(): Map<String, Boolean> = mapOf(
        "sms" to (has(Manifest.permission.READ_SMS) && has(Manifest.permission.RECEIVE_SMS)),
        "notifications" to (Build.VERSION.SDK_INT < 33 || has(POST_NOTIFICATIONS))
    )

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST) {
            pendingPermissionResult?.success(status())
            pendingPermissionResult = null
        }
    }

    private fun readInbox(since: Long, until: Long): List<Map<String, Any>> {
        val out = ArrayList<Map<String, Any>>()
        if (!has(Manifest.permission.READ_SMS)) return out
        val cursor = contentResolver.query(
            Uri.parse("content://sms/inbox"),
            arrayOf("_id", "address", "body", "date"),
            "date > ? AND date <= ?",
            arrayOf(since.toString(), until.toString()),
            "date DESC"
        ) ?: return out
        cursor.use {
            while (it.moveToNext() && out.size < 5000) {
                out.add(
                    mapOf(
                        "id" to it.getLong(0).toString(),
                        "address" to (it.getString(1) ?: ""),
                        "body" to (it.getString(2) ?: ""),
                        "date" to it.getLong(3)
                    )
                )
            }
        }
        return out
    }

    companion object {
        private const val PERMISSION_REQUEST = 4711
        const val POST_NOTIFICATIONS = "android.permission.POST_NOTIFICATIONS"
    }
}
