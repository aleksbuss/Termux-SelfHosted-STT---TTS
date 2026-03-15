#!/bin/bash
# ============================================================
# Termux Voice AI Bot — Installer v7.1 (Ultimate Android Fix)
# STT: Whisper | TTS: Piper (RU, EN, ES) | 100% Offline
# ============================================================

cd "$HOME" 2>/dev/null || cd /data/data/com.termux/files/home
PROJECT_DIR="$HOME/voice-bot"

ok()   { echo "[OK] $1"; }
fail() { echo "[ERROR] $1"; exit 1; }
warn() { echo "[WARN] $1"; }

echo "=========================================="
echo "  VOICE AI BOT v7.1 (Multi-Lang Premium)"
echo "  Architecture Fix: Android Bionic -> Glibc"
echo "=========================================="

pkill -f "main\.py" 2>/dev/null || true
sleep 1

# Чтение токена
echo -n "Telegram bot token (from @BotFather): "
read BOT_TOKEN < /dev/tty 2>/dev/null || read BOT_TOKEN

if [ -z "$BOT_TOKEN" ]; then fail "Token required!"; fi
echo "$BOT_TOKEN" | grep -qE '^[0-9]+:[A-Za-z0-9_-]+$' || fail "Invalid token format!"
ok "Token accepted"

echo "-- Step 1: System packages --"
pkg update -y; pkg upgrade -y
# ДОБАВЛЕН rust ДЛЯ КОМПИЛЯЦИИ БИБЛИОТЕК PYTHON (pydantic-core)
pkg install -y ca-certificates python ffmpeg git curl clang make cmake tar gzip sqlite proot-distro rust || fail "pkg install failed"

echo "-- Step 2: Whisper STT (Native Bionic) --"
mkdir -p "$PROJECT_DIR" && cd "$PROJECT_DIR"

if [ ! -f "whisper.cpp/build/bin/whisper-cli" ]; then
    git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git || fail "Git clone failed"
    cd whisper.cpp && mkdir -p build && cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release || fail "CMake config failed"
    cmake --build . --config Release -j"$(nproc 2>/dev/null || echo 2)" || fail "CMake build failed"
    cd "$PROJECT_DIR"
fi

if [ ! -f "whisper.cpp/models/ggml-base.bin" ]; then
    echo "Downloading Whisper model (~142 MB)..."
    curl -sSfL "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin" -o "whisper.cpp/models/ggml-base.bin" || fail "Whisper model download failed"
fi

echo "-- Step 3: Ubuntu Subsystem (Glibc Fix for Piper) --"
if [ ! -d "$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu" ]; then
    echo "Installing lightweight Ubuntu container..."
    proot-distro install ubuntu || fail "Ubuntu install failed"
fi
echo "Configuring Ubuntu libs for AI runtime..."
proot-distro login ubuntu -- bash -c "apt-get update && apt-get install -y libgomp1 libatomic1" || warn "Apt install warnings"

echo "-- Step 4: Piper TTS (3 Premium Models) --"
cd "$PROJECT_DIR"
mkdir -p piper/models
mkdir -p tmp

if [ ! -f "piper/piper" ]; then
    echo "Downloading Piper engine (ARM64)..."
    curl -sSfL "https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_linux_aarch64.tar.gz" -o piper.tar.gz || fail "Piper download failed"
    tar -xf piper.tar.gz || fail "Piper extraction failed"
    rm -f piper.tar.gz
fi

BASE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main"
MODELS=(
    "ru/ru_RU/irina/medium/ru_RU-irina-medium.onnx"
    "en/en_US/lessac/medium/en_US-lessac-medium.onnx"
    "es/es_ES/davefx/medium/es_ES-davefx-medium.onnx"
)

for model_path in "${MODELS[@]}"; do
    FILE_NAME=$(basename "$model_path")
    if [ ! -f "piper/models/$FILE_NAME" ]; then
        echo "Downloading voice model: $FILE_NAME ..."
        curl -sSfL "$BASE_URL/$model_path" -o "piper/models/$FILE_NAME" || fail "Failed to download $FILE_NAME"
        curl -sSfL "$BASE_URL/${model_path}.json" -o "piper/models/${FILE_NAME}.json" || fail "Failed to download JSON"
    fi
done
ok "Piper TTS ready"

echo "-- Step 5: Python Setup --"
cd "$PROJECT_DIR"
rm -rf venv; python -m venv venv || fail "Venv failed"
source venv/bin/activate
# === ВОТ ЭТА ВАЖНАЯ СТРОЧКА ВЕРНУЛАСЬ НА МЕСТО ===
export ANDROID_API_LEVEL=$(getprop ro.build.version.sdk 2>/dev/null || echo 24)
pip install --upgrade pip
pip install aiogram aiohttp num2words || fail "pip install failed"
deactivate

echo "-- Step 6: Finalizing --"
echo "Downloading main.py from repository..."
curl -sSfL "https://raw.githubusercontent.com/aleksbuss/Termux-SelfHosted-STT---TTS/main/main.py" -o main.py || fail "Failed to download main.py"

cat > .env << ENVEOF
export TELEGRAM_BOT_TOKEN="$BOT_TOKEN"
export WHISPER_BIN="$PROJECT_DIR/whisper.cpp/build/bin/whisper-cli"
export WHISPER_MODEL="$PROJECT_DIR/whisper.cpp/models/ggml-base.bin"
export PIPER_BIN="$PROJECT_DIR/piper/piper"
export MODELS_DIR="$PROJECT_DIR/piper/models"
ENVEOF
chmod 600 .env

cat > start_bot.sh << 'STARTEOF'
#!/bin/bash
cd ~/voice-bot
pkill -f "main\.py" 2>/dev/null || true
source .env
source venv/bin/activate
exec python main.py
STARTEOF
chmod +x start_bot.sh

cat > stop_bot.sh << 'STOPEOF'
#!/bin/bash
pkill -f "main\.py" 2>/dev/null || true
STOPEOF
chmod +x stop_bot.sh

if [ -f ~/.bashrc ]; then grep -v 'voice-bot' ~/.bashrc > ~/.bashrc.tmp && mv ~/.bashrc.tmp ~/.bashrc; fi
cat >> ~/.bashrc << 'BASHEOF'
if [ -f ~/voice-bot/start_bot.sh ] && ! pgrep -f "voice-bot.*main\.py" > /dev/null 2>&1; then
    nohup ~/voice-bot/start_bot.sh > ~/voice-bot/bot.log 2>&1 &
fi
BASHEOF

echo "INSTALLATION COMPLETE! Starting bot..."
nohup ~/voice-bot/start_bot.sh > ~/voice-bot/bot.log 2>&1 &
