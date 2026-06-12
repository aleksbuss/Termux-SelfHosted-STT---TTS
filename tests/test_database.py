import pytest
import pytest_asyncio
import os
import tempfile
import aiosqlite
from src.database import init_db, get_user_lang, set_user_lang
import src.database

@pytest_asyncio.fixture(autouse=True)
async def db_setup_teardown():
    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    src.database.DB_PATH = path
    
    await init_db()
    yield
    
    if os.path.exists(path):
        os.remove(path)

@pytest.mark.asyncio
async def test_get_user_lang_default():
    lang = await get_user_lang(123)
    assert lang == "ru"

@pytest.mark.asyncio
async def test_set_user_lang():
    await set_user_lang(123, "en")
    lang = await get_user_lang(123)
    assert lang == "en"
    
    # Test update
    await set_user_lang(123, "es")
    lang = await get_user_lang(123)
    assert lang == "es"
