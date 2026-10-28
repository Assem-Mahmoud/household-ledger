package com.assem.household_ledger

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import java.util.Calendar

/** Daily end-of-day reminder, re-armed for the next day each time it fires. */
object Reminder {
    const val PREFS = "ledger"

    /** True when the app is set to Arabic (falls back to the phone language). */
    fun arabic(ctx: Context): Boolean {
        val l = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("lang", null)
        return (l ?: java.util.Locale.getDefault().language) == "ar"
    }

    fun save(ctx: Context, hour: Int, minute: Int, on: Boolean) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putInt("remH", hour).putInt("remM", minute).putBoolean("remOn", on).apply()
    }

    fun disable(ctx: Context) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("remOn", false).apply()
        alarmManager(ctx).cancel(pendingIntent(ctx))
    }

    private fun alarmManager(ctx: Context) = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    private fun pendingIntent(ctx: Context): PendingIntent {
        val flags = if (Build.VERSION.SDK_INT >= 23)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else PendingIntent.FLAG_UPDATE_CURRENT
        return PendingIntent.getBroadcast(ctx, 77, Intent(ctx, ReminderReceiver::class.java), flags)
    }

    fun schedule(ctx: Context) {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("remOn", false)) return
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, prefs.getInt("remH", 21))
            set(Calendar.MINUTE, prefs.getInt("remM", 0))
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis() + 1000) add(Calendar.DAY_OF_YEAR, 1)
        }
        val am = alarmManager(ctx)
        val pi = pendingIntent(ctx)
        am.cancel(pi)
        if (Build.VERSION.SDK_INT >= 23) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.timeInMillis, pi)
        } else {
            am.set(AlarmManager.RTC_WAKEUP, cal.timeInMillis, pi)
        }
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val ar = Reminder.arabic(ctx)
        Notifier.show(
            ctx, 1001,
            if (ar) "سجّل مصروفات اليوم" else "Log today's spending",
            if (ar) "أضف أي مصروفات نقدية وأكّد العمليات البنكية لهذا اليوم."
            else "Add any cash spending and confirm today's bank transactions."
        )
        Reminder.schedule(ctx)
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) Reminder.schedule(ctx)
    }
}

/** Shows a notification when a bank-looking SMS arrives. Parsing happens in the app. */
class SmsReceiver : BroadcastReceiver() {
    private val currency = Regex("((?<![A-Za-z])(SAR|SR)(?![A-Za-z])|ر\\.?\\s?س|ريال)", RegexOption.IGNORE_CASE)
    private val amount = Regex("[0-9٠-٩][0-9٠-٩,.]*")
    private val ignore = listOf(
        "otp", "verification", "one time", "رمز", "كلمة المرور", "password",
        // promotions and notices mention riyals too
        "up to ", "يصل إلى", "يصل الى", "offer", "عرض", "limited time", "لفترة محدودة", "will be deducted",
        "سيتم خصم", "due date", "is due", "reminder", "تذكير", "declined", "مرفوض", "hold of", "points"
    )
    private val transaction = listOf(
        "purchase", "شراء", "pos", "mada", "مدى", "payment", "سداد", "paid", "دفع", "withdraw", "سحب",
        "transfer", "حوالة", "تحويل", "debit", "credit", "خصم", "إيداع", "ايداع", "deposit", "salary", "راتب",
        "refund", "استرداد", "card", "بطاقة", "atm", "صراف", "amount", "مبلغ", "received", "sent"
    )

    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val prefs = ctx.getSharedPreferences(Reminder.PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("smsAlerts", true)) return

        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (parts.isEmpty()) return
        val body = parts.joinToString("") { it.messageBody ?: "" }
        val lower = body.lowercase()
        if (ignore.any { lower.contains(it) }) return
        if (!currency.containsMatchIn(body) || !amount.containsMatchIn(body)) return
        if (transaction.none { lower.contains(it) }) return
        val blocked = prefs.getString("blockedSenders", "") ?: ""
        val from = (parts[0].originatingAddress ?: "").lowercase().replace(Regex("[^a-z0-9\u0600-\u06ff]"), "")
        if (from.isNotEmpty() && blocked.split("\n").any { b ->
                val n = b.lowercase().replace(Regex("[^a-z0-9\u0600-\u06ff]"), "")
                n.isNotEmpty() && from.contains(n)
            }) return

        val sender = parts[0].originatingAddress ?: "Bank"
        val ar = Reminder.arabic(ctx)
        Notifier.show(
            ctx,
            2000 + (System.currentTimeMillis() % 1000).toInt(),
            if (ar) "عملية جديدة للمراجعة" else "New transaction to review",
            if (ar) "من $sender. اضغط لتأكيد المبلغ واختيار الفئة."
            else "From $sender. Tap to confirm the amount and pick a category."
        )
    }
}
