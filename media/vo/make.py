# Generates the ad voice-over lines (run on CI, which has internet access).
# Tries Microsoft neural voices via edge-tts; falls back to the open Piper Arabic voice. Writes a log either way.
import asyncio, json, os, subprocess, traceback, urllib.request
lines = json.load(open("media/vo/lines.json", encoding="utf-8"))
log = open("media/vo/out/log.txt", "w", encoding="utf-8")
def say(*a):
    print(*a); log.write(" ".join(map(str, a)) + "\n"); log.flush()

async def edge():
    import edge_tts
    ok = 0
    for v in ["ar-SA-HamedNeural"]:
        try:
            os.makedirs(f"media/vo/out/simple/{v}", exist_ok=True)
            for key, text in lines:
                c = edge_tts.Communicate(text, v, rate="-3%")
                await c.save(f"media/vo/out/simple/{v}/{key}.mp3")
            say("edge ok", v); ok += 1
        except Exception:
            say("edge failed", v, traceback.format_exc())
    return ok

def piper():
    base = "https://huggingface.co/rhasspy/piper-voices/resolve/main/ar/ar_JO/kareem/medium/"
    os.makedirs("pv", exist_ok=True)
    for f in ["ar_JO-kareem-medium.onnx", "ar_JO-kareem-medium.onnx.json"]:
        urllib.request.urlretrieve(base + f, "pv/" + f)
    os.makedirs("media/vo/out/piper-kareem", exist_ok=True)
    for key, text in lines:
        subprocess.run(["python", "-m", "piper", "-m", "pv/ar_JO-kareem-medium.onnx", "-f", f"media/vo/out/piper-kareem/{key}.wav"],
                       input=text.encode("utf-8"), check=True)
    say("piper ok")

os.makedirs("media/vo/out", exist_ok=True)
n = 0
try:
    n = asyncio.run(edge())
except Exception:
    say("edge import/run failed", traceback.format_exc())
log.close()
