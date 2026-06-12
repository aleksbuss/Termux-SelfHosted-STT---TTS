import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from aiogram.types import Message, CallbackQuery, Voice, User

from src.bot import cmd_start, cmd_lang, process_lang_selection, handle_voice, handle_text

def create_mock_message(text=None, voice=None, audio=None):
    msg = AsyncMock()
    msg.text = text
    msg.voice = voice
    msg.audio = audio
    msg.from_user.id = 123
    msg.bot.get_file = AsyncMock()
    msg.bot.download_file = AsyncMock()
    msg.answer = AsyncMock()
    msg.answer_voice = AsyncMock()
    msg.reply = AsyncMock()
    return msg

@pytest.mark.asyncio
async def test_cmd_start():
    msg = create_mock_message()
    await cmd_start(msg)
    msg.answer.assert_called_once()
    assert "Voice AI Bot" in msg.answer.call_args[0][0]

@pytest.mark.asyncio
async def test_cmd_lang():
    msg = create_mock_message()
    with patch('src.bot.get_user_lang', return_value="ru"):
        await cmd_lang(msg)
        msg.answer.assert_called_once()

@pytest.mark.asyncio
async def test_handle_text_success():
    msg = create_mock_message(text="Hello")
    status_msg = AsyncMock()
    msg.answer.return_value = status_msg
    
    with patch('src.bot.tts', return_value="test.ogg"), \
         patch('src.bot.get_user_lang', return_value="en"), \
         patch('src.bot.os.path.exists', return_value=True), \
         patch('src.bot.os.remove'):
        
        await handle_text(msg)
        
        msg.answer.assert_called_with("⏳ Generating voice...")
        msg.answer_voice.assert_called_once()
        status_msg.delete.assert_called_once()

@pytest.mark.asyncio
async def test_handle_text_failure():
    msg = create_mock_message(text="Hello")
    status_msg = AsyncMock()
    msg.answer.return_value = status_msg
    
    with patch('src.bot.tts', return_value=None), \
         patch('src.bot.get_user_lang', return_value="en"):
        
        await handle_text(msg)
        status_msg.edit_text.assert_called_once()
        assert "Could not generate speech" in status_msg.edit_text.call_args[0][0]

@pytest.mark.asyncio
async def test_handle_voice_success():
    voice = MagicMock(spec=Voice)
    voice.duration = 10
    voice.file_id = "file123"
    msg = create_mock_message(voice=voice)
    status_msg = AsyncMock()
    msg.answer.return_value = status_msg
    msg.bot.get_file.return_value = MagicMock(file_path="voice.ogg")
    
    with patch('src.bot.stt', return_value="Recognized text"), \
         patch('src.bot.get_user_lang', return_value="en"), \
         patch('src.bot.os.path.exists', return_value=True), \
         patch('src.bot.os.remove'):
        
        await handle_voice(msg)
        
        msg.answer.assert_called_with("⏳ Processing...")
        msg.bot.get_file.assert_called_with("file123")
        msg.bot.download_file.assert_called_once()
        status_msg.edit_text.assert_called_with("Recognized text")

@pytest.mark.asyncio
async def test_process_lang_selection():
    cb = AsyncMock()
    cb.data = "lang_es"
    cb.from_user.id = 123
    cb.message.edit_text = AsyncMock()
    cb.answer = AsyncMock()
    
    with patch('src.bot.set_user_lang') as mock_set_lang:
        await process_lang_selection(cb)
        mock_set_lang.assert_called_with(123, "es")
        cb.message.edit_text.assert_called_once()
        cb.answer.assert_called_once()

from aiogram.types import Voice, Audio

@pytest.mark.asyncio
async def test_handle_voice_too_long():
    voice = MagicMock(spec=Voice)
    voice.duration = 9999
    msg = create_mock_message(voice=voice)
    await handle_voice(msg)
    msg.reply.assert_called_with("Audio is too long.")

@pytest.mark.asyncio
async def test_handle_text_too_long():
    msg = create_mock_message(text="A" * 9999)
    await handle_text(msg)
    msg.reply.assert_called_with("Text is too long.")

@pytest.mark.asyncio
async def test_handle_voice_exception():
    voice = MagicMock(spec=Voice)
    voice.duration = 10
    msg = create_mock_message(voice=voice)
    msg.bot.get_file.side_effect = Exception("Network error")
    status_msg = AsyncMock()
    msg.answer.return_value = status_msg
    with patch("src.bot.get_user_lang", return_value="en"):
        await handle_voice(msg)
        status_msg.edit_text.assert_called_with("❌ Error processing audio.")

@pytest.mark.asyncio
async def test_handle_text_exception():
    msg = create_mock_message(text="hello")
    status_msg = AsyncMock()
    msg.answer.return_value = status_msg
    with patch("src.bot.get_user_lang", return_value="en"), patch("src.bot.tts", side_effect=Exception("TTS Error")):
        await handle_text(msg)
        status_msg.edit_text.assert_called_with("❌ Error processing text.")

@pytest.mark.asyncio
async def test_handle_voice_none():
    voice = MagicMock(spec=Voice)
    voice.duration = 10
    voice.file_id = "123"
    msg = create_mock_message(voice=voice)
    status_msg = AsyncMock()
    msg.answer.return_value = status_msg
    with patch("src.bot.get_user_lang", return_value="en"), patch("src.bot.stt", return_value=None), patch("src.bot.os.path.exists", return_value=True), patch("src.bot.os.remove"):
        await handle_voice(msg)
        status_msg.edit_text.assert_called_with("❌ Speech not recognized.")

@pytest.mark.asyncio
async def test_auth_middleware_unauthorized():
    from src.bot import auth_middleware
    handler = AsyncMock()
    event = MagicMock()
    event.from_user.id = 999999999
    
    with patch("src.bot.ALLOWED_USER_IDS", [12345]):
        result = await auth_middleware(handler, event, {})
        assert result is None
        handler.assert_not_called()

@pytest.mark.asyncio
async def test_auth_middleware_authorized():
    from src.bot import auth_middleware
    handler = AsyncMock()
    event = MagicMock()
    event.from_user.id = 12345
    
    with patch("src.bot.ALLOWED_USER_IDS", [12345]):
        await auth_middleware(handler, event, {})
        handler.assert_called_once()
