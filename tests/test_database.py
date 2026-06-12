import pytest
import pytest_asyncio
import os
import aiosqlite
from src.database import init_db, get_user_lang, set_user_lang
import src.config

# Override DB path for tests
TEST_DB = "test_users.db"
src.config.DB_PATH = TEST_DB

@pytest_asyncio.fixture(autouse=True)
async def db_setup_teardown():
    # Setup
    if os.path.exists(TEST_DB):
        os.remove(TEST_DB)
    await init_db()
    yield
    # Teardown
    if os.path.exists(TEST_DB):
        os.remove(TEST_DB)

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
