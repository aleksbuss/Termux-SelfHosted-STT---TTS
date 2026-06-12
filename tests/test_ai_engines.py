import pytest
from unittest.mock import patch, MagicMock, AsyncMock
import os
import asyncio
from src.ai_engines import stt, tts, cleanup_processes, active_processes
import src.ai_engines

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
    with patch('src.ai_engines.run_proc') as mock_run_proc, \
         patch('os.path.exists', return_value=True), \
         patch('os.remove'):
        mock_run_proc.return_value = (1, b"", b"Error") # ffmpeg fails
        
        result = await stt("dummy.ogg", "en")
        assert result is None
        assert mock_run_proc.call_count == 1

@pytest.mark.asyncio
async def test_stt_whisper_fails():
    with patch('src.ai_engines.run_proc') as mock_run_proc, \
         patch('os.path.exists', return_value=True), \
         patch('os.remove'):
        mock_run_proc.side_effect = [
            (0, b"", b""), # ffmpeg
            (1, b"", b"Error") # whisper fails
        ]
        
        result = await stt("dummy.ogg", "en")
        assert result is None

@pytest.mark.asyncio
async def test_stt_brackets():
    with patch('src.ai_engines.run_proc') as mock_run_proc, \
         patch('os.path.exists', return_value=True), \
         patch('os.remove'):
        mock_run_proc.side_effect = [
            (0, b"", b""), # ffmpeg
            (0, b"(music playing)", b"") # whisper hallucination
        ]
        
        result = await stt("dummy.ogg", "en")
        assert result is None

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

@pytest.mark.asyncio
async def test_tts_piper_fails():
    with patch('src.ai_engines.run_proc') as mock_run_proc, \
         patch('os.path.exists', return_value=True), \
         patch('os.remove'):
        mock_run_proc.return_value = (-1, b"", b"Error")
        result = await tts("hello", "en")
        assert result is None

@pytest.mark.asyncio
async def test_tts_ffmpeg_fails():
    with patch('src.ai_engines.run_proc') as mock_run_proc, \
         patch('os.path.exists', return_value=True), \
         patch('os.remove'):
        mock_run_proc.side_effect = [
            (0, b"", b""), # piper
            (-1, b"", b"Error") # ffmpeg fails
        ]
        result = await tts("hello", "en")
        assert result is None

@pytest.mark.asyncio
async def test_run_proc():
    with patch('asyncio.create_subprocess_exec') as mock_exec:
        proc_mock = AsyncMock()
        proc_mock.returncode = 0
        proc_mock.communicate.return_value = (b"stdout", b"stderr")
        mock_exec.return_value = proc_mock
        
        rc, out, err = await src.ai_engines.run_proc("ls", "-la", stdin_data=b"input")
        
        assert rc == 0
        assert out == b"stdout"
        assert err == b"stderr"
        mock_exec.assert_called_once()
        proc_mock.communicate.assert_called_with(input=b"input")

@pytest.mark.asyncio
async def test_run_proc_cancelled():
    with patch('asyncio.create_subprocess_exec') as mock_exec:
        proc_mock = AsyncMock()
        proc_mock.communicate.side_effect = asyncio.CancelledError()
        mock_exec.return_value = proc_mock
        
        with pytest.raises(asyncio.CancelledError):
            await src.ai_engines.run_proc("ls")
            
        proc_mock.kill.assert_called_once()

@pytest.mark.asyncio
async def test_run_proc_exception():
    with patch('asyncio.create_subprocess_exec', side_effect=Exception("Exec failed")):
        rc, out, err = await src.ai_engines.run_proc("ls")
        assert rc == -1
        assert b"Exec failed" in err

def test_cleanup_processes():
    proc_mock = MagicMock()
    active_processes.add(proc_mock)
    cleanup_processes()
    proc_mock.kill.assert_called_once()
    assert len(active_processes) == 0

def test_cleanup_processes_exception():
    proc_mock = MagicMock()
    proc_mock.kill.side_effect = Exception("Kill failed")
    active_processes.add(proc_mock)
    cleanup_processes()
    # It should not throw, and should still clear the list
    assert len(active_processes) == 0
