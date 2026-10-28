package com.assem.household_ledger

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import java.io.File
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
    private var pendingPickResult: MethodChannel.Result? = null

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

                    "setLang" -> {
                        getSharedPreferences(Reminder.PREFS, Context.MODE_PRIVATE)
                            .edit().putString("lang", call.argument<String>("lang") ?: "en").apply()
                        result.success(null)
                    }

                    "setPref" -> {
                        val key = call.argument<String>("key") ?: ""
                        val edit = getSharedPreferences(Reminder.PREFS, Context.MODE_PRIVATE).edit()
                        when (val value = call.argument<Any>("value")) {
                            is Boolean -> edit.putBoolean(key, value)
                            else -> edit.putString(key, value?.toString() ?: "")
                        }
                        edit.apply()
                        result.success(null)
                    }

                    "emailFile" -> {
                        try {
                            result.success(
                                emailFile(
                                    call.argument<String>("content") ?: "",
                                    call.argument<String>("fileName") ?: "backup.json",
                                    call.argument<String>("to") ?: "",
                                    call.argument<String>("subject") ?: "",
                                    call.argument<String>("body") ?: ""
                                )
                            )
                        } catch (e: Exception) {
                            result.error("email_failed", e.message, null)
                        }
                    }

                    "pickFile" -> {
                        pendingPickResult?.success(null)
                        pendingPickResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }
                        try {
                            startActivityForResult(intent, PICK_REQUEST)
                        } catch (e: ActivityNotFoundException) {
                            pendingPickResult = null
                            result.error("no_picker", "No file picker available", null)
                        }
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

    /** Writes the file privately and opens Gmail (or any mail app) with it attached. Returns the app used. */
    private fun emailFile(content: String, fileName: String, to: String, subject: String, body: String): String {
        val safeName = fileName.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val dir = BackupProvider.dir(this)
        dir.listFiles()?.forEach { if (it.name != safeName) it.delete() }
        File(dir, safeName).writeText(content, Charsets.UTF_8)
        val uri = BackupProvider.uriFor(safeName)

        val send = Intent(Intent.ACTION_SEND).apply {
            type = if (safeName.endsWith(".csv")) "text/csv" else "application/json"
            if (to.isNotBlank()) putExtra(Intent.EXTRA_EMAIL, arrayOf(to.trim()))
            putExtra(Intent.EXTRA_SUBJECT, subject)
            putExtra(Intent.EXTRA_TEXT, body)
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri(safeName, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val gmail = Intent(send).setPackage("com.google.android.gm")
        return try {
            startActivity(gmail)
            "gmail"
        } catch (e: ActivityNotFoundException) {
            startActivity(Intent.createChooser(send, "Send backup").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
            "chooser"
        }
    }

    @Deprecated("Uses the platform activity-result API, which FlutterActivity still forwards")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_REQUEST) return
        val callback = pendingPickResult ?: return
        pendingPickResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            callback.success(null)
            return
        }
        Thread {
            try {
                val text = contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) }
                runOnUiThread { callback.success(text) }
            } catch (e: Exception) {
                runOnUiThread { callback.error("read_failed", e.message, null) }
            }
        }.start()
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
        private const val PICK_REQUEST = 4712
        const val POST_NOTIFICATIONS = "android.permission.POST_NOTIFICATIONS"
    }
}
