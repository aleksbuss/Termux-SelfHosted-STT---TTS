#!/bin/bash
# ============================================================
# Termux Voice AI Bot — Installer v4.0
# STT: whisper.cpp | TTS: espeak-ng | 100% local
# ============================================================
# No set -e: pkill/grep return non-zero legitimately.

cd "$HOME" 2>/dev/null || cd /data/data/com.termux/files/home

PROJECT_DIR="$HOME/voice-bot"

ok()   { echo "[OK] $1"; }
fail() { echo "[ERROR] $1"; exit 1; }
warn() { echo "[WARN] $1"; }

echo ""
echo "=========================================="
echo "  VOICE AI BOT for Termux v4.0"
echo "  STT: whisper.cpp | TTS: espeak-ng"
echo "  100% local — zero cloud"
echo "=========================================="

# Kill ALL possible bot instances (broad pattern for install — catches old versions too)
pkill -f "main\.py" 2>/dev/null || true
pkill -f "voice-bot" 2>/dev/null || true
sleep 2

# ── Token input ──
echo ""
echo -n "Telegram bot token (from @BotFather): "
if [ -t 0 ]; then
    read BOT_TOKEN
else
    read BOT_TOKEN < /dev/tty 2>/dev/null || true
fi

if [ -z "$BOT_TOKEN" ]; then
    echo ""
    fail "Could not read token. Run instead:
  curl -sL https://raw.githubusercontent.com/aleksbuss/Termux-SelfHosted-STT---TTS/main/install.sh -o install.sh && bash install.sh"
fi

echo "$BOT_TOKEN" | grep -qE '^[0-9]+:[A-Za-z0-9_-]+$' || fail "Invalid token format"
ok "Token accepted"

# ══════════════════════════════════
# Step 1: System packages
# ══════════════════════════════════
echo ""
echo "-- Step 1/5: System packages --"

# Separate update and upgrade — upgrade can return non-zero on minor issues
pkg update -y || warn "pkg update had warnings"
pkg upgrade -y || warn "pkg upgrade had warnings"
pkg install -y python ffmpeg git wget curl clang make cmake espeak || fail "pkg install failed"

for bin in python ffmpeg git cmake espeak; do
    command -v "$bin" > /dev/null 2>&1 || fail "$bin not found after install"
done
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
    rm -rf build
    mkdir -p build
    cd build || fail "Cannot cd to build dir"

    JOBS=$(nproc 2>/dev/null || echo 2)
    cmake .. -DCMAKE_BUILD_TYPE=Release || fail "cmake configure failed"
    cmake --build . --config Release -j"$JOBS" || fail "cmake build failed"
    cd "$PROJECT_DIR" || fail "Cannot cd back to project"

    # Fallback: binary might be at different path depending on version
    if [ ! -f "$WHISPER_BIN" ]; then
        ALT=$(find whisper.cpp/build \( -name "whisper-cli" -o -name "main" \) -type f -executable 2>/dev/null | head -1)
        if [ -n "$ALT" ]; then
            WHISPER_BIN="$PROJECT_DIR/$ALT"
            warn "Binary at non-standard path: $ALT"
        else
            fail "Build succeeded but binary not found"
        fi
    fi
    ok "whisper-cli built"
fi

# Download model
WHISPER_MODEL="$PROJECT_DIR/whisper.cpp/models/ggml-base.bin"
mkdir -p "$(dirname "$WHISPER_MODEL")"

if [ -f "$WHISPER_MODEL" ]; then
    ok "Whisper model exists, skipping download"
else
    echo "Downloading Whisper base model (~142 MB)..."
    wget -O "$WHISPER_MODEL" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin" \
        || fail "Model download failed"

    # Verify file size (trim whitespace from wc output)
    SIZE=$(wc -c < "$WHISPER_MODEL" 2>/dev/null | tr -d ' ')
    SIZE=${SIZE:-0}
    if [ "$SIZE" -lt 1000000 ] 2>/dev/null; then
        rm -f "$WHISPER_MODEL"
        fail "Model file too small (${SIZE} bytes) — download corrupted"
    fi
    ok "Whisper model downloaded"
fi

# ══════════════════════════════════
# Step 3: espeak-ng
# ══════════════════════════════════
echo ""
echo "-- Step 3/5: espeak-ng (TTS) --"
command -v espeak > /dev/null 2>&1 || fail "espeak not found"
ok "espeak-ng ready"

# ══════════════════════════════════
# Step 4: Python deps
# ══════════════════════════════════
echo ""
echo "-- Step 4/5: Python dependencies --"

cd "$PROJECT_DIR" || fail "Cannot cd to $PROJECT_DIR"

# If venv exists but is broken (python/pip upgraded), recreate it
if [ -d "venv" ]; then
    if [ -f "venv/bin/python" ] && venv/bin/python -c "import pip" 2>/dev/null; then
        source venv/bin/activate
        if python -c "import aiogram; import aiohttp" 2>/dev/null; then
            ok "Already installed, skipping"
            deactivate
        else
            warn "Packages missing, installing..."
            export ANDROID_API_LEVEL=$(getprop ro.build.version.sdk 2>/dev/null || echo 24)
            pip install --upgrade pip
            pip install aiogram aiohttp || fail "pip install failed"
            deactivate
        fi
    else
        warn "venv is broken (Python upgraded?), recreating..."
        rm -rf venv
        python -m venv venv || fail "venv creation failed"
        source venv/bin/activate
        export ANDROID_API_LEVEL=$(getprop ro.build.version.sdk 2>/dev/null || echo 24)
        pip install --upgrade pip
        pip install aiogram aiohttp || fail "pip install failed"
        deactivate
    fi
else
    echo "(C extensions compile from source — may take 5-10 min on phone)"
    python -m venv venv || fail "venv creation failed"
    source venv/bin/activate
    # Required for Rust-based packages (pydantic-core) on Android/Termux
    export ANDROID_API_LEVEL=$(getprop ro.build.version.sdk 2>/dev/null || echo 24)
    pip install --upgrade pip
    pip install aiogram aiohttp || fail "pip install failed"
    deactivate
fi
ok "Python dependencies ready"

# ══════════════════════════════════
# Step 5: Bot code + config
# ══════════════════════════════════
echo ""
echo "-- Step 5/5: Bot code + config --"

cd "$PROJECT_DIR" || fail "Cannot cd to $PROJECT_DIR"

# Download to temp first, only overwrite on success
curl -sSL "https://raw.githubusercontent.com/aleksbuss/Termux-SelfHosted-STT---TTS/main/main.py" -o main.py.tmp
if [ ! -s main.py.tmp ]; then
    rm -f main.py.tmp
    fail "Failed to download main.py"
fi
mv main.py.tmp main.py
ok "Bot code downloaded"

# .env — restricted permissions (contains token)
cat > .env << ENVEOF
export TELEGRAM_BOT_TOKEN="$BOT_TOKEN"
export WHISPER_BIN="$WHISPER_BIN"
export WHISPER_MODEL="$WHISPER_MODEL"
export ESPEAK_VOICE="ru"
ENVEOF
chmod 600 .env

# ── start_bot.sh ──
cat > start_bot.sh << 'STARTEOF'
#!/bin/bash
BOT_DIR=~/voice-bot
PID_FILE="$BOT_DIR/bot.pid"

# Kill existing bot via PID file (reliable)
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null
        sleep 1
        kill -9 "$OLD_PID" 2>/dev/null
    fi
    rm -f "$PID_FILE"
fi

# Fallback: kill by name (catches strays)
pkill -f "main\.py" 2>/dev/null || true
sleep 2

cd "$BOT_DIR" || exit 1
source .env
source venv/bin/activate
exec python main.py
STARTEOF
chmod +x start_bot.sh

# ── stop_bot.sh ──
cat > stop_bot.sh << 'STOPEOF'
#!/bin/bash
PID_FILE=~/voice-bot/bot.pid
KILLED=0

# Try PID file first
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null
        sleep 1
        kill -9 "$PID" 2>/dev/null
        KILLED=1
    fi
    rm -f "$PID_FILE"
fi

# Fallback: kill by name
pkill -f "main\.py" 2>/dev/null && KILLED=1

if [ "$KILLED" -eq 1 ]; then
    echo "Bot stopped"
else
    echo "Bot was not running"
fi
STOPEOF
chmod +x stop_bot.sh

# ── restart_bot.sh ──
cat > restart_bot.sh << 'RESTARTEOF'
#!/bin/bash
~/voice-bot/stop_bot.sh
sleep 3
nohup ~/voice-bot/start_bot.sh > ~/voice-bot/bot.log 2>&1 &
disown
echo "Bot restarted. Logs: tail -f ~/voice-bot/bot.log"
RESTARTEOF
chmod +x restart_bot.sh

ok "Scripts created"

# ── Autostart (clean ALL old entries, add fresh) ──
# Use temp file to avoid sed -i portability issues
if [ -f ~/.bashrc ]; then
    grep -v 'voice-bot' ~/.bashrc > ~/.bashrc.tmp 2>/dev/null || true
    mv ~/.bashrc.tmp ~/.bashrc
fi
cat >> ~/.bashrc << 'BASHEOF'
# voice-bot-autostart-v4
if [ -f ~/voice-bot/start_bot.sh ] && ! pgrep -f "voice-bot.*main\.py" > /dev/null 2>&1; then
    echo "Starting Voice Bot..."
    nohup ~/voice-bot/start_bot.sh > ~/voice-bot/bot.log 2>&1 &
    disown
fi
BASHEOF
ok "Autostart configured"

# ══════════════════════════════════
# Launch
# ══════════════════════════════════
echo ""
echo "=========================================="
echo "  INSTALLATION COMPLETE!"
echo "=========================================="
echo ""
echo "  Start:   ~/voice-bot/start_bot.sh"
echo "  Stop:    ~/voice-bot/stop_bot.sh"
echo "  Restart: ~/voice-bot/restart_bot.sh"
echo "  Logs:    tail -f ~/voice-bot/bot.log"
echo ""
echo "  Voice message -> text (whisper.cpp)"
echo "  Text message   -> voice (espeak-ng)"
echo "=========================================="
echo ""

nohup ~/voice-bot/start_bot.sh > ~/voice-bot/bot.log 2>&1 &
disown
sleep 3

if pgrep -f "voice-bot.*main\.py" > /dev/null 2>&1; then
    ok "Bot is running! Send a voice message to your bot."
else
    warn "Bot may not have started. Check: tail ~/voice-bot/bot.log"
fi
