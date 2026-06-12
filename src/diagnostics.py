import os
import shutil
import logging
from src.config import WHISPER_BIN, WHISPER_MODEL, PIPER_BIN, MODELS_DIR, LANG_CONFIG

log = logging.getLogger(__name__)

class EnvironmentError(Exception):
    pass

def run_diagnostics():
    log.info("Running environment diagnostics (Smoke tests)...")
    
    if not os.path.isfile(WHISPER_BIN) or not os.access(WHISPER_BIN, os.X_OK):
        raise EnvironmentError(f"Whisper binary not found or not executable: {WHISPER_BIN}. Please run install.sh again.")
    
    if not os.path.isfile(WHISPER_MODEL) or os.path.getsize(WHISPER_MODEL) < 10_000_000:
        raise EnvironmentError(f"Whisper model not found or corrupted (too small): {WHISPER_MODEL}. Please run install.sh again.")
        
    if not os.path.isfile(PIPER_BIN) or not os.access(PIPER_BIN, os.X_OK):
        raise EnvironmentError(f"Piper binary not found or not executable: {PIPER_BIN}. Please run install.sh again.")
        
    for lang, cfg in LANG_CONFIG.items():
        model_path = os.path.join(MODELS_DIR, cfg["piper"])
        if not os.path.isfile(model_path) or os.path.getsize(model_path) < 10_000_000:
            raise EnvironmentError(f"Piper model for {lang} not found or corrupted (too small): {model_path}. Please run install.sh again.")
            
    if shutil.which("ffmpeg") is None:
        raise EnvironmentError("ffmpeg is not installed. Please run install.sh again.")
        
    if shutil.which("proot-distro") is None:
        log.warning("proot-distro is not found in PATH. TTS might fail if not running on Ubuntu natively.")
        
    log.info("Diagnostics passed! Environment is healthy.")
