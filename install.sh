#!/bin/bash
# ============================================================
# Termux Voice Bot — Installer
# STT: whisper.cpp | TTS: Piper (RU, EN, ES) | fully offline
# ============================================================

cd "$HOME" 2>/dev/null || cd /data/data/com.termux/files/home || exit 1
PROJECT_DIR="$HOME/voice-bot"

ok()   { echo "[OK] $1"; }
fail() { echo "[ERROR] $1"; exit 1; }
warn() { echo "[WARN] $1"; }

echo "=========================================="
echo "  Termux Voice Bot installer"
echo "  STT: whisper.cpp | TTS: Piper (proot)"
echo "=========================================="

pkill -f "voice-bot/main\.py" 2>/dev/null || true
sleep 1

echo -n "Telegram bot token (from @BotFather): "
read -r BOT_TOKEN < /dev/tty 2>/dev/null || read -r BOT_TOKEN

if [ -z "$BOT_TOKEN" ]; then fail "Token required!"; fi
echo "$BOT_TOKEN" | grep -qE '^[0-9]+:[A-Za-z0-9_-]+$' || fail "Invalid token format!"
ok "Token accepted"

echo -n "Your Telegram User ID (optional, for security): "
read -r ALLOWED_USER_ID < /dev/tty 2>/dev/null || read -r ALLOWED_USER_ID
if [ -n "$ALLOWED_USER_ID" ]; then
    ok "Whitelist activated for ID: $ALLOWED_USER_ID"
else
    warn "No User ID provided. Bot will be public (Not recommended!)."
fi

echo "-- Step 1: System packages --"
pkg update -y; pkg upgrade -y
# rust is needed to build pydantic-core (aiogram dependency) on Termux
pkg install -y ca-certificates python ffmpeg git curl clang make cmake tar gzip sqlite proot-distro rust || fail "pkg install failed"

echo "-- Step 2: Whisper STT (Native Bionic) --"
mkdir -p "$PROJECT_DIR" && cd "$PROJECT_DIR" || exit 1

if [ ! -f "whisper.cpp/build/bin/whisper-cli" ]; then
    git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git || fail "Git clone failed"
    cd whisper.cpp && mkdir -p build && cd build || exit 1
    cmake .. -DCMAKE_BUILD_TYPE=Release || fail "CMake config failed"
    cmake --build . --config Release -j"$(nproc 2>/dev/null || echo 2)" || fail "CMake build failed"
    cd "$PROJECT_DIR" || exit 1
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

echo "-- Step 4: Piper TTS (RU, EN, ES voice models) --"
cd "$PROJECT_DIR" || exit 1
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

echo "-- Step 5: Fetch Bot Repository --"
cd "$PROJECT_DIR" || exit 1
echo "Downloading bot repository..."
git clone https://github.com/aleksbuss/Termux-SelfHosted-STT---TTS.git tmp_repo || fail "Git clone bot failed"
cp -r tmp_repo/* .
cp tmp_repo/.gitignore . 2>/dev/null || true
rm -rf tmp_repo

echo "-- Step 6: Python Setup --"
cd "$PROJECT_DIR" || exit 1
rm -rf venv; python -m venv venv || fail "Venv failed"
# shellcheck disable=SC1091
source venv/bin/activate
# pydantic-core's build script needs the Android API level to pick the right target
ANDROID_API_LEVEL=$(getprop ro.build.version.sdk 2>/dev/null || echo 24)
export ANDROID_API_LEVEL
pip install --upgrade pip
pip install -r requirements.txt || fail "pip install failed"
deactivate

echo "-- Step 7: Finalizing --"

cat > .env << ENVEOF
export TELEGRAM_BOT_TOKEN="$BOT_TOKEN"
export ALLOWED_USER_IDS="$ALLOWED_USER_ID"
export WHISPER_BIN="$PROJECT_DIR/whisper.cpp/build/bin/whisper-cli"
export WHISPER_MODEL="$PROJECT_DIR/whisper.cpp/models/ggml-base.bin"
export PIPER_BIN="$PROJECT_DIR/piper/piper"
export MODELS_DIR="$PROJECT_DIR/piper/models"
ENVEOF
chmod 600 .env

# main.py is invoked by its full path so the process can be matched
# (and killed) by the "voice-bot/main.py" pattern without touching
# unrelated processes that also run a main.py.
cat > start_bot.sh << 'STARTEOF'
#!/bin/bash
cd ~/voice-bot || exit 1
pkill -f "voice-bot/main\.py" 2>/dev/null || true
source .env
source venv/bin/activate
exec python "$HOME/voice-bot/main.py"
STARTEOF
chmod +x start_bot.sh

cat > stop_bot.sh << 'STOPEOF'
#!/bin/bash
pkill -f "voice-bot/main\.py" 2>/dev/null || true
STOPEOF
chmod +x stop_bot.sh

# Autostart on opening Termux: replace only our own marked block in
# ~/.bashrc (plus the unmarked block from older installer versions).
if [ -f ~/.bashrc ]; then
    sed -i '/# >>> voice-bot autostart >>>/,/# <<< voice-bot autostart <<</d' ~/.bashrc
    sed -i '/if \[ -f ~\/voice-bot\/start_bot\.sh \]/,/^fi$/d' ~/.bashrc
fi
cat >> ~/.bashrc << 'BASHEOF'
# >>> voice-bot autostart >>>
if [ -f ~/voice-bot/start_bot.sh ] && ! pgrep -f "voice-bot/main\.py" > /dev/null 2>&1; then
    nohup ~/voice-bot/start_bot.sh > ~/voice-bot/bot.log 2>&1 &
fi
# <<< voice-bot autostart <<<
BASHEOF

# Autostart on device boot (requires the Termux:Boot app from F-Droid).
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/voice-bot.sh << 'BOOTEOF'
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock 2>/dev/null || true
nohup ~/voice-bot/start_bot.sh > ~/voice-bot/bot.log 2>&1 &
BOOTEOF
chmod +x ~/.termux/boot/voice-bot.sh

echo "INSTALLATION COMPLETE! Starting bot..."
echo "Tip: install the Termux:Boot app from F-Droid and the bot will also survive reboots."
nohup ~/voice-bot/start_bot.sh > ~/voice-bot/bot.log 2>&1 &
