#!/usr/bin/env python3
"""
Telegram Voice AI Bot — Termux Edition v4.0
STT: whisper.cpp (whisper-cli) — local speech recognition
TTS: espeak-ng — local text-to-speech
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

from aiogram import Bot, Dispatcher, F, types
from aiogram.types import FSInputFile

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
ESPEAK_VOICE = os.environ.get("ESPEAK_VOICE", "ru")

# Limits
MAX_VOICE_DURATION = 300      # seconds (5 min)
MAX_TTS_CHARS = 1000          # espeak handles this fine
WHISPER_TIMEOUT = 120         # seconds — prevent hanging
RATE_LIMIT_SECONDS = 3        # per-user cooldown between requests
TEMP_DIR = os.path.join(tempfile.gettempdir(), "voice-bot")

# Known whisper non-speech markers (not actual transcription)
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
if errors:
    for e in errors:
        log.error(e)
    sys.exit(1)

os.makedirs(TEMP_DIR, exist_ok=True)

# ── PID file for reliable stop/start ──
PID_FILE = os.path.join(os.path.expanduser("~"), "voice-bot", "bot.pid")


def write_pid():
    """Write current PID to file."""
    try:
        with open(PID_FILE, "w") as f:
            f.write(str(os.getpid()))
    except OSError as e:
        log.warning(f"Could not write PID file: {e}")


def remove_pid():
    """Remove PID file on exit."""
    try:
        if os.path.exists(PID_FILE):
            os.remove(PID_FILE)
    except OSError:
        pass


write_pid()

bot = Bot(token=BOT_TOKEN)
dp = Dispatcher()

# Only 1 whisper process at a time (phone CPU is single-threaded effectively)
whisper_lock = asyncio.Semaphore(1)

# Per-user rate limiting: user_id -> last_request_time
_user_cooldown: dict[int, float] = {}

# Track shutdown state to avoid double-close
_shutdown_done = False


# ══════════════════════════════════
# Helpers
# ══════════════════════════════════

def safe_path(file_id: str, ext: str) -> str:
    """Generate collision-safe temp path from Telegram file_id."""
    h = hashlib.md5(file_id.encode()).hexdigest()[:12]
    return os.path.join(TEMP_DIR, f"{h}{ext}")


def cleanup(*paths):
    """Remove files silently."""
    for p in paths:
        try:
            if p and os.path.exists(p):
                os.remove(p)
        except OSError:
            pass


def is_rate_limited(user_id: int) -> bool:
    """Check per-user cooldown. Returns True if too soon."""
    now = time.monotonic()
    last = _user_cooldown.get(user_id, 0)
    if now - last < RATE_LIMIT_SECONDS:
        return True
    _user_cooldown[user_id] = now
    return False


async def run_proc(*args, timeout=60):
    """Run subprocess with timeout. Returns (returncode, stdout, stderr)."""
    try:
        proc = await asyncio.create_subprocess_exec(
            *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(), timeout=timeout
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
    """Speech-to-text via whisper.cpp. Returns text or None."""
    # Use proper extension split, not concatenation
    base = os.path.splitext(ogg_path)[0]
    wav_path = base + ".wav"

    try:
        # OGG -> WAV 16kHz mono (whisper requirement)
        rc, _, err = await run_proc(
            "ffmpeg", "-y", "-i", ogg_path,
            "-ar", "16000", "-ac", "1", "-f", "wav", wav_path,
            timeout=30,
        )
        if rc != 0:
            log.error(f"ffmpeg: {err.decode(errors='replace')[:200]}")
            return None

        # Whisper — serialized via semaphore (phone has limited CPU)
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

        # Filter known whisper noise markers
        if not text:
            return None
        if text in WHISPER_NOISE:
            return None

        return text

    finally:
        cleanup(wav_path)


async def tts(text: str) -> str | None:
    """Text-to-speech via espeak-ng. Returns path to OGG or None."""
    fd, wav_path = tempfile.mkstemp(suffix=".wav", dir=TEMP_DIR)
    os.close(fd)

    # Proper extension swap
    base = os.path.splitext(wav_path)[0]
    ogg_path = base + ".ogg"

    try:
        rc, _, err = await run_proc(
            "espeak", "-v", ESPEAK_VOICE, "-w", wav_path, text,
            timeout=30,
        )
        if rc != 0:
            log.error(f"espeak: {err.decode(errors='replace')[:200]}")
            cleanup(wav_path)
            return None

        # WAV -> OGG opus (Telegram voice format)
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
    """Voice/audio -> transcribed text."""
    if is_rate_limited(msg.from_user.id):
        await msg.reply("Please wait a few seconds...")
        return

    # Duration check
    duration = 0
    if msg.voice:
        duration = msg.voice.duration or 0
    elif msg.audio:
        duration = msg.audio.duration or 0

    if duration > MAX_VOICE_DURATION:
        await msg.reply(f"Audio too long ({duration}s). Max: {MAX_VOICE_DURATION}s")
        return

    status = await msg.answer("Recognizing...")
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
            await status.edit_text("Could not recognize speech. Try again?")

    except Exception as e:
        log.error(f"handle_voice: {e}")
        try:
            await status.edit_text("Processing error. Please try again.")
        except Exception:
            pass
    finally:
        cleanup(ogg_path)


@dp.message(F.text)
async def handle_text(msg: types.Message):
    """Text -> voice reply."""
    text = (msg.text or "").strip()

    # Commands — handle /cmd@botname format for groups
    if text.startswith("/"):
        cmd = text.split()[0].split("@")[0].lower()
        if cmd in ("/start", "/help"):
            await msg.answer(
                "Voice AI Bot (100% local)\n\n"
                "Voice message -> transcribed text\n"
                "Text message -> spoken voice\n\n"
                "/start — this help\n"
                "/ping — check if bot is alive\n\n"
                "All data stays on this device."
            )
        elif cmd == "/ping":
            await msg.answer("Pong!")
        return

    if not text:
        return

    if is_rate_limited(msg.from_user.id):
        await msg.reply("Please wait a few seconds...")
        return

    if len(text) > MAX_TTS_CHARS:
        await msg.reply(f"Text too long ({len(text)} chars). Max: {MAX_TTS_CHARS}")
        return

    status = await msg.answer("Generating speech...")
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
            await status.edit_text("Could not generate speech.")

    except Exception as e:
        log.error(f"handle_text: {e}")
        try:
            await status.edit_text("Processing error. Please try again.")
        except Exception:
            pass
    finally:
        cleanup(ogg_path)


# ══════════════════════════════════
# Lifecycle
# ══════════════════════════════════

async def on_shutdown():
    """Cleanup on exit — called exactly once."""
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

    # Clean temp dir
    try:
        for f in os.listdir(TEMP_DIR):
            cleanup(os.path.join(TEMP_DIR, f))
    except FileNotFoundError:
        pass


async def main():
    log.info("=" * 40)
    log.info("  Voice AI Bot v4.0 STARTED")
    log.info(f"  STT: {os.path.basename(WHISPER_BIN)}")
    log.info(f"  TTS: espeak-ng ({ESPEAK_VOICE})")
    log.info(f"  Temp: {TEMP_DIR}")
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
