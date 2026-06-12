#!/usr/bin/env python3
"""
Voice AI Bot v7.1 (Modular Edition)
STT: Whisper | TTS: Piper via proot-distro
"""

import asyncio
import logging
import sys
from aiogram import Bot
from src.bot import dp
from src.config import BOT_TOKEN
from src.database import init_db
from src.ai_engines import cleanup_processes

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s", datefmt="%H:%M:%S")
log = logging.getLogger("main")

async def main():
    if not BOT_TOKEN:
        log.error("TELEGRAM_BOT_TOKEN environment variable not set. Exiting.")
        sys.exit(1)
        
    bot = Bot(token=BOT_TOKEN)
    await init_db()
    
    try:
        log.info("Starting Voice AI Bot...")
        await dp.start_polling(bot, handle_signals=False)
    finally:
        log.info("Shutting down... Cleaning up resources.")
        cleanup_processes()
        await bot.session.close()

if __name__ == "__main__": # pragma: no cover
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log.info("Bot stopped by user")
