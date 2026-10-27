# Household Ledger (Android MVP)

Personal income and expense tracker for Saudi bank accounts. No AI and no cloud: everything is stored on the phone.

## What it does

| Area | Features |
|---|---|
| **Data entry** | Reads bank SMS (Arabic and English), extracts amount, merchant and in/out, and puts each one in a **Review** list to confirm with a category. Manual entry with "Save & add another" for end-of-day logging. |
| **Learning categories** | Merchant keywords map to categories (Lulu → Groceries, Tameeni → Transport…). Every confirmation teaches a new rule. Rules are editable. |
| **Budget template** | One default monthly budget per category. Any single period can be changed ("this period only") without touching the template, and reset back. Expected income shows the plan against 50/30/20. "Suggest" fills the template from your last 3 periods. |
| **Periods** | Calendar months or salary-to-salary (choose the start day, e.g. 27th). |
| **Dashboard** | Net cash flow, savings rate, budget left and per-day allowance, categories closest to their limit, insights, recent entries. |
| **Analytics** | Six-period trend, daily spending vs daily budget, category breakdown with change vs last period, needs/wants/savings split, top merchants. |
| **Notifications** | Budget warning at your threshold (default 80%) and at 100%, per category and total. Alert when a bank SMS arrives. Daily reminder (default 21:00). |
| **Data** | CSV export to clipboard; CSV import (accepts the web ledger export). |

## Build the APK (GitHub Actions)

1. Push this folder to a GitHub repository (branch `main`).
2. The **Build APK** workflow runs automatically (Actions tab). It tests the SMS parser, builds a release APK and publishes it under **Releases** as `app-release.apk`.
3. To rebuild without code changes: Actions → Build APK → Run workflow.

## Install on the phone

1. Open the repository's **Releases** page on the phone and download `app-release.apk`.
2. Android asks to allow installs from your browser/files app: allow it.
3. Play Protect may warn that the app is from an unknown developer. Choose **Install anyway**. This is expected for an app you built yourself.
4. On first launch choose **Allow SMS & notifications**.
   - On Android 13+, if SMS access is blocked as a "restricted setting": Settings → Apps → Household Ledger → ⋮ → **Allow restricted settings**, then grant SMS permission.
5. Updates: install a newer APK over the old one. Data is kept.

## First-time setup (5 minutes)

1. **Settings → Period starts on day**: 1 for calendar months, or your salary day.
2. **Budget → Template**: set expected income and an amount per category.
3. **Review**: confirm the SMS found since the start of the current period.
4. Optional: **Settings → Bank senders** to only read your bank's sender names.
5. Optional: copy the CSV from the web ledger and use **Settings → Import entries from CSV**.

## Project layout

```
lib/
  main.dart            app shell, bottom navigation, first-run flow
  state.dart           SQLite data layer, budgets, SMS scan, alerts, CSV
  sms_parser.dart      rule-based SMS reader (amount, merchant, in/out)
  stats.dart           period totals, insights, averages
  periods.dart         calendar / salary-cycle periods
  screens/             home, review, entries, entry form, analytics, budget, settings
android/app/src/main/
  AndroidManifest.xml  permissions and receivers
  kotlin/…/            SMS reading, notifications, daily reminder
test/parser_test.dart  SMS parser and period tests (run in CI)
```

The Gradle files are generated in CI by `flutter create`, so only customised Android files are kept in the repo.
