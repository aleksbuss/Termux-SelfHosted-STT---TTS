#!/usr/bin/env python3
import os, asyncio, tempfile, logging
from aiogram import Bot, Dispatcher, F, types
from aiogram.types import FSInputFile

BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
WHISPER_BIN = os.environ.get("WHISPER_BIN",
    os.path.expanduser("~/voice-bot/whisper.cpp/build/bin/whisper-cli"))
WHISPER_MODEL = os.environ.get("WHISPER_MODEL",
    os.path.expanduser("~/voice-bot/whisper.cpp/models/ggml-base.bin"))
ESPEAK_VOICE = os.environ.get("ESPEAK_VOICE", "ru")

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)
if not BOT_TOKEN:
    exit("TELEGRAM_BOT_TOKEN not set")
if not os.path.isfile(WHISPER_BIN):
    exit(f"whisper-cli not found: {WHISPER_BIN}")
if not os.path.isfile(WHISPER_MODEL):
    exit(f"Model not found: {WHISPER_MODEL}")

bot = Bot(token=BOT_TOKEN)
dp = Dispatcher()

async def run(*a):
    p = await asyncio.create_subprocess_exec(
        *a, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    o, e = await p.communicate()
    return p.returncode, o, e

async def stt(ogg):
    wav = ogg + ".wav"
    try:
        r, _, _ = await run("ffmpeg","-y","-i",ogg,"-ar","16000","-ac","1","-f","wav",wav)
        if r: return "[ffmpeg error]"
        r, o, e = await run(WHISPER_BIN,"-m",WHISPER_MODEL,"-f",wav,"-l","auto","-nt","--no-prints")
        if r: return "[whisper error]"
        t = o.decode().strip()
        return t or "[silence]"
    finally:
        if os.path.exists(wav): os.remove(wav)

async def tts(text):
    fd, wav = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    ogg = wav.replace(".wav", ".ogg")
    try:
        r, _, _ = await run("espeak","-v",ESPEAK_VOICE,"-w",wav,text)
        if r: return None
        r, _, _ = await run("ffmpeg","-y","-i",wav,"-c:a","libopus","-b:a","64k",ogg)
        if os.path.exists(wav): os.remove(wav)
        return ogg if not r and os.path.exists(ogg) else None
    except:
        for p in [wav, ogg]:
            if os.path.exists(p): os.remove(p)
        return None

@dp.message(F.voice | F.audio)
async def hv(m: types.Message):
    s = await m.answer("...")
    ogg = None
    try:
        fid = m.voice.file_id if m.voice else m.audio.file_id
        f = await bot.get_file(fid)
        ogg = os.path.join(tempfile.gettempdir(), f.file_id + ".ogg")
        await bot.download_file(f.file_path, ogg)
        await s.edit_text(await stt(ogg))
    except Exception as e:
        await s.edit_text(str(e))
    finally:
        if ogg and os.path.exists(ogg): os.remove(ogg)

@dp.message(F.text)
async def ht(m: types.Message):
    if m.text.startswith("/"):
        if m.text == "/start":
            await m.answer("Voice->Text | Text->Voice | 100% local")
        return
    s = await m.answer("...")
    ogg = None
    try:
        ogg = await tts(m.text[:1000])
        if ogg:
            await m.answer_voice(FSInputFile(ogg))
            await s.delete()
        else:
            await s.edit_text("TTS error")
    except Exception as e:
        await s.edit_text(str(e))
    finally:
        if ogg and os.path.exists(ogg): os.remove(ogg)

if __name__ == "__main__":
    log.info("Bot started")
    asyncio.run(dp.start_polling(bot))
