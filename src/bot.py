import os
import uuid
import logging
from aiogram import Bot, Dispatcher, F, types
from aiogram.types import FSInputFile, InlineKeyboardMarkup, InlineKeyboardButton
from aiogram.filters import Command
from src.config import BOT_TOKEN, MAX_VOICE_DURATION, MAX_TTS_CHARS, TEMP_DIR, LANG_CONFIG, ALLOWED_USER_IDS
from src.database import get_user_lang, set_user_lang
from src.ai_engines import stt, tts

log = logging.getLogger(__name__)

dp = Dispatcher()

@dp.message.outer_middleware()
async def auth_middleware(handler, event, data):
    user_id = event.from_user.id
    if ALLOWED_USER_IDS and user_id not in ALLOWED_USER_IDS:
        return # Ignore unauthorized users completely
    return await handler(event, data)

def get_lang_keyboard():
    buttons = [
        [InlineKeyboardButton(text=f"{v['icon']} {v['name']}", callback_data=f"lang_{k}")] 
        for k, v in LANG_CONFIG.items()
    ]
    return InlineKeyboardMarkup(inline_keyboard=buttons)

@dp.message(Command("lang"))
async def cmd_lang(msg: types.Message):
    curr_lang = await get_user_lang(msg.from_user.id)
    await msg.answer(
        f"Текущий язык / Current language: {LANG_CONFIG[curr_lang]['icon']}\nВыберите язык / Choose language:",
        reply_markup=get_lang_keyboard()
    )

@dp.callback_query(F.data.startswith("lang_"))
async def process_lang_selection(callback: types.CallbackQuery):
    lang_code = callback.data.split("_")[1]
    await set_user_lang(callback.from_user.id, lang_code)
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

    lang = await get_user_lang(msg.from_user.id)
    status = await msg.answer("⏳ Processing...")
    
    uid = str(uuid.uuid4())[:8]
    ogg_path = os.path.join(TEMP_DIR, f"{uid}_in.ogg")

    try:
        file_id = msg.voice.file_id if msg.voice else msg.audio.file_id
        tg_file = await msg.bot.get_file(file_id)
        await msg.bot.download_file(tg_file.file_path, ogg_path)

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

    lang = await get_user_lang(msg.from_user.id)
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
