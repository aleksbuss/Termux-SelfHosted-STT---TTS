#!/bin/bash
# ============================================================
# Termux Voice AI Bot — Installer v7.1 (Hotfix Piper Download)
# ============================================================

set -e

cd "$HOME" 2>/dev/null || cd /data/data/com.termux/files/home
PROJECT_DIR="$HOME/voice-bot"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
fail() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "[INFO] $1"; }

echo "=========================================="
echo "  VOICE AI BOT v7.1 (Piper Fix)"
echo "=========================================="

pkill -f "main.py" 2>/dev/null || true
sleep 1

echo -n "Telegram bot token: "
read -r BOT_TOKEN < /dev/tty 2>/dev/null || read -r BOT_TOKEN

[ -z "$BOT_TOKEN" ] && fail "Token required!"
echo "$BOT_TOKEN" | grep -qE '^[0-9]+:[A-Za-z0-9_-]+$' || fail "Invalid token format!"
ok "Token accepted"

ARCH=$(uname -m)
info "Architecture: $ARCH"

echo "-- Step 1: System packages --"
pkg update -y && pkg upgrade -y
pkg install -y python ffmpeg git curl clang make cmake tar gzip sqlite libandroid-spawn || fail "pkg install failed"
ok "Packages installed"

echo "-- Step 2: Whisper Setup --"
mkdir -p "$PROJECT_DIR" && cd "$PROJECT_DIR"

if [ ! -f "whisper.cpp/build/bin/whisper-cli" ]; then
    rm -rf whisper.cpp
    git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git || fail "Git clone failed"
    cd whisper.cpp && mkdir -p build && cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release || fail "CMake failed"
    cmake --build . --config Release -j$(nproc 2>/dev/null || echo 2) || fail "Build failed"
    cd "$PROJECT_DIR"
fi

if [ ! -f "whisper.cpp/models/ggml-base.bin" ]; then
    info "Downloading Whisper model..."
    mkdir -p whisper.cpp/models
    curl -sSfL --retry 3 "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin" \
        -o "whisper.cpp/models/ggml-base.bin" || fail "Model download failed"
fi
ok "Whisper ready"

echo "-- Step 3: Piper Setup (FIXED) --"
cd "$PROJECT_DIR"
mkdir -p piper/models

if [ ! -f "piper/piper" ]; then
    info "Downloading Piper..."
    
    # Прямые ссылки на рабочие версии
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        URL="https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_linux_aarch64.tar.gz"
    elif [ "$ARCH" = "armv7l" ] || [ "$ARCH" = "arm" ]; then
        URL="https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_linux_armv7l.tar.gz"
    else
        fail "Unsupported arch: $ARCH"
    fi
    
    # Скачивание с проверкой
    curl -fL --retry 3 "$URL" -o piper.tar.gz 2>&1 | tee /tmp/curl.log || {
        cat /tmp/curl.log
        fail "Download failed from $URL"
    }
    
    # Проверка что скачалось
    if [ ! -s piper.tar.gz ]; then
        fail "Downloaded file is empty"
    fi
    
    # Распаковка
    tar -xzf piper.tar.gz || fail "Extract failed"
    rm -f piper.tar.gz
    
    # Структура может быть разной - ищем бинарник
    if [ -f "piper" ]; then
        mkdir -p piper_bin && mv piper piper_bin/ 2>/dev/null || true
        mv piper_bin piper
    fi
    
    chmod +x piper/piper 2>/dev/null || chmod +x piper 2>/dev/null || true
    ok "Piper installed"
else
    ok "Piper exists"
fi

# Скачивание голосов
cd "$PROJECT_DIR"
BASE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main"
MODELS="ru/ru_RU/irina/medium/ru_RU-irina-medium.onnx en/en_US/lessac/medium/en_US-lessac-medium.onnx es/es_ES/davefx/medium/es_ES-davefx-medium.onnx"

for model in $MODELS; do
    fname=$(basename "$model")
    if [ ! -f "piper/models/$fname" ]; then
        info "Downloading $fname..."
        curl -sSfL --retry 3 "$BASE_URL/$model" -o "piper/models/$fname" || warn "Failed: $fname"
        curl -sSfL --retry 3 "$BASE_URL/$model.json" -o "piper/models/$fname.json" || warn "Failed: $fname.json"
    fi
done

# Тест Piper
info "Testing Piper..."
echo "test" > /tmp/test.txt
./piper/piper --model ./piper/models/ru_RU-irina-medium.onnx --file /tmp/test.txt --output_file /tmp/test.wav 2>&1 || warn "Piper test failed"
rm -f /tmp/test.txt /tmp/test.wav

ok "Piper ready"

echo "-- Step 4: Python --"
cd "$PROJECT_DIR"
rm -rf venv
python -m venv venv || fail "venv failed"
source venv/bin/activate
pip install --upgrade pip
pip install aiogram==3.4.1 aiohttp num2words || fail "pip failed"
deactivate
ok "Python ready"

echo "-- Step 5: Files --"
cd "$PROJECT_DIR"

# Скачиваем main.py или создаем
if curl -sSfL "https://raw.githubusercontent.com/aleksbuss/Termux-SelfHosted-STT---TTS/main/main.py" -o main.py 2>/dev/null; then
    ok "Downloaded main.py"
else
    warn "Could not download main.py, create manually"
fi

# .env
cat > .env << EOF
export TELEGRAM_BOT_TOKEN="$BOT_TOKEN"
export WHISPER_BIN="$PROJECT_DIR/whisper.cpp/build/bin/whisper-cli"
export WHISPER_MODEL="$PROJECT_DIR/whisper.cpp/models/ggml-base.bin"
export PIPER_BIN="$PROJECT_DIR/piper/piper"
export MODELS_DIR="$PROJECT_DIR/piper/models"
export TEMP_DIR="/tmp/voice-bot"
EOF

chmod 600 .env

# Start script
cat > start_bot.sh << 'EOF'
#!/bin/bash
cd ~/voice-bot
pkill -f main.py 2>/dev/null || true
sleep 1
source .env
source venv/bin/activate
mkdir -p "$TEMP_DIR"
python main.py 2>&1 | tee -a bot.log
EOF
chmod +x start_bot.sh

echo "=========================================="
echo "  DONE! Run: ~/voice-bot/start_bot.sh"
echo "=========================================="
