import pytest
import asyncio
import sys
from unittest.mock import patch, AsyncMock, MagicMock
import main

@pytest.mark.asyncio
async def test_main_no_token():
    with patch('main.BOT_TOKEN', ''), \
         patch('sys.exit', side_effect=SystemExit(1)) as mock_exit, \
         patch('main.log.error') as mock_log:
         
        with pytest.raises(SystemExit):
            await main.main()
        
        mock_log.assert_called_once()
        mock_exit.assert_called_with(1)

@pytest.mark.asyncio
async def test_main_success():
    with patch('main.BOT_TOKEN', '123:test'), \
         patch('main.init_db', new_callable=AsyncMock) as mock_init_db, \
         patch('main.dp.start_polling', new_callable=AsyncMock) as mock_start_polling, \
         patch('main.cleanup_processes') as mock_cleanup, \
         patch('main.Bot') as MockBot:
         
        mock_bot_instance = MagicMock()
        mock_bot_instance.session.close = AsyncMock()
        MockBot.return_value = mock_bot_instance

        await main.main()
        
        mock_init_db.assert_called_once()
        mock_start_polling.assert_called_once()
        mock_cleanup.assert_called_once()
        mock_bot_instance.session.close.assert_called_once()

@pytest.mark.asyncio
async def test_main_start_polling_exception():
    with patch('main.BOT_TOKEN', '123:test'), \
         patch('main.init_db', new_callable=AsyncMock), \
         patch('main.dp.start_polling', side_effect=Exception("Polling failed")), \
         patch('main.cleanup_processes') as mock_cleanup, \
         patch('main.Bot') as MockBot:
         
        mock_bot_instance = MagicMock()
        mock_bot_instance.session.close = AsyncMock()
        MockBot.return_value = mock_bot_instance

        with pytest.raises(Exception, match="Polling failed"):
            await main.main()
            
        # Ensure finally block executes
        mock_cleanup.assert_called_once()
        mock_bot_instance.session.close.assert_called_once()
