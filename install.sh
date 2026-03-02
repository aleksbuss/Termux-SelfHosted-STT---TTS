#!/bin/bash

echo "🚀 Начинаем установку локального ИИ-бота..."

read -p "🔑 Введите токен вашего Telegram-бота (от @BotFather): " BOT_TOKEN
if [ -z "$BOT_TOKEN" ]; then echo "❌ Токен пустой. Выход."; exit 1; fi

echo "📦 Устанавливаем зависимости (это займет время)..."
pkg update -y && pkg upgrade -y
pkg install -y python ffmpeg git wget curl clang make cmake

PROJECT_DIR="$HOME/voice-bot"
mkdir -p "$PROJECT_DIR" && cd "$PROJECT_DIR"

echo "🎙 Скачиваем и собираем Whisper (Голос -> Текст)..."
if [ ! -d "whisper.cpp" ]; then
    git clone https://github.com/ggerganov/whisper.cpp.git
    cd whisper.cpp && make
    bash ./models/download-ggml-model.sh base
    cd ..
fi

echo "🔊 Устанавливаем Piper (Текст -> Голос)..."
mkdir -p piper_tts && cd piper_tts
wget -qO piper.tar.gz https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_linux_aarch64.tar.gz
tar -xf piper.tar.gz
wget -qO voice.onnx https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ru/ru_RU/irina/medium/ru_RU-irina-medium.onnx
wget -qO voice.onnx.json https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ru/ru_RU/irina/medium/ru_RU-irina-medium.onnx.json
cd ..

echo "🐍 Настраиваем Python..."
pip install aiogram aiohttp --break-system-packages

echo "🤖 Скачиваем логику бота..."
curl -sSL https://raw.githubusercontent.com/aleksbuss/Termux-SelfHosted-STT---TTS/main/main.py > main.py

echo "⚙️ Создаем конфигурацию..."
cat <<EOF > .env
export TELEGRAM_BOT_TOKEN="$BOT_TOKEN"
export WHISPER_BIN="$PROJECT_DIR/whisper.cpp/main"
export WHISPER_MODEL="$PROJECT_DIR/whisper.cpp/models/ggml-base.bin"
export PIPER_BIN="$PROJECT_DIR/piper_tts/piper/piper"
export PIPER_MODEL="$PROJECT_DIR/piper_tts/voice.onnx"
EOF

echo "🔄 Настраиваем автозапуск..."
cat << 'STARTEOF' > start_bot.sh
#!/bin/bash
cd ~/voice-bot
source .env
python main.py
STARTEOF
chmod +x start_bot.sh

if ! grep -q "voice-bot/start_bot.sh" ~/.bashrc; then
    echo "if ! pgrep -f 'python main.py' > /dev/null; then ~/voice-bot/start_bot.sh & fi" >> ~/.bashrc
fi

echo "=========================================="
echo "✅ ГОТОВО! Бот установлен. Запускаем..."
echo "=========================================="
~/voice-bot/start_bot.sh &
