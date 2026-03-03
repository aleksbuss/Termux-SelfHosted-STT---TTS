#!/bin/bash
set -e

echo ""
echo "=========================================="
echo "  INSTALL VOICE AI BOT for Termux v2.0"
echo "  STT: whisper.cpp (local)"
echo "  TTS: espeak-ng (local, native Termux)"
echo "  100% privacy - no cloud"
echo "=========================================="
echo ""

read -p "Enter your Telegram bot token (from @BotFather): " BOT_TOKEN
if [ -z "$BOT_TOKEN" ]; then
    echo "ERROR: Token is empty. Exit."
    exit 1
fi

echo ""
echo "Step 1/5: Installing system dependencies..."
pkg update -y && pkg upgrade -y
pkg install -y python ffmpeg git wget curl clang make cmake espeak

PROJECT_DIR="$HOME/voice-bot"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

echo ""
echo "Step 2/5: Building Whisper (Voice to Text)..."
if [ ! -d "whisper.cpp" ]; then
    git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git
fi
cd whisper.cpp
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release -j$(nproc)
cd ../..

echo "Downloading Whisper base model (~142 MB)..."
mkdir -p whisper.cpp/models
if [ ! -f "whisper.cpp/models/ggml-base.bin" ]; then
    wget -O whisper.cpp/models/ggml-base.bin \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
fi
echo "Whisper ready!"

echo ""
echo "Step 3/5: TTS via espeak-ng (native for Termux)..."
if command -v espeak > /dev/null 2>&1; then
    echo "espeak-ng installed and working!"
else
    echo "ERROR: espeak not found. Try: pkg install espeak"
    exit 1
fi

echo ""
echo "Step 4/5: Installing Python dependencies..."
echo "  (aiogram + aiohttp may compile for 5-10 min on phone)"
python -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install aiogram aiohttp
deactivate
echo "Python dependencies installed!"

echo ""
echo "Step 5/5: Downloading bot code..."
curl -sSL "https://raw.githubusercontent.com/aleksbuss/Termux-SelfHosted-STT---TTS/main/main.py" -o main.py

if [ ! -s main.py ]; then
    echo "ERROR: Failed to download main.py"
    exit 1
fi

cat > .env << ENVEOF
export TELEGRAM_BOT_TOKEN="$BOT_TOKEN"
export WHISPER_BIN="$PROJECT_DIR/whisper.cpp/build/bin/whisper-cli"
export WHISPER_MODEL="$PROJECT_DIR/whisper.cpp/models/ggml-base.bin"
export TTS_ENGINE="espeak"
export ESPEAK_VOICE="ru"
ENVEOF

cat > start_bot.sh << 'STARTEOF'
#!/bin/bash
cd ~/voice-bot
source .env
source venv/bin/activate
python main.py
STARTEOF
chmod +x start_bot.sh

cat > stop_bot.sh << 'STOPEOF'
#!/bin/bash
pkill -f "python main.py" 2>/dev/null && echo "Bot stopped" || echo "Bot not running"
STOPEOF
chmod +x stop_bot.sh

if ! grep -q "voice-bot/start_bot.sh" ~/.bashrc 2>/dev/null; then
    echo '# Auto-start voice bot' >> ~/.bashrc
    echo 'if ! pgrep -f "python main.py" > /dev/null 2>&1; then ~/voice-bot/start_bot.sh & fi' >> ~/.bashrc
fi

echo ""
echo "=========================================="
echo "  INSTALLATION COMPLETE!"
echo "  Start: ~/voice-bot/start_bot.sh"
echo "  Stop:  ~/voice-bot/stop_bot.sh"
echo "  STT:   whisper-cli (local)"
echo "  TTS:   espeak-ng (local)"
echo "=========================================="
echo ""
echo "Starting bot..."
~/voice-bot/start_bot.sh &
