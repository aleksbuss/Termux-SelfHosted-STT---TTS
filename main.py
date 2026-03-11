#!/usr/bin/env python3
"""
Voice AI Bot v7.0 (Fixed & Stable)
STT: Whisper | TTS: Piper (RU, EN, ES)
Fixed: Piper stdin handling, error logging, path validation
"""
import os
import sys
import asyncio
import signal
import tempfile
import logging
import uuid
import re
import sqlite3
import shutil
from pathlib import Path
from aiogram import Bot, Dispatcher, F, types
from aiogram.types import FSInputFile, InlineKeyboardMarkup, InlineKeyboardButton
from aiogram.filters import Command
from aiogram.exceptions import TelegramAPIError
from num2words import num2words

# ─── Configuration ───
BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
WHISPER_BIN = os.environ.get("WHISPER_BIN", os.path.expanduser("~/voice-bot/whisper.cpp/build/bin/whisper-cli"))
WHISPER_MODEL = os.environ.get("WHISPER_MODEL", os.path.expanduser("~/voice-bot/whisper.cpp/models/ggml-base.bin"))
PIPER_BIN = os.environ.get("PIPER_BIN", os.path.expanduser("~/voice-bot/piper/piper"))
MODELS_DIR = os.environ.get("MODELS_DIR", os.path.expanduser("~/voice-bot/piper/models"))
TEMP_DIR = os.environ.get("TEMP_DIR", "/tmp/voice-bot")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")

# Limits & Settings
MAX_VOICE_DURATION = 300  # 5 minutes
MAX_TTS_CHARS = 1000
TIMEOUT_SEC = 120

# ─── Multilingual Config ───
LANG_CONFIG = {
    "ru": {
        "whisper": "ru",
        "piper": "ru_RU-irina-medium.onnx",
        "n2w": "ru",
        "icon": "🇷🇺",
        "name": "Русский"
    },
    "en": {
        "whisper": "en",
        "piper": "en_US-lessac-medium.onnx",
        "n2w": "en",
        "icon": "🇬🇧",
        "name": "English"
    },
    "es": {
        "whisper": "es",
        "piper": "es_ES-davefx-medium.onnx",
        "n2w": "es",
        "icon": "🇪🇸",
        "name": "Español"
    }
}

# ─── Logging Setup ───
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL),
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(os.path.expanduser("~/voice-bot/bot.log"), mode='a')
    ]
)
log = logging.getLogger("bot")

# ─── Validation on Startup ───
def validate_environment():
    """Проверка окружения при запуске"""
    errors = []
    
    if not BOT_TOKEN:
        errors.append("TELEGRAM_BOT_TOKEN not set")
    
    if not os.path.isfile(WHISPER_BIN):
        errors.append(f"Whisper binary not found: {WHISPER_BIN}")
    
    if not os.path.isfile(WHISPER_MODEL):
        errors.append(f"Whisper model not found: {WHISPER_MODEL}")
    
    if not os.path.isfile(PIPER_BIN):
        errors.append(f"Piper binary not found: {PIPER_BIN}")
    
    if not os.path.isdir(MODELS_DIR):
        errors.append(f"Models directory not found: {MODELS_DIR}")
    else:
        # Проверка наличия голосовых моделей
        for lang, config in LANG_CONFIG.items():
            model_path = os.path.join(MODELS_DIR, config["piper"])
            if not os.path.isfile(model_path):
                errors.append(f"Voice model not found: {model_path}")
            json_path = model_path + ".json"
            if not os.path.isfile(json_path):
                errors.append(f"Voice config not found: {json_path}")
    
    if errors:
        log.error("Environment validation failed:")
        for err in errors:
            log.error(f"  - {err}")
        sys.exit(1)
    
    log.info("Environment validation passed")

# Создание директорий
os.makedirs(TEMP_DIR, exist_ok=True)

# ─── SQLite Database ───
DB_PATH = os.path.expanduser("~/voice-bot/users.db")

def init_db():
    try:
        with sqlite3.connect(DB_PATH) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS users (
                    user_id INTEGER PRIMARY KEY,
                    lang TEXT DEFAULT 'ru',
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            conn.execute("""
                CREATE TABLE IF NOT EXISTS stats (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER,
                    operation TEXT,
                    success BOOLEAN,
                    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
        log.info("Database initialized")
    except Exception as e:
        log.error(f"Database initialization failed: {e}")
        raise

def get_user_lang(user_id: int) -> str:
    try:
        with sqlite3.connect(DB_PATH) as conn:
            res = conn.execute("SELECT lang FROM users WHERE user_id = ?", (user_id,)).fetchone()
            return res[0] if res else "ru"
    except Exception as e:
        log.error(f"DB error in get_user_lang: {e}")
        return "ru"

def set_user_lang(user_id: int, lang: str):
    try:
        with sqlite3.connect(DB_PATH) as conn:
            conn.execute("""
                INSERT INTO users (user_id, lang) VALUES (?, ?)
                ON CONFLICT(user_id) DO UPDATE SET lang = ?
            """, (user_id, lang, lang))
    except Exception as e:
        log.error(f"DB error in set_user_lang: {e}")

def log_stat(user_id: int, operation: str, success: bool):
    try:
        with sqlite3.connect(DB_PATH) as conn:
            conn.execute(
                "INSERT INTO stats (user_id, operation, success) VALUES (?, ?, ?)",
                (user_id, operation, success)
            )
    except Exception as e:
        log.error(f"DB error in log_stat: {e}")

# ─── Semaphores for Resource Management ───
whisper_lock = asyncio.Semaphore(1)
piper_lock = asyncio.Semaphore(1)
_active_processes = set()

# ─── Core Functions ───
def clean_text_for_piper(text: str) -> str:
    """Очистка текста для Piper TTS"""
    if not text:
        return ""
    
    # Удаление URL
    text = re.sub(r'https?://\S+|www\.\S+', '', text)
    # Удаление специальных символов, но сохранение базовой пунктуации
    text = re.sub(r'[^\w\s\.,!?;:\-\'\"()]', ' ', text, flags=re.UNICODE)
    # Удаление лишних пробелов
    text = re.sub(r'\s+', ' ', text).strip()
    
    return text

def normalize_text(text: str, lang: str) -> str:
    """Нормализация текста (числа в слова)"""
    if lang not in LANG_CONFIG:
        lang = "en"
    
    try:
        text = clean_text_for_piper(text)
        if not text:
            return ""
        
        # Преобразование чисел в слова
        def replace_num(match):
            try:
                num = int(match.group(0))
                return num2words(num, lang=LANG_CONFIG[lang]['n2w'])
            except:
                return match.group(0)
        
        text = re.sub(r'\d+', replace_num, text)
        return text
    except Exception as e:
        log.warning(f"Normalization error: {e}")
        return clean_text_for_piper(text)  # Fallback

async def run_proc(*args, timeout=TIMEOUT_SEC, stdin_data=None, **kwargs):
    """Улучшенный запуск процесса с таймаутом и обработкой ошибок"""
    proc = None
    try:
        log.debug(f"Running: {' '.join(args)}")
        
        proc = await asyncio.create_subprocess_exec(
            *args,
            stdin=asyncio.subprocess.PIPE if stdin_data else None,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            **kwargs
        )
        
        _active_processes.add(proc)
        
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(input=stdin_data),
            timeout=timeout
        )
        
        if proc.returncode != 0:
            stderr_text = stderr.decode('utf-8', 'ignore')[:500]
            log.warning(f"Process failed (code {proc.returncode}): {stderr_text}")
        
        return proc.returncode, stdout, stderr
        
    except asyncio.TimeoutError:
        log.error(f"Process timeout after {timeout}s: {' '.join(args[:3])}")
        if proc:
            try:
                proc.kill()
                await proc.wait()
            except:
                pass
        return -1, b"", b"Timeout"
        
    except Exception as e:
        log.error(f"Process error: {e}")
        if proc:
            try:
                proc.kill()
            except:
                pass
        return -1, b"", str(e).encode()
        
    finally:
        if proc in _active_processes:
            _active_processes.remove(proc)

# ─── STT Engine (Whisper) ───
async def stt(ogg_path: str, lang: str) -> str | None:
    """Speech-to-Text через Whisper"""
    uid = str(uuid.uuid4())[:8]
    wav_path = os.path.join(TEMP_DIR, f"{uid}.wav")
    
    try:
        # Конвертация OGG -> WAV
        rc, _, err = await run_proc(
            "ffmpeg", "-y", "-i", ogg_path,
            "-ar", "16000", "-ac", "1", "-f", "wav",
            wav_path
        )
        
        if rc != 0:
            log.error(f"FFmpeg conversion failed: {err.decode('utf-8', 'ignore')[:200]}")
            return None
        
        if not os.path.exists(wav_path):
            log.error("WAV file not created after ffmpeg")
            return None
        
        # Распознавание через Whisper
        async with whisper_lock:
            whisper_lang = LANG_CONFIG.get(lang, LANG_CONFIG["en"])["whisper"]
            
            rc, stdout, stderr = await run_proc(
                WHISPER_BIN,
                "-m", WHISPER_MODEL,
                "-f", wav_path,
                "-l", whisper_lang,
                "-nt",  # no timestamps
                "--no-prints"
            )
        
        if rc != 0:
            log.error(f"Whisper failed (code {rc}): {stderr.decode('utf-8', 'ignore')[:200]}")
            return None
        
        text = stdout.decode('utf-8', 'ignore').strip()
        
        # Фильтрация мусора
        if not text or text.startswith('[') or '(' in text[:10]:
            return None
        
        # Очистка от артефактов whisper
        text = re.sub(r'\[[^\]]*\]', '', text).strip()
        
        return text if text else None
        
    except Exception as e:
        log.error(f"STT exception: {e}")
        return None
        
    finally:
        if os.path.exists(wav_path):
            try:
                os.remove(wav_path)
            except:
                pass

# ─── TTS Engine (Piper) ───
async def tts(text: str, lang: str) -> str | None:
    """Text-to-Speech через Piper (ИСПРАВЛЕНО: используем файл вместо stdin)"""
    uid = str(uuid.uuid4())[:8]
    wav_path = os.path.join(TEMP_DIR, f"{uid}.wav")
    ogg_path = os.path.join(TEMP_DIR, f"{uid}.ogg")
    txt_path = os.path.join(TEMP_DIR, f"{uid}.txt")
    
    try:
        # Нормализация текста
        norm_text = normalize_text(text, lang)
        if not norm_text:
            log.warning("Text empty after normalization")
            return None
        
        if len(norm_text) > MAX_TTS_CHARS:
            norm_text = norm_text[:MAX_TTS_CHARS]
            log.info(f"Text truncated to {MAX_TTS_CHARS} chars")
        
        # Проверка модели
        model_file = LANG_CONFIG.get(lang, LANG_CONFIG["en"])["piper"]
        model_path = os.path.join(MODELS_DIR, model_file)
        
        if not os.path.isfile(model_path):
            log.error(f"Model not found: {model_path}")
            return None
        
        # Запись текста во временный файл (ИСПРАВЛЕНИЕ!)
        try:
            with open(txt_path, 'w', encoding='utf-8') as f:
                f.write(norm_text)
        except Exception as e:
            log.error(f"Failed to write temp text file: {e}")
            return None
        
        # Запуск Piper с --file вместо stdin
        async with piper_lock:
            rc, stdout, stderr = await run_proc(
                PIPER_BIN,
                "--model", model_path,
                "--file", txt_path,  # ИСПРАВЛЕНО: читаем из файла
                "--output_file", wav_path
            )
        
        # Удаление временного текстового файла сразу после использования
        try:
            os.remove(txt_path)
        except:
            pass
        
        if rc != 0:
            err_text = stderr.decode('utf-8', 'ignore')[:500]
            log.error(f"Piper failed (code {rc}): {err_text}")
            return None
        
        if not os.path.exists(wav_path):
            log.error("Piper did not create WAV file")
            return None
        
        # Конвертация WAV -> OGG (Opus)
        rc, _, err = await run_proc(
            "ffmpeg", "-y", "-i", wav_path,
            "-c:a", "libopus",
            "-b:a", "64k",
            "-application", "voip",
            ogg_path
        )
        
        if rc != 0:
            log.error(f"FFmpeg OGG conversion failed: {err.decode('utf-8', 'ignore')[:200]}")
            return None
        
        if os.path.exists(ogg_path) and os.path.getsize(ogg_path) > 0:
            return ogg_path
        else:
            log.error("OGG file not created or empty")
            return None
            
    except Exception as e:
        log.error(f"TTS exception: {e}")
        return None
        
    finally:
        # Очистка временных файлов
        for f in [wav_path, txt_path]:
            if f and os.path.exists(f):
                try:
                    os.remove(f)
                except:
                    pass

# ─── Telegram Handlers ───
def get_lang_keyboard():
    """Клавиатура выбора языка"""
    buttons = [
        [InlineKeyboardButton(text=f"{v['icon']} {v['name']}", callback_data=f"lang_{k}")]
        for k, v in LANG_CONFIG.items()
    ]
    return InlineKeyboardMarkup(inline_keyboard=buttons)

@dp.message(Command("lang"))
async def cmd_lang(msg: types.Message):
    """Команда смены языка"""
    try:
        curr_lang = get_user_lang(msg.from_user.id)
        await msg.answer(
            f"🌐 Текущий язык / Current language: {LANG_CONFIG[curr_lang]['icon']}\n\n"
            f"Выберите язык / Choose language:",
            reply_markup=get_lang_keyboard()
        )
    except Exception as e:
        log.error(f"Error in cmd_lang: {e}")
        await msg.answer("❌ Error showing language menu")

@dp.callback_query(F.data.startswith("lang_"))
async def process_lang_selection(callback: types.CallbackQuery):
    """Обработка выбора языка"""
    try:
        lang_code = callback.data.split("_")[1]
        if lang_code not in LANG_CONFIG:
            await callback.answer("Invalid language")
            return
        
        set_user_lang(callback.from_user.id, lang_code)
        
        await callback.message.edit_text(
            f"✅ Язык изменен на / Language set to:\n"
            f"{LANG_CONFIG[lang_code]['icon']} {LANG_CONFIG[lang_code]['name']}"
        )
        await callback.answer()
        
    except Exception as e:
        log.error(f"Error in process_lang_selection: {e}")
        await callback.answer("Error")

@dp.message(Command("start", "help"))
async def cmd_start(msg: types.Message):
    """Стартовая команда"""
    try:
        await msg.answer(
            "🎙 <b>Voice AI Bot</b> (Offline)\n\n"
            "Отправьте:\n"
            "• <b>Голосовое сообщение</b> → получите текст\n"
            "• <b>Текст</b> → получите голосовое\n\n"
            "Команды:\n"
            "/lang — сменить язык (RU/EN/ES)\n"
            "/help — эта справка\n\n"
            "⚡️ 100% офлайн, приватно и быстро!",
            parse_mode="HTML"
        )
    except Exception as e:
        log.error(f"Error in cmd_start: {e}")

@dp.message(Command("status"))
async def cmd_status(msg: types.Message):
    """Команда статуса (для отладки)"""
    try:
        lang = get_user_lang(msg.from_user.id)
        
        # Проверка компонентов
        checks = {
            "Whisper": os.path.isfile(WHISPER_BIN),
            "Whisper Model": os.path.isfile(WHISPER_MODEL),
            "Piper": os.path.isfile(PIPER_BIN),
            "Voice Models": all(
                os.path.isfile(os.path.join(MODELS_DIR, cfg["piper"]))
                for cfg in LANG_CONFIG.values()
            )
        }
        
        status_text = "📊 <b>System Status</b>\n\n"
        status_text += f"Language: {LANG_CONFIG[lang]['icon']} {LANG_CONFIG[lang]['name']}\n\n"
        status_text += "Components:\n"
        for name, ok in checks.items():
            status_text += f"{'✅' if ok else '❌'} {name}\n"
        
        await msg.answer(status_text, parse_mode="HTML")
        
    except Exception as e:
        log.error(f"Error in cmd_status: {e}")

@dp.message(F.voice | F.audio)
async def handle_voice(msg: types.Message):
    """Обработка голосовых сообщений"""
    user_id = msg.from_user.id
    lang = get_user_lang(user_id)
    
    # Проверка длительности
    duration = 0
    if msg.voice:
        duration = msg.voice.duration or 0
    elif msg.audio:
        duration = msg.audio.duration or 0
    
    if duration > MAX_VOICE_DURATION:
        await msg.reply(f"⚠️ Аудио слишком длинное. Максимум {MAX_VOICE_DURATION} секунд.")
        return
    
    status_msg = None
    ogg_path = None
    
    try:
        status_msg = await msg.answer("⏳ Распознаю речь...")
        
        # Скачивание файла
        uid = str(uuid.uuid4())[:8]
        ogg_path = os.path.join(TEMP_DIR, f"{uid}_in.ogg")
        
        file_id = msg.voice.file_id if msg.voice else msg.audio.file_id
        tg_file = await bot.get_file(file_id)
        
        await bot.download_file(tg_file.file_path, ogg_path)
        
        if not os.path.exists(ogg_path):
            raise Exception("Download failed")
        
        # Распознавание
        text = await stt(ogg_path, lang)
        
        if text:
            await status_msg.edit_text(f"📝 {text}")
            log_stat(user_id, "stt", True)
        else:
            await status_msg.edit_text("❌ Не удалось распознать речь.\nПопробуйте говорить чётче.")
            log_stat(user_id, "stt", False)
            
    except TelegramAPIError as e:
        log.error(f"Telegram API error in handle_voice: {e}")
        if status_msg:
            await status_msg.edit_text("❌ Ошибка Telegram API")
    except Exception as e:
        log.error(f"Error in handle_voice: {e}")
        if status_msg:
            await status_msg.edit_text("❌ Ошибка обработки аудио")
    finally:
        if ogg_path and os.path.exists(ogg_path):
            try:
                os.remove(ogg_path)
            except:
                pass

@dp.message(F.text)
async def handle_text(msg: types.Message):
    """Обработка текстовых сообщений (TTS)"""
    user_id = msg.from_user.id
    lang = get_user_lang(user_id)
    
    # Проверка длины
    if len(msg.text) > MAX_TTS_CHARS:
        await msg.reply(f"⚠️ Текст слишком длинный. Максимум {MAX_TTS_CHARS} символов.")
        return
    
    # Проверка на команду
    if msg.text.startswith('/'):
        return
    
    status_msg = None
    ogg_path = None
    
    try:
        status_msg = await msg.answer("🔊 Генерирую голос...")
        
        # Генерация голоса
        ogg_path = await tts(msg.text, lang)
        
        if ogg_path and os.path.exists(ogg_path):
            # Отправка голосового
            await msg.answer_voice(FSInputFile(ogg_path))
            await status_msg.delete()
            log_stat(user_id, "tts", True)
        else:
            await status_msg.edit_text(
                "❌ Не удалось сгенерировать речь.\n"
                "Возможные причины:\n"
                "• Неустановленные компоненты (/status)\n"
                "• Неподдерживаемые символы\n"
                "• Ошибка TTS движка"
            )
            log_stat(user_id, "tts", False)
            
    except TelegramAPIError as e:
        log.error(f"Telegram API error in handle_text: {e}")
        if status_msg:
            await status_msg.edit_text("❌ Ошибка отправки голоса")
    except Exception as e:
        log.error(f"Error in handle_text: {e}")
        if status_msg:
            await status_msg.edit_text("❌ Ошибка генерации речи")
    finally:
        if ogg_path and os.path.exists(ogg_path):
            try:
                os.remove(ogg_path)
            except:
                pass

@dp.errors()
async def error_handler(event: types.ErrorEvent):
    """Глобальный обработчик ошибок"""
    log.error(f"Update handling error: {event.exception}")
    return True

# ─── Lifecycle ───
async def main():
    """Главная функция"""
    log.info("=" * 50)
    log.info("Voice AI Bot v7.0 Starting...")
    log.info(f"Whisper: {WHISPER_BIN}")
    log.info(f"Piper: {PIPER_BIN}")
    log.info(f"Models: {MODELS_DIR}")
    log.info("=" * 50)
    
    # Валидация окружения
    validate_environment()
    
    # Инициализация БД
    init_db()
    
    # Запуск бота
    try:
        await dp.start_polling(bot, handle_signals=False)
    finally:
        log.info("Shutting down...")

def signal_handler(sig, frame):
    """Обработчик сигналов"""
    log.info(f"Received signal {sig}, shutting down...")
    sys.exit(0)

if __name__ == "__main__":
    # Настройка обработчиков сигналов
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    # Запуск
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log.info("Interrupted by user")
    except Exception as e:
        log.error(f"Fatal error: {e}")
        sys.exit(1)
