#!/bin/bash
# ============================================================
# Termux Voice AI Bot — Installer v7.0 (Fixed)
# STT: Whisper | TTS: Piper (RU, EN, ES) | 100% Offline
# ============================================================

set -e  # Остановка при ошибке

cd "$HOME" 2>/dev/null || cd /data/data/com.termux/files/home
PROJECT_DIR="$HOME/voice-bot"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
fail() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "[INFO] $1"; }

echo "=========================================="
echo "  VOICE AI BOT v7.0 (Fixed & Stable)"
echo "  Languages: RU 🇷🇺 | EN 🇬🇧 | ES 🇪🇸"
echo "=========================================="

# Остановка существующего бота
pkill -f "main.py" 2>/dev/null || true
sleep 1

# Чтение токена
echo -n "Telegram bot token (from @BotFather): "
read -r BOT_TOKEN < /dev/tty 2>/dev/null || read -r BOT_TOKEN

if [ -z "$BOT_TOKEN" ]; then
    fail "Token required!"
fi

if ! echo "$BOT_TOKEN" | grep -qE '^[0-9]+:[A-Za-z0-9_-]+$'; then
    fail "Invalid token format!"
fi
ok "Token accepted"

# Проверка архитектуры
ARCH=$(uname -m)
info "Detected architecture: $ARCH"

if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "armv7l" ]; then
    warn "Architecture $ARCH may not be fully supported"
fi

echo "-- Step 1: System packages --"
pkg update -y || warn "pkg update failed, continuing..."
pkg upgrade -y || warn "pkg upgrade failed, continuing..."

# Установка необходимых пакетов
REQUIRED_PKGS="python ffmpeg git curl clang make cmake tar gzip sqlite libandroid-spawn"
pkg install -y $REQUIRED_PKGS || fail "pkg install failed"

# Установка дополнительных библиотек для Piper
pkg install -y libogg libvorbis libopus || warn "Optional audio libs install failed"

ok "System packages ready"

echo "-- Step 2: Whisper STT Setup --"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

if [ ! -f "whisper.cpp/build/bin/whisper-cli" ]; then
    info "Cloning whisper.cpp..."
    rm -rf whisper.cpp  # Очистка если было частичное клонирование
    git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git || fail "Git clone failed"
    
    cd whisper.cpp
    mkdir -p build && cd build
    
    info "Configuring Whisper with CMake..."
    cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=Linux || fail "CMake config failed"
    
    info "Building Whisper (this may take 5-10 minutes)..."
    cmake --build . --config Release -j"$(nproc 2>/dev/null || echo 2)" || fail "CMake build failed"
    
    cd "$PROJECT_DIR"
    ok "Whisper built successfully"
else
    ok "Whisper already exists"
fi

# Скачивание модели Whisper
if [ ! -f "whisper.cpp/models/ggml-base.bin" ]; then
    info "Downloading Whisper model (~142 MB)..."
    mkdir -p whisper.cpp/models
    curl -sSfL --retry 3 --retry-delay 2 \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin" \
        -o "whisper.cpp/models/ggml-base.bin" || fail "Whisper model download failed"
    ok "Whisper model downloaded"
else
    ok "Whisper model exists"
fi

echo "-- Step 3: Piper TTS Setup --"
cd "$PROJECT_DIR"
mkdir -p piper/models

# Скачивание Piper
if [ ! -f "piper/piper" ]; then
    info "Downloading Piper engine..."
    
    # Определение правильной версии Piper
    if [ "$ARCH" = "aarch64" ]; then
        PIPER_URL="https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_linux_aarch64.tar.gz"
    else
        PIPER_URL="https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_linux_armv7l.tar.gz"
    fi
    
    curl -sSfL --retry 3 --retry-delay 2 "$PIPER_URL" -o piper.tar.gz || fail "Piper download failed"
    tar -xzf piper.tar.gz -C piper --strip-components=1 || fail "Piper extraction failed"
    rm -f piper.tar.gz
    
    # Даем права на выполнение
    chmod +x piper/piper
    chmod +x piper/lib/*.so 2>/dev/null || true
    
    ok "Piper installed"
else
    ok "Piper already exists"
    chmod +x piper/piper  # На всякий случай
fi

# Скачивание голосовых моделей
BASE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main"
declare -A MODELS=(
    ["ru_RU-irina-medium.onnx"]="ru/ru_RU/irina/medium/ru_RU-irina-medium.onnx"
    ["en_US-lessac-medium.onnx"]="en/en_US/lessac/medium/en_US-lessac-medium.onnx"
    ["es_ES-davefx-medium.onnx"]="es/es_ES/davefx/medium/es_ES-davefx-medium.onnx"
)

for filename in "${!MODELS[@]}"; do
    model_path="${MODELS[$filename]}"
    
    if [ ! -f "piper/models/$filename" ]; then
        info "Downloading voice model: $filename"
        
        # Скачивание .onnx
        curl -sSfL --retry 3 --retry-delay 2 \
            "$BASE_URL/$model_path" \
            -o "piper/models/$filename" || fail "Failed to download $filename"
        
        # Скачивание .json
        curl -sSfL --retry 3 --retry-delay 2 \
            "$BASE_URL/${model_path}.json" \
            -o "piper/models/${filename}.json" || fail "Failed to download JSON for $filename"
        
        ok "Downloaded $filename"
    else
        ok "Model $filename exists"
    fi
done

# Проверка работоспособности Piper
info "Testing Piper installation..."
echo "Тест" > /tmp/piper_test.txt
if ./piper/piper --model ./piper/models/ru_RU-irina-medium.onnx --file /tmp/piper_test.txt --output_file /tmp/piper_test.wav 2>/dev/null; then
    ok "Piper test passed"
    rm -f /tmp/piper_test.txt /tmp/piper_test.wav
else
    warn "Piper test failed, but continuing..."
fi

echo "-- Step 4: Python Environment --"
cd "$PROJECT_DIR"

# Очистка старого окружения
rm -rf venv
info "Creating Python virtual environment..."
python -m venv venv || fail "Failed to create venv"

# Активация и установка пакетов
source venv/bin/activate

export ANDROID_API_LEVEL=$(getprop ro.build.version.sdk 2>/dev/null || echo 28)

info "Upgrading pip..."
pip install --upgrade pip wheel setuptools || warn "pip upgrade failed"

info "Installing Python packages..."
pip install aiogram==3.4.1 aiohttp==3.9.1 num2words || fail "pip install failed"

deactivate
ok "Python environment ready"

echo "-- Step 5: Downloading main.py --"
cd "$PROJECT_DIR"

# Создаем резервную копию старого main.py если есть
[ -f main.py ] && mv main.py main.py.backup.$(date +%s)

# Скачивание main.py
curl -sSfL --retry 3 \
    "https://raw.githubusercontent.com/aleksbuss/Termux-SelfHosted-STT---TTS/main/main.py" \
    -o main.py.download || warn "Failed to download main.py from repo"

if [ -f main.py.download ]; then
    mv main.py.download main.py
    ok "main.py downloaded"
else
    warn "Using local main.py or creating from template..."
    # Здесь можно добавить создание main.py из heredoc если нужно
fi

echo "-- Step 6: Configuration --"

# Создание .env файла
cat > .env << ENVEOF
# Voice Bot Configuration
export TELEGRAM_BOT_TOKEN="$BOT_TOKEN"
export WHISPER_BIN="$PROJECT_DIR/whisper.cpp/build/bin/whisper-cli"
export WHISPER_MODEL="$PROJECT_DIR/whisper.cpp/models/ggml-base.bin"
export PIPER_BIN="$PROJECT_DIR/piper/piper"
export MODELS_DIR="$PROJECT_DIR/piper/models"
export LD_LIBRARY_PATH="$PROJECT_DIR/piper/lib:$LD_LIBRARY_PATH"
export TEMP_DIR="/tmp/voice-bot"
export LOG_LEVEL="INFO"
ENVEOF

chmod 600 .env
ok "Environment file created"

# Создание скрипта запуска
cat > start_bot.sh << 'STARTEOF'
#!/bin/bash
set -e

cd ~/voice-bot || exit 1

# Остановка если уже запущен
pkill -f "main.py" 2>/dev/null || true
sleep 1

# Загрузка переменных окружения
source .env

# Создание временной директории
mkdir -p "$TEMP_DIR"

# Активация окружения
source venv/bin/activate

# Проверка зависимостей
if [ ! -f "$WHISPER_BIN" ]; then
    echo "[ERROR] Whisper not found at $WHISPER_BIN"
    exit 1
fi

if [ ! -f "$PIPER_BIN" ]; then
    echo "[ERROR] Piper not found at $PIPER_BIN"
    exit 1
fi

echo "[INFO] Starting Voice AI Bot..."
echo "[INFO] Whisper: $WHISPER_BIN"
echo "[INFO] Piper: $PIPER_BIN"

# Запуск бота
exec python main.py 2>&1 | tee -a bot.log
STARTEOF

chmod +x start_bot.sh

# Скрипт остановки
cat > stop_bot.sh << 'STOPEOF'
#!/bin/bash
echo "Stopping bot..."
pkill -f "main.py" 2>/dev/null && echo "Bot stopped" || echo "Bot was not running"
pkill -f "whisper-cli" 2>/dev/null || true
pkill -f "piper" 2>/dev/null || true
STOPEOF

chmod +x stop_bot.sh

# Скрипт проверки статуса
cat > status_bot.sh << 'STATUSEOF'
#!/bin/bash
if pgrep -f "main.py" > /dev/null 2>&1; then
    echo "✅ Bot is RUNNING"
    echo "PID: $(pgrep -f 'main.py')"
    echo "Log tail:"
    tail -n 5 ~/voice-bot/bot.log 2>/dev/null || echo "No log file"
else
    echo "❌ Bot is NOT running"
fi
STATUSEOF

chmod +x status_bot.sh

# Скрипт диагностики
cat > diagnose.sh << 'DIAGEOF'
#!/bin/bash
cd ~/voice-bot || exit 1
source .env 2>/dev/null || true

echo "=== Voice Bot Diagnostics ==="
echo "Date: $(date)"
echo ""

echo "=== Directory Structure ==="
ls -la
echo ""

echo "=== Whisper ==="
if [ -f "$WHISPER_BIN" ]; then
    echo "✅ Whisper binary found"
    ls -la "$WHISPER_BIN"
else
    echo "❌ Whisper binary NOT found at $WHISPER_BIN"
fi

if [ -f "$WHISPER_MODEL" ]; then
    echo "✅ Whisper model found ($(stat -c%s "$WHISPER_MODEL" 2>/dev/null || stat -f%z "$WHISPER_MODEL" 2>/dev/null) bytes)"
else
    echo "❌ Whisper model NOT found at $WHISPER_MODEL"
fi
echo ""

echo "=== Piper ==="
if [ -f "$PIPER_BIN" ]; then
    echo "✅ Piper binary found"
    ls -la "$PIPER_BIN"
    echo "Testing Piper..."
    echo "test" > /tmp/diag_test.txt
    if $PIPER_BIN --model "$MODELS_DIR/ru_RU-irina-medium.onnx" --file /tmp/diag_test.txt --output_file /tmp/diag_test.wav 2>&1; then
        echo "✅ Piper test PASSED"
    else
        echo "❌ Piper test FAILED"
    fi
    rm -f /tmp/diag_test.txt /tmp/diag_test.wav
else
    echo "❌ Piper binary NOT found at $PIPER_BIN"
fi

echo ""
echo "=== Voice Models ==="
ls -la "$MODELS_DIR" 2>/dev/null || echo "Models directory not found"
echo ""

echo "=== Python Environment ==="
if [ -d "venv" ]; then
    echo "✅ Virtual environment exists"
    source venv/bin/activate
    python --version
    pip list | grep -E "aiogram|aiohttp|num2words"
else
    echo "❌ Virtual environment NOT found"
fi
echo ""

echo "=== Bot Process ==="
if pgrep -f "main.py" > /dev/null; then
    echo "✅ Bot is running (PID: $(pgrep -f 'main.py'))"
else
    echo "❌ Bot is NOT running"
fi
echo ""

echo "=== Recent Logs ==="
tail -n 20 bot.log 2>/dev/null || echo "No log file"
DIAGEOF

chmod +x diagnose.sh

# Автозапуск в .bashrc (опционально)
read -p "Add auto-start to .bashrc? (y/n): " -n 1 -r < /dev/tty 2>/dev/null || REPLY="n"
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Удаляем старые записи
    if [ -f ~/.bashrc ]; then
        grep -v 'voice-bot' ~/.bashrc > ~/.bashrc.tmp 2>/dev/null && mv ~/.bashrc.tmp ~/.bashrc || true
    fi
    
    cat >> ~/.bashrc << 'BASHEOF'

# Voice Bot Auto-start
if [ -f ~/voice-bot/start_bot.sh ] && ! pgrep -f "voice-bot.*main.py" > /dev/null 2>&1; then
    echo "Starting Voice Bot..."
    nohup ~/voice-bot/start_bot.sh > ~/voice-bot/bot.log 2>&1 &
fi
BASHEOF
    ok "Auto-start added to .bashrc"
fi

echo ""
echo "=========================================="
echo "  INSTALLATION COMPLETE!"
echo "=========================================="
echo ""
echo "Commands:"
echo "  Start:   ~/voice-bot/start_bot.sh"
echo "  Stop:    ~/voice-bot/stop_bot.sh"
echo "  Status:  ~/voice-bot/status_bot.sh"
echo "  Diagnose: ~/voice-bot/diagnose.sh"
echo ""
echo "Logs: ~/voice-bot/bot.log"
echo ""
echo "Starting bot for the first time..."
sleep 2

# Первый запуск
~/voice-bot/start_bot.sh &
