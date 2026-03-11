#!/bin/bash
# ============================================================
# Termux Voice AI Bot — Installer v5.0 (Premium Voice)
# STT: whisper.cpp | TTS: Piper (Irina) | 100% local
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
echo "=========================================="

pkill -f "main\.py" 2>/dev/null || true
pkill -f "voice-bot" 2>/dev/null || true
sleep 2

echo ""
echo -n "Telegram bot token (from @BotFather): "
read BOT_TOKEN

if [ -z "$BOT_TOKEN" ]; then
    fail "Could not read token."
fi
echo "$BOT_TOKEN" | grep -qE '^[0-9]+:[A-Za-z0-9_-]+$' || fail "Invalid token format"
ok "Token accepted"

# ══════════════════════════════════
# Step 1: System packages
# ══════════════════════════════════
echo ""
echo "-- Step 1/5: System packages --"

pkg update -y || warn "pkg update had warnings"
pkg upgrade -y || warn "pkg upgrade had warnings"
# Убрали espeak, добавили tar и gzip для Piper
pkg install -y python ffmpeg git wget curl clang make cmake tar gzip || fail "pkg install failed"

ok "System packages ready"

# ══════════════════════════════════
# Step 2: Whisper.cpp
# ══════════════════════════════════
echo ""
echo "-- Step 2/5: Whisper.cpp (STT) --"

mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR" || fail "Cannot cd to $PROJECT_DIR"

WHISPER_BIN="$PROJECT_DIR/whisper.cpp/build/bin/whisper-cli"

if [ -f "$WHISPER_BIN" ]; then
    ok "whisper-cli already built, skipping"
else
    if [ ! -d "whisper.cpp" ]; then
        git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git || fail "git clone failed"
    fi
    cd whisper.cpp
    rm -rf build && mkdir -p build && cd build || fail "Cannot cd to build dir"
    JOBS=$(nproc 2>/dev/null || echo 2)
    cmake .. -DCMAKE_BUILD_TYPE=Release || fail "cmake configure failed"
    cmake --build . --config Release -j"$JOBS" || fail "cmake build failed"
    cd "$PROJECT_DIR"
fi

WHISPER_MODEL="$PROJECT_DIR/whisper.cpp/models/ggml-base.bin"
mkdir -p "$(dirname "$WHISPER_MODEL")"
if [ ! -f "$WHISPER_MODEL" ]; then
    echo "Downloading Whisper base model (~142 MB)..."
    wget -O "$WHISPER_MODEL" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin" || fail "Model download failed"
fi
ok "Whisper ready"

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
    echo "Downloading Piper binary for ARM64..."
    wget -qO piper.tar.gz https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_linux_aarch64.tar.gz || fail "Piper download failed"
    tar -xf piper.tar.gz || fail "Failed to extract Piper"
    rm piper.tar.gz
fi

if [ ! -f "$PIPER_MODEL" ]; then
    echo "Downloading Irina Premium Model (~50MB)..."
    wget -qO "$PIPER_MODEL" "https://huggingface.co/rhasspy/piper-voices/resolve/main/ru/ru_RU/irina/medium/ru_RU-irina-medium.onnx"
    wget -qO "${PIPER_MODEL}.json" "https://huggingface.co/rhasspy/piper-voices/resolve/main/ru/ru_RU/irina/medium/ru_RU-irina-medium.onnx.json"
fi
ok "Piper TTS ready"

# ══════════════════════════════════
# Step 4: Python deps
# ══════════════════════════════════
echo ""
echo "-- Step 4/5: Python dependencies --"
cd "$PROJECT_DIR"

if [ ! -d "venv" ] || ! venv/bin/python -c "import pip" 2>/dev/null; then
    rm -rf venv
    python -m venv venv || fail "venv creation failed"
fi

source venv/bin/activate
export ANDROID_API_LEVEL=$(getprop ro.build.version.sdk 2>/dev/null || echo 24)
pip install --upgrade pip
# ДОБАВЛЕН num2words ДЛЯ НОРМАЛИЗАЦИИ ТЕКСТА
pip install aiogram aiohttp num2words || fail "pip install failed"
deactivate
ok "Python dependencies ready"

# ══════════════════════════════════
# Step 5: Bot code + config
# ══════════════════════════════════
echo ""
echo "-- Step 5/5: Bot code + config --"
cd "$PROJECT_DIR"

# КОПИРУЕМ ЛОКАЛЬНЫЙ main.py ВМЕСТО СКАЧИВАНИЯ С GITHUB
if [ -f "$OLDPWD/main.py" ]; then
    cp "$OLDPWD/main.py" "$PROJECT_DIR/main.py"
    ok "Copied local main.py"
elif [ ! -f "main.py" ]; then
    fail "main.py not found! Please place main.py in the same folder as this script."
fi

cat > .env << ENVEOF
export TELEGRAM_BOT_TOKEN="$BOT_TOKEN"
export WHISPER_BIN="$WHISPER_BIN"
export WHISPER_MODEL="$WHISPER_MODEL"
export PIPER_BIN="$PIPER_BIN"
export PIPER_MODEL="$PIPER_MODEL"
ENVEOF
chmod 600 .env

# Генерация bash скриптов (start_bot.sh, stop_bot.sh, restart_bot.sh)
cat > start_bot.sh << 'STARTEOF'
#!/bin/bash
BOT_DIR=~/voice-bot
PID_FILE="$BOT_DIR/bot.pid"
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null; sleep 1; kill -9 "$OLD_PID" 2>/dev/null
    fi
    rm -f "$PID_FILE"
fi
pkill -f "main\.py" 2>/dev/null || true; sleep 2
cd "$BOT_DIR" || exit 1
source .env
source venv/bin/activate
exec python main.py
STARTEOF
chmod +x start_bot.sh

cat > stop_bot.sh << 'STOPEOF'
#!/bin/bash
PID_FILE=~/voice-bot/bot.pid
if [ -f "$PID_FILE" ]; then PID=$(cat "$PID_FILE" 2>/dev/null); kill "$PID" 2>/dev/null; rm -f "$PID_FILE"; fi
pkill -f "main\.py" 2>/dev/null || true
echo "Bot stopped"
STOPEOF
chmod +x stop_bot.sh

cat > restart_bot.sh << 'RESTARTEOF'
#!/bin/bash
~/voice-bot/stop_bot.sh; sleep 3
nohup ~/voice-bot/start_bot.sh > ~/voice-bot/bot.log 2>&1 &
disown
echo "Bot restarted. Logs: tail -f ~/voice-bot/bot.log"
RESTARTEOF
chmod +x restart_bot.sh

# Автозагрузка
if [ -f ~/.bashrc ]; then grep -v 'voice-bot' ~/.bashrc > ~/.bashrc.tmp 2>/dev/null || true; mv ~/.bashrc.tmp ~/.bashrc; fi
cat >> ~/.bashrc << 'BASHEOF'
if [ -f ~/voice-bot/start_bot.sh ] && ! pgrep -f "voice-bot.*main\.py" > /dev/null 2>&1; then
    nohup ~/voice-bot/start_bot.sh > ~/voice-bot/bot.log 2>&1 &
    disown
fi
BASHEOF

echo "=========================================="
echo "  INSTALLATION COMPLETE!"
echo "=========================================="
nohup ~/voice-bot/start_bot.sh > ~/voice-bot/bot.log 2>&1 &
disown
sleep 3
ok "Bot is running! Send a text message to hear the new premium voice."
