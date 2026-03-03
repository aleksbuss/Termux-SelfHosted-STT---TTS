import os
import asyncio
import logging
import tempfile
import wave
from aiogram import Bot, Dispatcher, F, types
from aiogram.filters import Command

# --- НАСТРОЙКИ ---
TOKEN         = os.environ.get("TELEGRAM_BOT_TOKEN", "")
WHISPER_BIN   = os.environ.get("WHISPER_BIN", "")
WHISPER_MODEL = os.environ.get("WHISPER_MODEL", "")
PIPER_MODEL   = os.environ.get("PIPER_MODEL", "")

logging.basicConfig(level=logging.INFO)
bot = Bot(token=TOKEN)
dp  = Dispatcher()

# Piper загружается один раз при старте
_piper_voice = None

def get_piper_voice():
    global _piper_voice
    if _piper_voice is None:
        from piper.voice import PiperVoice
        logging.info(f"Загружаю Piper: {PIPER_MODEL}")
        _piper_voice = PiperVoice.load(PIPER_MODEL)
        logging.info("Piper готов")
    return _piper_voice


# --- STT: Голос -> Текст ---
async def stt_whisper(audio_ogg_path: str) -> str:
    wav_path = audio_ogg_path + ".wav"
    txt_path = wav_path + ".txt"
    try:
        proc = await asyncio.create_subprocess_exec(
            "ffmpeg", "-y", "-i", audio_ogg_path,
            "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", wav_path,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL
        )
        await proc.wait()

        proc = await asyncio.create_subprocess_exec(
            WHISPER_BIN, "-m", WHISPER_MODEL, "-f", wav_path,
            "-l", "ru", "--no-timestamps", "-t", "4", "--output-txt",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        await proc.wait()

        if os.path.isfile(txt_path):
            with open(txt_path, "r", encoding="utf-8") as f:
                return f.read().strip()
        return "Не удалось распознать текст."
    finally:
        for p in [wav_path, txt_path, audio_ogg_path]:
            if os.path.exists(p):
                os.remove(p)


# --- TTS: Текст -> Голос (через Python piper-tts, без бинарника) ---
async def tts_piper(text: str, output_ogg_path: str):
    wav_path = output_ogg_path + ".wav"
    try:
        def synthesize():
            voice = get_piper_voice()
            with wave.open(wav_path, "w") as wav_file:
                voice.synthesize(text, wav_file)

        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, synthesize)

        if not os.path.exists(wav_path) or os.path.getsize(wav_path) == 0:
            raise RuntimeError("Piper не сгенерировал аудио")

        proc = await asyncio.create_subprocess_exec(
            "ffmpeg", "-y", "-i", wav_path,
            "-c:a", "libopus", output_ogg_path,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL
        )
        await proc.wait()

        if not os.path.exists(output_ogg_path) or os.path.getsize(output_ogg_path) == 0:
            raise RuntimeError("ffmpeg не создал OGG")
    finally:
        if os.path.exists(wav_path):
            os.remove(wav_path)


# --- ОБРАБОТЧИКИ ---
@dp.message(Command("start"))
async def start_cmd(message: types.Message):
    await message.answer(
        "Привет! Я работаю на 100% локально в Termux.\n"
        "🎤 Отправь голосовое — переведу в текст.\n"
        "⌨️ Отправь текст — озвучу его."
    )


@dp.message(F.voice | F.audio)
async def handle_voice(message: types.Message):
    msg = await message.answer("⏳ Распознаю речь (локально)...")
    file = message.voice or message.audio
    file_info = await bot.get_file(file.file_id)
    with tempfile.NamedTemporaryFile(suffix=".ogg", delete=False) as tmp:
        tmp_path = tmp.name
    await bot.download_file(file_info.file_path, tmp_path)
    text = await stt_whisper(tmp_path)
    await msg.edit_text(f"📝 {text}")


@dp.message(F.text)
async def handle_text(message: types.Message):
    msg = await message.answer("⏳ Генерирую голос (локально)...")
    with tempfile.NamedTemporaryFile(suffix=".ogg", delete=False) as tmp:
        tmp_path = tmp.name
    try:
        await tts_piper(message.text, tmp_path)
        await bot.send_voice(message.chat.id, types.FSInputFile(tmp_path))
        await msg.delete()
    except Exception as e:
        logging.error(f"TTS error: {e}")
        await msg.edit_text(f"❌ Ошибка TTS: {e}")
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


async def main():
    print("✅ БОТ ЗАПУЩЕН И ГОТОВ К РАБОТЕ!")
    try:
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, get_piper_voice)
        print("✅ Piper модель загружена")
    except Exception as e:
        print(f"⚠️ Ошибка загрузки Piper: {e}")
    await dp.start_polling(bot)


if __name__ == "__main__":
    asyncio.run(main())
