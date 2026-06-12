import os

BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")

# Security: Comma-separated list of Telegram user IDs allowed to use the bot
_allowed_users_str = os.getenv("ALLOWED_USER_IDS", "")
ALLOWED_USER_IDS = [int(x.strip()) for x in _allowed_users_str.split(",") if x.strip().isdigit()]

WHISPER_BIN = os.environ.get("WHISPER_BIN", os.path.expanduser("~/voice-bot/whisper.cpp/build/bin/whisper-cli"))
WHISPER_MODEL = os.environ.get("WHISPER_MODEL", os.path.expanduser("~/voice-bot/whisper.cpp/models/ggml-base.bin"))
PIPER_BIN = os.environ.get("PIPER_BIN", os.path.expanduser("~/voice-bot/piper/piper"))
MODELS_DIR = os.environ.get("MODELS_DIR", os.path.expanduser("~/voice-bot/piper/models"))

MAX_VOICE_DURATION = 300
MAX_TTS_CHARS = 1000
TIMEOUT_SEC = 120

TEMP_DIR = os.path.expanduser("~/voice-bot/tmp")
os.makedirs(TEMP_DIR, exist_ok=True)
DB_PATH = os.path.expanduser("~/voice-bot/users.db")

LANG_CONFIG = {
    "ru": {"whisper": "ru", "piper": "ru_RU-irina-medium.onnx", "n2w": "ru", "icon": "🇷🇺", "name": "Русский"},
    "en": {"whisper": "en", "piper": "en_US-lessac-medium.onnx", "n2w": "en", "icon": "🇬🇧", "name": "English"},
    "es": {"whisper": "es", "piper": "es_ES-davefx-medium.onnx", "n2w": "es", "icon": "🇪🇸", "name": "Español"}
}
