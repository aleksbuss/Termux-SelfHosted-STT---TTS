import pytest
from src.utils import clean_text_for_piper, normalize_text

def test_clean_text_for_piper():
    # Test removing URLs
    assert clean_text_for_piper("Check out https://google.com and http://example.org") == "Check out  and"
    
    # Test keeping valid punctuation
    assert clean_text_for_piper("Hello, world! What's up?") == "Hello, world! What's up?"
    
    # Test removing invalid symbols (like emojis, brackets)
    assert clean_text_for_piper("Hello [world] 🚀!") == "Hello world !"
    
    # Test unicode support (Russian/Spanish)
    assert clean_text_for_piper("Привет, мир!") == "Привет, мир!"
    assert clean_text_for_piper("¿Cómo estás?") == "¿Cómo estás?"

def test_normalize_text():
    # Test english numbers
    assert normalize_text("I have 2 apples", "en") == "I have two apples"
    assert normalize_text("Number 123", "en") == "Number one hundred and twenty-three"
    
    # Test russian numbers
    assert normalize_text("У меня 5 яблок", "ru") == "У меня пять яблок"
    
    # Test spanish numbers
    assert normalize_text("Tengo 2 gatos", "es") == "Tengo dos gatos"

    # Test edge case: huge number (fallback to raw string if num2words fails, though it shouldn't fail easily)
    # 999999 is valid
    assert "девяносто" in normalize_text("99", "ru")
    
    # Test invalid language fallback (if dictionary doesn't exist, it should raise or log, returning original number)
    # but since our LANG_CONFIG has en/ru/es, we only test those.

from unittest.mock import patch
def test_normalize_text_exceptions():
    with patch("src.utils.num2words", side_effect=Exception("mocked error")):
        assert normalize_text("123", "en") == "123"
    with patch("src.utils.re.sub", side_effect=Exception("mocked error")):
        assert normalize_text("123", "en") == "123"
