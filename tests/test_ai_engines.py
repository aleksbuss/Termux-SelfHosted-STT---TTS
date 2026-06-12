import pytest
import pytest_asyncio
from unittest.mock import patch, MagicMock
import os
from src.ai_engines import stt, tts, cleanup_processes, active_processes

@pytest.mark.asyncio
async def test_stt_success():
    with patch('src.ai_engines.run_proc') as mock_run_proc, \
         patch('os.path.exists', return_value=True), \
         patch('os.remove'):
        
        mock_run_proc.side_effect = [
            (0, b"", b""), # ffmpeg
            (0, b"Hello world", b"") # whisper
        ]
        
        result = await stt("dummy.ogg", "en")
        assert result == "Hello world"
        assert mock_run_proc.call_count == 2
        
        whisper_call = mock_run_proc.call_args_list[1]
        assert "-l" in whisper_call[0]
        assert "en" in whisper_call[0]

@pytest.mark.asyncio
async def test_stt_ffmpeg_fails():
    with patch('src.ai_engines.run_proc') as mock_run_proc:
        mock_run_proc.return_value = (1, b"", b"Error") # ffmpeg fails
        
        result = await stt("dummy.ogg", "en")
        assert result is None
        assert mock_run_proc.call_count == 1

@pytest.mark.asyncio
async def test_tts_success():
    with patch('src.ai_engines.run_proc') as mock_run_proc, \
         patch('os.path.exists', return_value=True), \
         patch('os.remove'):
         
        mock_run_proc.side_effect = [
            (0, b"", b""), # piper
            (0, b"", b"")  # ffmpeg
        ]
        
        result = await tts("Hello", "en")
        assert result is not None
        assert result.endswith(".ogg")
        
        piper_call = mock_run_proc.call_args_list[0]
        assert "proot-distro" in piper_call[0]
        assert piper_call[1]["stdin_data"] == b"Hello"

@pytest.mark.asyncio
async def test_tts_empty_text():
    with patch('src.ai_engines.normalize_text', return_value=""):
        result = await tts("---", "en")
        assert result is None

def test_cleanup_processes():
    proc_mock = MagicMock()
    active_processes.add(proc_mock)
    cleanup_processes()
    proc_mock.kill.assert_called_once()
    assert len(active_processes) == 0
