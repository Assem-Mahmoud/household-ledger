# Generates the ad voice-over lines with several Arabic neural voices (run on CI, which has internet access).
import asyncio, json, os, edge_tts
VOICES = ["ar-SA-HamedNeural", "ar-SA-ZariyahNeural", "ar-JO-TaimNeural", "ar-EG-SalmaNeural"]
lines = json.load(open("media/vo/lines.json", encoding="utf-8"))
async def main():
    for v in VOICES:
        os.makedirs(f"media/vo/out/{v}", exist_ok=True)
        for key, text in lines:
            c = edge_tts.Communicate(text, v, rate="-6%", pitch="+0Hz")
            await c.save(f"media/vo/out/{v}/{key}.mp3")
            print(v, key)
asyncio.run(main())
