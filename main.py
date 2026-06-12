#!/usr/bin/env python3
"""
Voice AI Bot v7.1 (Modular Edition)
STT: Whisper | TTS: Piper via proot-distro
"""

import asyncio
import logging
import sys
from src.bot import dp, bot
from src.database import init_db
from src.ai_engines import cleanup_processes

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s", datefmt="%H:%M:%S")
log = logging.getLogger("main")

async def main():
    if not bot.token:
        log.error("TELEGRAM_BOT_TOKEN environment variable not set. Exiting.")
        sys.exit(1)
        
    await init_db()
    
    try:
        log.info("Starting Voice AI Bot...")
        await dp.start_polling(bot, handle_signals=False)
    finally:
        log.info("Shutting down... Cleaning up resources.")
        cleanup_processes()
        await bot.session.close()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log.info("Stopped by user.")
