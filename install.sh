#!/bin/bash
# ============================================================
# Termux Voice AI Bot — Installer v5.0 (Premium Voice)
# STT: whisper.cpp | TTS: Piper (Irina) | 100% local
# Open Source Edition
# ============================================================

cd "$HOME" 2>/dev/null || cd /data/data/com.termux/files/home
PROJECT_DIR="$HOME/voice-bot"

ok()   { echo "[OK] $1"; }
fail() { echo "[ERROR] $1"; exit 1; }
warn() { echo "[WARN] $1"; }

echo ""
echo "=========================================="
echo "  VOICE AI BOT for Termux v5.0 (Premium)"
echo "  STT: whisper.cpp | TTS: Piper (Irina)"
echo "  100% Offline | Zero Cloud"
echo "=========================================="

# Убиваем старые процессы
pkill -f "main\.py" 2>/dev/null || true
sleep 1

# ==========================================
# МАГИЯ ДЛЯ ВВОДА ТОКЕНА ПРИ curl | bash
# ==========================================
echo ""
echo -n "Telegram bot token (from @BotFather): "
# Читаем напрямую с терминала, игнорируя пайп curl
read BOT_TOKEN < /dev/tty 2>/dev/null || read BOT_TOKEN

if [ -z "$BOT_TOKEN" ]; then
    echo ""
    fail "Could not read token. Installation aborted."
fi

echo "$BOT_TOKEN" | grep -qE '^[0-9]+:[A-Za-z0-9_-]+$' || fail "Invalid token format!"
ok "Token accepted"

# ══════════════════════════════════
# Step 1: System packages
# ══════════════════════════════════
echo ""
echo "-- Step 1/5: System packages --"
pkg update -y || warn "pkg update had warnings"
pkg upgrade -y || warn "pkg upgrade had warnings"
pkg install -y python ffmpeg git wget curl clang make cmake tar gzip || fail "pkg install failed"
ok "System packages ready"

# ══════════════════════════════════
# Step 2: Whisper.cpp (STT)
# ══════════════════════════════════
echo ""
echo "-- Step 2/5: Whisper.cpp (STT) --"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

WHISPER_BIN="$PROJECT_DIR/whisper.cpp/build/bin/whisper-cli"
if [ ! -f "$WHISPER_BIN" ]; then
    git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git || fail "git clone failed"
    cd whisper.cpp
    rm -rf build && mkdir -p build && cd build
    JOBS=$(nproc 2>/dev/null || echo 2)
    cmake .. -DCMAKE_BUILD_TYPE=Release || fail "cmake configure failed"
    cmake --build . --config Release -j"$JOBS" || fail "cmake build failed"
    cd "$PROJECT_DIR"
fi

WHISPER_MODEL="$PROJECT_DIR/whisper.cpp/models/ggml-base.bin"
mkdir -p "$(dirname "$WHISPER_MODEL")"
if [ ! -f "$WHISPER_MODEL" ]; then
    echo "Downloading Whisper model (~142 MB)..."
    wget -qO "$WHISPER_MODEL" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin" || fail "Model download failed"
fi
ok "Whisper STT ready"

# ══════════════════════════════════
# Step 3: Piper TTS (Premium Voice)
# ══════════════════════════════════
echo ""
echo "-- Step 3/5: Piper TTS (Premium Voice) --"
cd "$PROJECT_DIR"
mkdir -p piper/models
PIPER_BIN="$PROJECT_DIR/piper/piper"
PIPER_MODEL="$PROJECT_DIR/piper/models/ru_RU-irina-medium.onnx"

if [ ! -f "$PIPER_BIN" ]; then
    echo "Downloading Piper engine (ARM64)..."
    wget -qO piper.tar.gz https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_linux_aarch64.tar.gz || fail "Piper download failed"
    tar -xf piper.tar.gz || fail "Failed to extract Piper"
    rm piper.tar.gz
fi

if [ ! -f "$PIPER_MODEL" ]; then
    echo "Downloading Irina Voice Model (~50MB)..."
    wget -qO "$PIPER_MODEL" "https://huggingface.co/rhasspy/piper-voices/resolve/main/ru/ru_RU/irina/medium/ru_RU-irina-medium.onnx"
    wget -qO "${PIPER_MODEL}.json" "https://huggingface.co/rhasspy/piper-voices/resolve/main/ru/ru_RU/irina/medium/ru_RU-irina-medium.onnx.json"
fi
ok "Piper TTS ready"

# ══════════════════════════════════
# Step 4: Python dependencies
# ══════════════════════════════════
echo ""
echo "-- Step 4/5: Python dependencies --"
cd "$PROJECT_DIR"
rm -rf venv
python -m venv venv || fail "venv creation failed"
source venv/bin/activate
export ANDROID_API_LEVEL=$(getprop ro.build.version.sdk 2>/dev/null || echo 24)
pip install --upgrade pip
pip install aiogram aiohttp num2words || fail "pip install failed"
deactivate
ok "Python ready"

# ══════════════════════════════════
# Step 5: Bot code + config
# ══════════════════════════════════
echo ""
echo "-- Step 5/5: Bot code + config --"
cd "$PROJECT_DIR"

# Скачиваем новый main.py прямо с вашего GitHub
echo "Downloading main.py from repository..."
curl -sSL "https://raw.githubusercontent.com/aleksbuss/Termux-SelfHosted-STT---TTS/main/main.py" -o main.py.tmp
if [ ! -s main.py.tmp ]; then
    rm -f main.py.tmp
    fail "Failed to download main.py from GitHub"
fi
mv main.py.tmp main.py
ok "Code downloaded"

# Конфигурация
cat > .env << ENVEOF
export TELEGRAM_BOT_TOKEN="$BOT_TOKEN"
export WHISPER_BIN="$WHISPER_BIN"
export WHISPER_MODEL="$WHISPER_MODEL"
export PIPER_BIN="$PIPER_BIN"
export PIPER_MODEL="$PIPER_MODEL"
ENVEOF
chmod 600 .env

# Скрипты управления
cat > start_bot.sh << 'STARTEOF'
#!/bin/bash
cd ~/voice-bot || exit 1
pkill -f "main\.py" 2>/dev/null || true
sleep 1
source .env
source venv/bin/activate
exec python main.py
STARTEOF
chmod +x start_bot.sh

cat > stop_bot.sh << 'STOPEOF'
#!/bin/bash
pkill -f "main\.py" 2>/dev/null || true
echo "Bot stopped"
STOPEOF
chmod +x stop_bot.sh

# Настройка чистой автозагрузки в Termux
if [ -f ~/.bashrc ]; then
    grep -v 'voice-bot' ~/.bashrc > ~/.bashrc.tmp && mv ~/.bashrc.tmp ~/.bashrc
fi
cat >> ~/.bashrc << 'BASHEOF'
# voice-bot-autostart
if [ -f ~/voice-bot/start_bot.sh ]; then
    if ! pgrep -f "voice-bot.*main\.py" > /dev/null 2>&1; then
        nohup ~/voice-bot/start_bot.sh > ~/voice-bot/bot.log 2>&1 &
    fi
fi
BASHEOF

echo ""
echo "=========================================="
echo "  INSTALLATION COMPLETE!"
echo "=========================================="
echo "Starting bot in background..."

nohup ~/voice-bot/start_bot.sh > ~/voice-bot/bot.log 2>&1 &
sleep 3
if pgrep -f "voice-bot.*main\.py" > /dev/null 2>&1; then
    ok "Bot is running! Send a message to your bot in Telegram."
else
    warn "Bot may not have started. Check logs: tail ~/voice-bot/bot.log"
fi
