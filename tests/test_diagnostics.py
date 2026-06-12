import pytest
from unittest.mock import patch
from src.diagnostics import run_diagnostics, EnvironmentError

def test_run_diagnostics_success():
    with patch("os.path.isfile", return_value=True), \
         patch("os.access", return_value=True), \
         patch("shutil.which", return_value="path/to/bin"), \
         patch("src.diagnostics.log.warning") as mock_warn:
        run_diagnostics()

def test_run_diagnostics_whisper_missing():
    with patch("os.path.isfile", return_value=False):
        with pytest.raises(EnvironmentError, match="Whisper binary"):
            run_diagnostics()

def test_run_diagnostics_whisper_model_missing():
    def mock_isfile(path):
        return not path.endswith("ggml-base.bin")
    with patch("os.path.isfile", side_effect=mock_isfile), patch("os.access", return_value=True):
        with pytest.raises(EnvironmentError, match="Whisper model not found"):
            run_diagnostics()

def test_run_diagnostics_piper_missing():
    def mock_isfile(path):
        return not path.endswith("piper")
    with patch("os.path.isfile", side_effect=mock_isfile), patch("os.access", return_value=True):
        with pytest.raises(EnvironmentError, match="Piper binary not found"):
            run_diagnostics()

def test_run_diagnostics_piper_model_missing():
    def mock_isfile(path):
        return not path.endswith(".onnx")
    with patch("os.path.isfile", side_effect=mock_isfile), patch("os.access", return_value=True):
        with pytest.raises(EnvironmentError, match="Piper model for"):
            run_diagnostics()

def test_run_diagnostics_ffmpeg_missing():
    with patch("os.path.isfile", return_value=True), patch("os.access", return_value=True), patch("shutil.which", return_value=None):
        with pytest.raises(EnvironmentError, match="ffmpeg is not installed"):
            run_diagnostics()

def test_run_diagnostics_proot_warning():
    def mock_which(cmd):
        return None if cmd == "proot-distro" else "path"
    with patch("os.path.isfile", return_value=True), patch("os.access", return_value=True), patch("shutil.which", side_effect=mock_which), patch("src.diagnostics.log.warning") as mock_warn:
        run_diagnostics()
        mock_warn.assert_called_once()
