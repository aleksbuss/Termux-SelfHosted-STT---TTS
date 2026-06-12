from __future__ import annotations
import os
import asyncio
import uuid
import logging
from src.config import TEMP_DIR, TIMEOUT_SEC, LANG_CONFIG, WHISPER_BIN, WHISPER_MODEL, MODELS_DIR, PIPER_BIN
from src.utils import normalize_text

log = logging.getLogger(__name__)

whisper_lock = asyncio.Semaphore(1)
piper_lock = asyncio.Semaphore(1)
active_processes = set()

async def run_proc(*args, timeout=TIMEOUT_SEC, stdin_data=None):
    proc = None
    try:
        proc = await asyncio.create_subprocess_exec(
            *args,
            stdin=asyncio.subprocess.PIPE if stdin_data else None,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        active_processes.add(proc)
        stdout, stderr = await asyncio.wait_for(proc.communicate(input=stdin_data), timeout=timeout)
        return proc.returncode, stdout, stderr
    except asyncio.CancelledError:
        if proc:
            try: proc.kill()
            except: pass
        raise
    except Exception as e:
        if proc:
            try: proc.kill()
            except: pass
        log.error(f"Process failed: {e}")
        return -1, b"", str(e).encode()
    finally:
        if proc in active_processes:
            active_processes.remove(proc)

async def stt(ogg_path: str, lang: str) -> str | None:
    uid = str(uuid.uuid4())[:8]
    wav_path = os.path.join(TEMP_DIR, f"{uid}.wav")

    try:
        rc, _, _ = await run_proc("ffmpeg", "-y", "-i", ogg_path, "-ar", "16000", "-ac", "1", "-f", "wav", wav_path)
        if rc != 0: return None

        async with whisper_lock:
            whisper_lang = LANG_CONFIG[lang]["whisper"]
            rc, out, _ = await run_proc(WHISPER_BIN, "-m", WHISPER_MODEL, "-f", wav_path, "-l", whisper_lang, "-nt")
        
        if rc != 0: return None
        
        text = out.decode("utf-8", errors="ignore").strip()
        if not text or "[" in text or "(" in text: 
            return None
        return text
    finally:
        if os.path.exists(wav_path): os.remove(wav_path)

async def tts(text: str, lang: str) -> str | None:
    uid = str(uuid.uuid4())[:8]
    wav_path = os.path.join(TEMP_DIR, f"{uid}.wav")
    ogg_path = os.path.join(TEMP_DIR, f"{uid}.ogg")

    norm_text = normalize_text(text, lang)
    if not norm_text: return None

    model_path = os.path.join(MODELS_DIR, LANG_CONFIG[lang]["piper"])

    try:
        async with piper_lock:
            rc, out, err = await run_proc(
                "proot-distro", "login", "ubuntu", "--",
                PIPER_BIN, "--model", model_path, "--output_file", wav_path,
                stdin_data=norm_text.encode('utf-8')
            )
        
        if rc != 0: 
            log.error(f"Piper error: {err.decode('utf-8', 'ignore')}")
            return None

        rc, _, _ = await run_proc("ffmpeg", "-y", "-i", wav_path, "-c:a", "libopus", "-b:a", "64k", ogg_path)
        if rc == 0 and os.path.exists(ogg_path):
            return ogg_path
        return None
    finally:
        if os.path.exists(wav_path): os.remove(wav_path)

def cleanup_processes():
    for proc in list(active_processes):
        try: proc.kill()
        except: pass
    active_processes.clear()
