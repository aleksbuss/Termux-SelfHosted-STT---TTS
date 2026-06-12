import re
from num2words import num2words
import logging
from src.config import LANG_CONFIG

log = logging.getLogger(__name__)

def clean_text_for_piper(text: str) -> str:
    text = re.sub(r'http\S+', '', text)
    text = re.sub(r'[^\w\s\.,!\?¿¡\'"-]', '', text, flags=re.UNICODE)
    return text.strip()

def normalize_text(text: str, lang: str) -> str:
    try:
        text = clean_text_for_piper(text)
        def replace_num(match):
            try:
                # Need to cast to float then int if there are leading zeros or big nums?
                # Simple int() is fine for \d+
                return num2words(int(match.group(0)), lang=LANG_CONFIG[lang]['n2w'])
            except Exception as e:
                log.warning(f"num2words error for {match.group(0)}: {e}")
                return match.group(0)

        text = re.sub(r'\d+', replace_num, text)
    except Exception as e:
        log.warning(f"Normalization error: {e}")
    return text
