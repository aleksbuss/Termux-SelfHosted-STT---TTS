#!/usr/bin/env python3
"""
Telegram Voice AI Bot — Termux Edition v5.0 (Premium Voice)
STT: whisper.cpp (whisper-cli) — local speech recognition
TTS: Piper TTS (irina-medium) — premium local text-to-speech
100% offline, zero cloud dependencies
"""

import os
import sys
import asyncio
import signal
import tempfile
import logging
import hashlib
import time
import re

from aiogram import Bot, Dispatcher, F, types
from aiogram.types import FSInputFile
from num2words import num2words

# ── Config ──
BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
WHISPER_BIN = os.environ.get(
    "WHISPER_BIN",
    os.path.expanduser("~/voice-bot/whisper.cpp/build/bin/whisper-cli"),
)
WHISPER_MODEL = os.environ.get(
    "WHISPER_MODEL",
    os.path.expanduser("~/voice-bot/whisper.cpp/models/ggml-base.bin"),
)

# Новые переменные для Piper TTS
PIPER_BIN = os.environ.get(
    "PIPER_BIN",
    os.path.expanduser("~/voice-bot/piper/piper"),
)
PIPER_MODEL = os.environ.get(
    "PIPER_MODEL",
    os.path.expanduser("~/voice-bot/piper/models/ru_RU-irina-medium.onnx"),
)

# Limits
MAX_VOICE_DURATION = 300      # seconds (5 min)
MAX_TTS_CHARS = 1000          # limits for phone processing
WHISPER_TIMEOUT = 120         # seconds — prevent hanging
PIPER_TIMEOUT = 60            # seconds for TTS generation
RATE_LIMIT_SECONDS = 3        # per-user cooldown between requests
TEMP_DIR = os.path.join(tempfile.gettempdir(), "voice-bot")

# Known whisper non-speech markers
WHISPER_NOISE = {
    "[BLANK_AUDIO]", "[MUSIC]", "[NOISE]", "[SILENCE]",
    "(music)", "(silence)", "[Music]", "[Silence]",
}

# ── Logging ──
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("bot")

# ── Validate config at startup ──
errors = []
if not BOT_TOKEN:
    errors.append("TELEGRAM_BOT_TOKEN not set in .env")
if not os.path.isfile(WHISPER_BIN):
    errors.append(f"whisper-cli not found: {WHISPER_BIN}")
if not os.path.isfile(WHISPER_MODEL):
    errors.append(f"Whisper model not found: {WHISPER_MODEL}")
if not os.path.isfile(PIPER_BIN):
    errors.append(f"Piper binary not found: {PIPER_BIN}")
if not os.path.isfile(PIPER_MODEL):
    errors.append(f"Piper model not found: {PIPER_MODEL}")
if errors:
    for e in errors:
        log.error(e)
    sys.exit(1)

os.makedirs(TEMP_DIR, exist_ok=True)

PID_FILE = os.path.join(os.path.expanduser("~"), "voice-bot", "bot.pid")

def write_pid():
    try:
        with open(PID_FILE, "w") as f:
            f.write(str(os.getpid()))
    except OSError as e:
        log.warning(f"Could not write PID file: {e}")

def remove_pid():
    try:
        if os.path.exists(PID_FILE):
            os.remove(PID_FILE)
    except OSError:
        pass

write_pid()

bot = Bot(token=BOT_TOKEN)
dp = Dispatcher()

# Семафоры для защиты процессора телефона (по 1 задаче за раз)
whisper_lock = asyncio.Semaphore(1)
piper_lock = asyncio.Semaphore(1)

_user_cooldown: dict[int, float] = {}
_shutdown_done = False

# ══════════════════════════════════
# Helpers & Text Normalization
# ══════════════════════════════════

def safe_path(file_id: str, ext: str) -> str:
    h = hashlib.md5(file_id.encode()).hexdigest()[:12]
    return os.path.join(TEMP_DIR, f"{h}{ext}")

def cleanup(*paths):
    for p in paths:
        try:
            if p and os.path.exists(p):
                os.remove(p)
        except OSError:
            pass

def is_rate_limited(user_id: int) -> bool:
    now = time.monotonic()
    last = _user_cooldown.get(user_id, 0)
    if now - last < RATE_LIMIT_SECONDS:
        return True
    _user_cooldown[user_id] = now
    return False

def normalize_text(text: str) -> str:
    """Переводит цифры в слова для правильного произношения нейросетью"""
    try:
        def replace_num(match):
            return num2words(int(match.group(0)), lang='ru')
        # Заменяем все последовательности цифр на слова
        text = re.sub(r'\d+', replace_num, text)
    except Exception as e:
        log.warning(f"Ошибка при нормализации текста: {e}")
    return text

async def run_proc(*args, timeout=60, stdin_data=None):
    """Run subprocess with timeout and optional stdin."""
    try:
        proc = await asyncio.create_subprocess_exec(
            *args,
            stdin=asyncio.subprocess.PIPE if stdin_data else None,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(input=stdin_data), timeout=timeout
        )
        return proc.returncode, stdout, stderr
    except (asyncio.TimeoutError, TimeoutError):
        try:
            proc.kill()
            await proc.wait()
        except ProcessLookupError:
            pass
        log.warning(f"Process timed out ({timeout}s): {args[0]}")
        return -1, b"", b"timeout"
    except Exception as e:
        log.error(f"run_proc error: {e}")
        return -1, b"", str(e).encode()

# ══════════════════════════════════
# STT / TTS engines
# ══════════════════════════════════

async def stt(ogg_path: str) -> str | None:
    base = os.path.splitext(ogg_path)[0]
    wav_path = base + ".wav"

    try:
        rc, _, err = await run_proc(
            "ffmpeg", "-y", "-i", ogg_path,
            "-ar", "16000", "-ac", "1", "-f", "wav", wav_path,
            timeout=30,
        )
        if rc != 0:
            log.error(f"ffmpeg: {err.decode(errors='replace')[:200]}")
            return None

        async with whisper_lock:
            rc, out, err = await run_proc(
                WHISPER_BIN, "-m", WHISPER_MODEL,
                "-f", wav_path, "-l", "auto", "-nt",
                timeout=WHISPER_TIMEOUT,
            )

        if rc != 0:
            log.error(f"whisper: {err.decode(errors='replace')[:200]}")
            return None

        text = out.decode(errors="replace").strip()
        if not text or text in WHISPER_NOISE:
            return None
        return text

    finally:
        cleanup(wav_path)

async def tts(text: str) -> str | None:
    fd, wav_path = tempfile.mkstemp(suffix=".wav", dir=TEMP_DIR)
    os.close(fd)

    base = os.path.splitext(wav_path)[0]
    ogg_path = base + ".ogg"

    # Подготавливаем текст (цифры -> слова)
    normalized_text = normalize_text(text)

    try:
        async with piper_lock:
            # Piper принимает текст через стандартный ввод (stdin)
            rc, _, err = await run_proc(
                PIPER_BIN, "--model", PIPER_MODEL, "--output_file", wav_path,
                timeout=PIPER_TIMEOUT,
                stdin_data=normalized_text.encode('utf-8')
            )
            
        if rc != 0:
            log.error(f"piper: {err.decode(errors='replace')[:200]}")
            cleanup(wav_path)
            return None

        # Сохраняем премиальное качество: кодируем в opus (Telegram voice)
        rc, _, _ = await run_proc(
            "ffmpeg", "-y", "-i", wav_path,
            "-c:a", "libopus", "-b:a", "64k", ogg_path,
            timeout=30,
        )
        cleanup(wav_path)

        if rc == 0 and os.path.exists(ogg_path):
            return ogg_path

        cleanup(ogg_path)
        return None

    except Exception as e:
        log.error(f"tts error: {e}")
        cleanup(wav_path, ogg_path)
        return None

# ══════════════════════════════════
# Handlers
# ══════════════════════════════════

@dp.message(F.voice | F.audio)
async def handle_voice(msg: types.Message):
    if is_rate_limited(msg.from_user.id):
        await msg.reply("Подождите пару секунд...")
        return

    duration = msg.voice.duration if msg.voice else (msg.audio.duration if msg.audio else 0)
    if duration > MAX_VOICE_DURATION:
        await msg.reply(f"Аудио слишком длинное ({duration}с). Максимум: {MAX_VOICE_DURATION}с")
        return

    status = await msg.answer("Распознаю текст...")
    ogg_path = None

    try:
        file_id = msg.voice.file_id if msg.voice else msg.audio.file_id
        tg_file = await bot.get_file(file_id)
        ogg_path = safe_path(tg_file.file_id, ".ogg")
        await bot.download_file(tg_file.file_path, ogg_path)

        text = await stt(ogg_path)

        if text:
            await status.edit_text(text)
        else:
            await status.edit_text("Не удалось распознать речь. Попробуете еще раз?")

    except Exception as e:
        log.error(f"handle_voice: {e}")
        try:
            await status.edit_text("Ошибка обработки. Попробуйте снова.")
        except Exception:
            pass
    finally:
        cleanup(ogg_path)


@dp.message(F.text)
async def handle_text(msg: types.Message):
    text = (msg.text or "").strip()

    if text.startswith("/"):
        cmd = text.split()[0].split("@")[0].lower()
        if cmd in ("/start", "/help"):
            await msg.answer(
                "Voice AI Bot (Premium 100% Local)\n\n"
                "Голосовое сообщение -> распознанный текст (Whisper)\n"
                "Текстовое сообщение -> премиальный голос (Piper TTS)\n\n"
                "Все данные обрабатываются прямо на этом устройстве."
            )
        elif cmd == "/ping":
            await msg.answer("Pong!")
        return

    if not text:
        return

    if is_rate_limited(msg.from_user.id):
        await msg.reply("Подождите пару секунд...")
        return

    if len(text) > MAX_TTS_CHARS:
        await msg.reply(f"Текст слишком длинный ({len(text)} симв.). Максимум: {MAX_TTS_CHARS}")
        return

    status = await msg.answer("Генерирую голос...")
    ogg_path = None

    try:
        ogg_path = await tts(text)

        if ogg_path:
            await msg.answer_voice(FSInputFile(ogg_path))
            try:
                await status.delete()
            except Exception:
                pass
        else:
            await status.edit_text("Не удалось сгенерировать речь.")

    except Exception as e:
        log.error(f"handle_text: {e}")
        try:
            await status.edit_text("Ошибка обработки. Попробуйте снова.")
        except Exception:
            pass
    finally:
        cleanup(ogg_path)

# ══════════════════════════════════
# Lifecycle
# ══════════════════════════════════

async def on_shutdown():
    global _shutdown_done
    if _shutdown_done:
        return
    _shutdown_done = True

    log.info("Shutting down...")
    remove_pid()
    try:
        await bot.session.close()
    except Exception:
        pass

    try:
        for f in os.listdir(TEMP_DIR):
            cleanup(os.path.join(TEMP_DIR, f))
    except FileNotFoundError:
        pass

async def main():
    log.info("=" * 40)
    log.info("  Voice AI Bot v5.0 (Premium) STARTED")
    log.info(f"  STT: {os.path.basename(WHISPER_BIN)}")
    log.info(f"  TTS: Piper (irina-medium.onnx)")
    log.info("=" * 40)

    dp.shutdown.register(on_shutdown)

    try:
        await dp.start_polling(bot, handle_signals=False)
    except (KeyboardInterrupt, SystemExit):
        pass
    finally:
        await on_shutdown()

if __name__ == "__main__":
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    def _sig_handler(sig, _frame):
        log.info(f"Signal {sig}, stopping...")
        for task in asyncio.all_tasks(loop):
            task.cancel()

    signal.signal(signal.SIGTERM, _sig_handler)
    signal.signal(signal.SIGINT, _sig_handler)

    try:
        loop.run_until_complete(main())
    except (KeyboardInterrupt, asyncio.CancelledError):
        pass
    finally:
        loop.run_until_complete(on_shutdown())
        loop.close()
