"""Points the release build at the permanent signing key (CI only).

The key file in signing/ is AES-256 encrypted; its password lives only in the
LEDGER_KEY_PASSWORD repository secret. Works for Groovy and Kotlin Gradle files.
"""
import os, pathlib, sys

if not os.environ.get("LEDGER_KEY_PASSWORD"):
    print("::warning::LEDGER_KEY_PASSWORD secret is not set - this build uses a temporary key and cannot update an installed app.")
    sys.exit(0)

for name, block, use in [
    ("build.gradle",
     '    signingConfigs {\n        release {\n            storeFile file(System.getenv("LEDGER_KEYSTORE"))\n'
     '            storePassword System.getenv("LEDGER_KEY_PASSWORD")\n            keyAlias "ledger"\n'
     '            keyPassword System.getenv("LEDGER_KEY_PASSWORD")\n            storeType "pkcs12"\n        }\n    }\n',
     "signingConfigs.release"),
    ("build.gradle.kts",
     '    signingConfigs {\n        create("release") {\n            storeFile = file(System.getenv("LEDGER_KEYSTORE"))\n'
     '            storePassword = System.getenv("LEDGER_KEY_PASSWORD")\n            keyAlias = "ledger"\n'
     '            keyPassword = System.getenv("LEDGER_KEY_PASSWORD")\n            storeType = "pkcs12"\n        }\n    }\n',
     'signingConfigs.getByName("release")'),
]:
    f = pathlib.Path("android/app") / name
    if not f.exists():
        continue
    s = f.read_text()
    if "LEDGER_KEYSTORE" in s:
        sys.exit(0)
    if "    buildTypes {" not in s or "signingConfigs.debug" not in s and 'getByName("debug")' not in s:
        sys.exit(f"::error::Unexpected {f} layout - cannot apply signing")
    s = s.replace("    buildTypes {", block + "\n    buildTypes {", 1)
    s = s.replace("signingConfigs.debug", use).replace('signingConfigs.getByName("debug")', use)
    f.write_text(s)
    print(f"Release signing applied to {f}")
    sys.exit(0)
sys.exit("::error::No android/app/build.gradle(.kts) found")
