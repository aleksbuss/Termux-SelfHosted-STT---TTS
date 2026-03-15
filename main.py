#!/usr/bin/env python3
"""
Voice AI Bot v7.0 (Ultimate Android Fix)
STT: Whisper | TTS: Piper via proot-distro
"""

import os
import sys
import asyncio
import tempfile
import logging
import uuid
import re
import sqlite3
from aiogram import Bot, Dispatcher, F, types
from aiogram.types import FSInputFile, InlineKeyboardMarkup, InlineKeyboardButton
from aiogram.filters import Command
from num2words import num2words

# ── Config ──
BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
WHISPER_BIN = os.environ.get("WHISPER_BIN", os.path.expanduser("~/voice-bot/whisper.cpp/build/bin/whisper-cli"))
WHISPER_MODEL = os.environ.get("WHISPER_MODEL", os.path.expanduser("~/voice-bot/whisper.cpp/models/ggml-base.bin"))
PIPER_BIN = os.environ.get("PIPER_BIN", os.path.expanduser("~/voice-bot/piper/piper"))
MODELS_DIR = os.environ.get("MODELS_DIR", os.path.expanduser("~/voice-bot/piper/models"))

MAX_VOICE_DURATION = 300
MAX_TTS_CHARS = 1000
TIMEOUT_SEC = 120

# ВАЖНО: Папка tmp внутри проекта, чтобы контейнер Ubuntu имел к ней прямой доступ
TEMP_DIR = os.path.expanduser("~/voice-bot/tmp")
os.makedirs(TEMP_DIR, exist_ok=True)
DB_PATH = os.path.expanduser("~/voice-bot/users.db")

LANG_CONFIG = {
    "ru": {"whisper": "ru", "piper": "ru_RU-irina-medium.onnx", "n2w": "ru", "icon": "🇷🇺", "name": "Русский"},
    "en": {"whisper": "en", "piper": "en_US-lessac-medium.onnx", "n2w": "en", "icon": "🇬🇧", "name": "English"},
    "es": {"whisper": "es", "piper": "es_ES-davefx-medium.onnx", "n2w": "es", "icon": "🇪🇸", "name": "Español"}
}

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s", datefmt="%H:%M:%S")
log = logging.getLogger("bot")

def init_db():
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS users (user_id INTEGER PRIMARY KEY, lang TEXT DEFAULT 'ru')")

def get_user_lang(user_id: int) -> str:
    with sqlite3.connect(DB_PATH) as conn:
        res = conn.execute("SELECT lang FROM users WHERE user_id = ?", (user_id,)).fetchone()
        return res[0] if res else "ru"

def set_user_lang(user_id: int, lang: str):
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute("INSERT INTO users (user_id, lang) VALUES (?, ?) ON CONFLICT(user_id) DO UPDATE SET lang = ?", (user_id, lang, lang))

init_db()

bot = Bot(token=BOT_TOKEN)
dp = Dispatcher()

whisper_lock = asyncio.Semaphore(1)
piper_lock = asyncio.Semaphore(1)
_active_processes = set()

def clean_text_for_piper(text: str) -> str:
    text = re.sub(r'http\S+', '', text)
    text = re.sub(r'[^\w\s\.,!\?¿¡\'\"-]', '', text, flags=re.UNICODE)
    return text.strip()

def normalize_text(text: str, lang: str) -> str:
    try:
        text = clean_text_for_piper(text)
        def replace_num(match):
            return num2words(int(match.group(0)), lang=LANG_CONFIG[lang]['n2w'])
        text = re.sub(r'\d+', replace_num, text)
    except Exception as e:
        log.warning(f"Normalization error: {e}")
    return text

async def run_proc(*args, timeout=TIMEOUT_SEC, stdin_data=None):
    proc = None
    try:
        proc = await asyncio.create_subprocess_exec(
            *args,
            stdin=asyncio.subprocess.PIPE if stdin_data else None,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        _active_processes.add(proc)
        stdout, stderr = await asyncio.wait_for(proc.communicate(input=stdin_data), timeout=timeout)
        return proc.returncode, stdout, stderr
    except asyncio.CancelledError:
        if proc:
            try: proc.kill()
            except: pass
        raise
    except Exception as e:
        if proc:
            try: proc.kill()
            except: pass
        log.error(f"Process failed: {e}")
        return -1, b"", str(e).encode()
    finally:
        if proc in _active_processes:
            _active_processes.remove(proc)

async def stt(ogg_path: str, lang: str) -> str | None:
    uid = str(uuid.uuid4())[:8]
    wav_path = os.path.join(TEMP_DIR, f"{uid}.wav")

    try:
        rc, _, _ = await run_proc("ffmpeg", "-y", "-i", ogg_path, "-ar", "16000", "-ac", "1", "-f", "wav", wav_path)
        if rc != 0: return None

        async with whisper_lock:
            whisper_lang = LANG_CONFIG[lang]["whisper"]
            rc, out, _ = await run_proc(WHISPER_BIN, "-m", WHISPER_MODEL, "-f", wav_path, "-l", whisper_lang, "-nt")
        
        if rc != 0: return None
        
        text = out.decode(errors="ignore").strip()
        if not text or "[" in text or "(" in text: 
            return None
        return text
    finally:
        if os.path.exists(wav_path): os.remove(wav_path)

async def tts(text: str, lang: str) -> str | None:
    uid = str(uuid.uuid4())[:8]
    wav_path = os.path.join(TEMP_DIR, f"{uid}.wav")
    ogg_path = os.path.join(TEMP_DIR, f"{uid}.ogg")

    norm_text = normalize_text(text, lang)
    if not norm_text: return None

    model_path = os.path.join(MODELS_DIR, LANG_CONFIG[lang]["piper"])

    try:
        async with piper_lock:
            # ИДЕАЛЬНОЕ РЕШЕНИЕ: Запускаем Piper внутри Ubuntu-контейнера через proot-distro!
            rc, out, err = await run_proc(
                "proot-distro", "login", "ubuntu", "--",
                PIPER_BIN, "--model", model_path, "--output_file", wav_path,
                stdin_data=norm_text.encode('utf-8')
            )
        
        if rc != 0: 
            log.error(f"Piper error: {err.decode('utf-8', 'ignore')}")
            return None

        rc, _, _ = await run_proc("ffmpeg", "-y", "-i", wav_path, "-c:a", "libopus", "-b:a", "64k", ogg_path)
        if rc == 0 and os.path.exists(ogg_path):
            return ogg_path
        return None
    finally:
        if os.path.exists(wav_path): os.remove(wav_path)

def get_lang_keyboard():
    buttons = [
        [InlineKeyboardButton(text=f"{v['icon']} {v['name']}", callback_data=f"lang_{k}")] 
        for k, v in LANG_CONFIG.items()
    ]
    return InlineKeyboardMarkup(inline_keyboard=buttons)

@dp.message(Command("lang"))
async def cmd_lang(msg: types.Message):
    curr_lang = get_user_lang(msg.from_user.id)
    await msg.answer(
        f"Текущий язык / Current language: {LANG_CONFIG[curr_lang]['icon']}\nВыберите язык / Choose language:",
        reply_markup=get_lang_keyboard()
    )

@dp.callback_query(F.data.startswith("lang_"))
async def process_lang_selection(callback: types.CallbackQuery):
    lang_code = callback.data.split("_")[1]
    set_user_lang(callback.from_user.id, lang_code)
    await callback.message.edit_text(f"✅ Язык изменен на / Language set to: {LANG_CONFIG[lang_code]['icon']} {LANG_CONFIG[lang_code]['name']}")
    await callback.answer()

@dp.message(Command("start", "help"))
async def cmd_start(msg: types.Message):
    await msg.answer(
        "🎙 Voice AI Bot (Enterprise Local)\n\n"
        "Send Voice -> Get Text\n"
        "Send Text -> Get Voice\n\n"
        "🌐 Change language: /lang"
    )

@dp.message(F.voice | F.audio)
async def handle_voice(msg: types.Message):
    if (msg.voice and msg.voice.duration > MAX_VOICE_DURATION) or (msg.audio and msg.audio.duration > MAX_VOICE_DURATION):
        return await msg.reply("Audio is too long.")

    lang = get_user_lang(msg.from_user.id)
    status = await msg.answer("⏳ Processing...")
    
    uid = str(uuid.uuid4())[:8]
    ogg_path = os.path.join(TEMP_DIR, f"{uid}_in.ogg")

    try:
        file_id = msg.voice.file_id if msg.voice else msg.audio.file_id
        tg_file = await bot.get_file(file_id)
        await bot.download_file(tg_file.file_path, ogg_path)

        text = await stt(ogg_path, lang)
        
        if text:
            await status.edit_text(text)
        else:
            await status.edit_text("❌ Speech not recognized.")
    except Exception as e:
        log.error(f"Voice error: {e}")
        await status.edit_text("❌ Error processing audio.")
    finally:
        if os.path.exists(ogg_path): os.remove(ogg_path)

@dp.message(F.text)
async def handle_text(msg: types.Message):
    if len(msg.text) > MAX_TTS_CHARS:
        return await msg.reply("Text is too long.")

    lang = get_user_lang(msg.from_user.id)
    status = await msg.answer("⏳ Generating voice...")
    ogg_path = None

    try:
        ogg_path = await tts(msg.text, lang)
        if ogg_path:
            await msg.answer_voice(FSInputFile(ogg_path))
            await status.delete()
        else:
            await status.edit_text("❌ Could not generate speech. (Tip: Try using regular text without complex emojis)")
    except Exception as e:
        log.error(f"Text error: {e}")
        await status.edit_text("❌ Error processing text.")
    finally:
        if ogg_path and os.path.exists(ogg_path): os.remove(ogg_path)

async def main():
    try:
        await dp.start_polling(bot, handle_signals=False)
    finally:
        log.info("Shutting down... Killing active subprocesses.")
        for proc in list(_active_processes):
            try: proc.kill()
            except: pass
        await bot.session.close()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
