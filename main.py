import os, asyncio, logging, tempfile
from aiogram import Bot, Dispatcher, F, types
from aiogram.filters import Command

# --- НАСТРОЙКИ ---
TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
WHISPER_BIN = os.environ.get("WHISPER_BIN", "")
WHISPER_MODEL = os.environ.get("WHISPER_MODEL", "")
PIPER_BIN = os.environ.get("PIPER_BIN", "")
PIPER_MODEL = os.environ.get("PIPER_MODEL", "")

logging.basicConfig(level=logging.INFO)
bot = Bot(token=TOKEN)
dp = Dispatcher()

# --- ФУНКЦИИ ---
async def stt_whisper(audio_ogg_path: str) -> str:
    """Голос -> Текст (Whisper)"""
    wav_path = audio_ogg_path + ".wav"
    txt_path = wav_path + ".txt"
    try:
        # Конвертируем OGG в WAV 16kHz
        proc = await asyncio.create_subprocess_exec("ffmpeg", "-y", "-i", audio_ogg_path, "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", wav_path, stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
        await proc.wait()
        
        # Распознаем текст
        proc = await asyncio.create_subprocess_exec(WHISPER_BIN, "-m", WHISPER_MODEL, "-f", wav_path, "-l", "ru", "--no-timestamps", "-t", "4", "--output-txt", stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        await proc.wait()
        
        if os.path.isfile(txt_path):
            with open(txt_path, "r", encoding="utf-8") as f:
                return f.read().strip()
        return "Не удалось распознать текст."
    finally:
        for p in [wav_path, txt_path, audio_ogg_path]:
            if os.path.exists(p): os.remove(p)

async def tts_piper(text: str, output_ogg_path: str):
    """Текст -> Голос (Piper)"""
    wav_path = output_ogg_path + ".wav"
    try:
        # Генерируем голос в WAV
        cmd = f"echo '{text}' | {PIPER_BIN} -m {PIPER_MODEL} -f {wav_path}"
        proc = await asyncio.create_subprocess_shell(cmd, stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
        await proc.wait()
        
        # Конвертируем WAV в OGG (формат голосовых Telegram)
        proc = await asyncio.create_subprocess_exec("ffmpeg", "-y", "-i", wav_path, "-c:a", "libopus", output_ogg_path, stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
        await proc.wait()
    finally:
        if os.path.exists(wav_path): os.remove(wav_path)

# --- ОБРАБОТЧИКИ ---
@dp.message(Command("start"))
async def start_cmd(message: types.Message):
    await message.answer("Привет! Я работаю на 100% локально в Termux.\n🎤 Отправь голосовое — я переведу его в текст.\n⌨️ Отправь текст — я озвучу его.")

@dp.message(F.voice | F.audio)
async def handle_voice(message: types.Message):
    msg = await message.answer("⏳ Распознаю речь (локально)...")
    file_info = await bot.get_file(message.voice.file_id)
    with tempfile.NamedTemporaryFile(suffix=".ogg", delete=False) as tmp:
        await bot.download_file(file_info.file_path, tmp.name)
        text = await stt_whisper(tmp.name)
        await msg.edit_text(f"📝 {text}")

@dp.message(F.text)
async def handle_text(message: types.Message):
    msg = await message.answer("⏳ Генерирую голос (локально)...")
    with tempfile.NamedTemporaryFile(suffix=".ogg", delete=False) as tmp:
        await tts_piper(message.text, tmp.name)
        await bot.send_voice(message.chat.id, types.FSInputFile(tmp.name))
        await msg.delete()
        os.remove(tmp.name)

async def main():
    print("✅ БОТ ЗАПУЩЕН И ГОТОВ К РАБОТЕ!")
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
