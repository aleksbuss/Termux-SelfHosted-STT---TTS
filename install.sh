#!/bin/bash

# ==========================================
#  Termux Voice AI Bot - Установщик
# ==========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0

# ИСПРАВЛЕНИЕ: В Termux нет /tmp, используем $TMPDIR
LOG_FILE="${TMPDIR}/install_log.txt"

print_header() { echo ""; echo "=========================================="; echo -e "${BLUE}$1${NC}"; echo "=========================================="; }
print_ok()     { echo -e "${GREEN}✅ $1${NC}"; }
print_warn()   { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error()  { echo -e "${RED}❌ $1${NC}"; ((ERRORS++)); }

fatal_error() {
    echo ""
    print_error "$1"
    echo ""
    echo -e "${YELLOW}💡 Что делать:${NC} $2"
    echo -e "${YELLOW}📍 Шаг:${NC} $3"
    echo ""
    echo "Откройте Issue: https://github.com/aleksbuss/Termux-SelfHosted-STT---TTS/issues"
    exit 1
}

run_check() {
    local cmd="$1"
    local step_name="$2"
    local fix_hint="$3"
    echo "   Выполняю: $step_name..."
    eval "$cmd" > "${LOG_FILE}" 2>&1
    if [ $? -eq 0 ]; then
        print_ok "$step_name"
        return 0
    else
        print_error "$step_name"
        echo "   Лог ошибки:"
        cat "${LOG_FILE}" | sed 's/^/   > /'
        echo -e "${YELLOW}   💡 $fix_hint${NC}"
        return 1
    fi
}

check_internet() {
    echo "   Проверка интернет-соединения..."
    if ping -c 1 google.com > /dev/null 2>&1; then
        print_ok "Интернет есть"
    else
        fatal_error "Нет подключения к интернету" "Проверьте Wi-Fi" "Проверка сети"
    fi
}

# ==========================================
clear
print_header "🚀 Установка Termux Voice AI Bot"
echo ""
echo "  🎙  Whisper.cpp (распознавание речи)"
echo "  🔊  Piper TTS (синтез речи)"
echo "  🤖  Telegram-бот"
echo ""
echo -e "${YELLOW}⚠️  Нужно ~300MB и 5-10 минут${NC}"
echo ""

# --- ШАГ 0 ---
print_header "0. Проверка окружения"

[ ! -d "/data/data/com.termux" ] && fatal_error "Только для Termux!" "Установите из F-Droid" "Проверка Termux"
print_ok "Termux обнаружен"

ARCH=$(uname -m)
[[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && print_ok "Архитектура aarch64" || print_warn "Архитектура $ARCH"

check_internet

# --- ШАГ 1 ---
print_header "1. Настройка бота"

echo "🔑 Введите токен вашего Telegram-бота (от @BotFather):"
read -r BOT_TOKEN < /dev/tty
BOT_TOKEN=$(echo "$BOT_TOKEN" | tr -d '[:space:]')

[ -z "$BOT_TOKEN" ] && fatal_error "Токен пустой!" "Получите у @BotFather" "Ввод токена"
print_ok "Токен принят"

# --- ШАГ 2 ---
print_header "2. Обновление системы"

run_check "pkg update -y" "Обновление пакетов" "Попробуйте: pkg update" || \
    fatal_error "Не удалось обновить пакеты" "Попробуйте: termux-change-repo" "pkg update"

run_check "pkg upgrade -y" "Обновление системы" "Попробуйте: pkg upgrade" || \
    print_warn "Некоторые пакеты не обновились (не критично)"

# --- ШАГ 3 ---
print_header "3. Установка зависимостей"

run_check "pkg install -y python ffmpeg git wget curl clang make cmake" \
    "Установка пакетов" "Попробуйте по одному: pkg install python" || \
    fatal_error "Не удалось установить зависимости" "pkg install python ffmpeg..." "pkg install"

command -v python &> /dev/null || fatal_error "Python не установился" "pkg install python" "Проверка Python"
print_ok "Python $(python --version 2>&1 | cut -d' ' -f2)"

# --- ШАГ 4 ---
print_header "4. Создание проекта"

PROJECT_DIR="$HOME/voice-bot"

if [ -d "$PROJECT_DIR" ]; then
    print_warn "Папка уже существует. Удалить и пересоздать? (y/n)"
    read -r choice < /dev/tty
    [[ "$choice" == "y" || "$choice" == "Y" ]] && rm -rf "$PROJECT_DIR"
fi

mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR" || fatal_error "Не могу зайти в папку" "" "Переход"
print_ok "Папка: $PROJECT_DIR"

# --- ШАГ 5 ---
print_header "5. Установка Whisper (Голос → Текст)"

WHISPER_DIR="$PROJECT_DIR/whisper.cpp"

if [ -f "$WHISPER_DIR/main" ] && [ -f "$WHISPER_DIR/models/ggml-base.bin" ]; then
    print_ok "Whisper уже установлен"
else
    [ ! -d "$WHISPER_DIR" ] && \
        run_check "git clone https://github.com/ggerganov/whisper.cpp.git" \
            "Скачивание Whisper" "Проверьте интернет" || \
        fatal_error "Не удалось скачать Whisper" "git clone вручную" "git clone"

    cd "$WHISPER_DIR" || fatal_error "Нет папки whisper" "" "cd whisper"

    echo "   ⏳ Компиляция (2-5 минут)..."
    run_check "make" "Компиляция Whisper" "Закройте другие приложения" || \
        fatal_error "Ошибка компиляции" "make clean && make" "make"

    echo "   ⏳ Скачивание модели (~150MB)..."
    run_check "bash ./models/download-ggml-model.sh base" \
        "Скачивание модели" "Проверьте место: df -h" || \
        fatal_error "Не удалось скачать модель" "df -h" "download model"

    cd "$PROJECT_DIR" || fatal_error "Не могу вернуться" "" "cd project"
    print_ok "Whisper установлен"
fi

[ -f "$WHISPER_DIR/main" ] || fatal_error "Бинарник whisper не найден!" "Удалите whisper.cpp и запустите снова" "Проверка"

# --- ШАГ 6 ---
print_header "6. Установка Piper (Текст → Голос)"

PIPER_DIR="$PROJECT_DIR/piper_tts"
mkdir -p "$PIPER_DIR"
cd "$PIPER_DIR" || fatal_error "Нет папки piper" "" "cd piper"

if [ -f "$PIPER_DIR/piper" ] && [ -f "$PIPER_DIR/ru_RU-irina-medium.onnx" ]; then
    print_ok "Piper уже установлен"
else
    echo "   ⏳ Скачивание Piper (~50MB)..."
    run_check "wget --show-progress -O piper.tar.gz https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_arm64.tar.gz" \
        "Скачивание Piper" "Проверьте интернет" || \
        fatal_error "Не удалось скачать Piper" "github.com/rhasspy/piper/releases" "wget piper"

    run_check "tar -xf piper.tar.gz" "Распаковка Piper" "Удалите piper.tar.gz и попробуйте снова" || \
        fatal_error "Ошибка распаковки" "Удалите piper.tar.gz" "tar"

    # Ищем бинарник (структура архива может отличаться)
    if [ -f "piper/piper" ]; then
        cp piper/piper ./piper
    elif [ ! -f "piper" ]; then
        FOUND=$(find . -name "piper" -type f 2>/dev/null | grep -v ".tar" | head -1)
        [ -n "$FOUND" ] && cp "$FOUND" ./piper || \
            fatal_error "Бинарник piper не найден!" "ls -la $PIPER_DIR" "Поиск бинарника"
    fi
    chmod +x ./piper
    print_ok "Piper бинарник готов"

    echo "   ⏳ Скачивание голоса Ирина (~60MB)..."
    run_check "wget --show-progress -O ru_RU-irina-medium.onnx https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ru/ru_RU/irina/medium/ru_RU-irina-medium.onnx" \
        "Скачивание голоса" "Проверьте интернет" || \
        fatal_error "Не удалось скачать голос" "Скачайте вручную с HuggingFace" "wget voice"

    run_check "wget --show-progress -O ru_RU-irina-medium.onnx.json https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ru/ru_RU/irina/medium/ru_RU-irina-medium.onnx.json" \
        "Скачивание конфига голоса" "Без конфига голос не заработает" || \
        fatal_error "Не удалось скачать конфиг" "Скачайте вручную" "wget config"

    cd "$PROJECT_DIR" || fatal_error "Не могу вернуться" "" "cd project"
    print_ok "Piper установлен"
fi

# --- ШАГ 7 ---
print_header "7. Python-библиотеки"

run_check "pip install aiogram aiohttp --break-system-packages" \
    "Установка aiogram и aiohttp" "pip install aiogram aiohttp" || \
    run_check "pip install aiogram aiohttp" \
        "Установка (попытка 2)" "python --version" || \
    fatal_error "Не удалось установить библиотеки" "pip install --upgrade pip" "pip install"

python -c "import aiogram; import aiohttp" 2>/dev/null || \
    fatal_error "Библиотеки не импортируются" "python -m pip install aiogram aiohttp" "import check"
print_ok "Python-библиотеки готовы"

# --- ШАГ 8 ---
print_header "8. Загрузка кода бота"

MAIN_URL="https://raw.githubusercontent.com/aleksbuss/Termux-SelfHosted-STT---TTS/main/main.py"

run_check "curl -sSL $MAIN_URL -o main.py" "Скачивание main.py" "Проверьте: $MAIN_URL" || \
    fatal_error "Не удалось скачать main.py" "Проверьте репозиторий" "curl main.py"

[ ! -s "main.py" ] && fatal_error "main.py пустой!" "$MAIN_URL" "Проверка файла"

head -1 main.py | grep -q "<!DOCTYPE\|<html" && \
    { rm main.py; fatal_error "Скачался HTML (404)" "Проверьте URL в репозитории" "Проверка содержимого"; }

print_ok "Код бота загружен ($(wc -l < main.py) строк)"

# --- ШАГ 9 ---
print_header "9. Настройка конфигурации"

WHISPER_BIN="$PROJECT_DIR/whisper.cpp/main"
WHISPER_MODEL="$PROJECT_DIR/whisper.cpp/models/ggml-base.bin"
PIPER_BIN="$PROJECT_DIR/piper_tts/piper"
PIPER_MODEL="$PROJECT_DIR/piper_tts/ru_RU-irina-medium.onnx"

[ -f "$WHISPER_BIN" ] || fatal_error "Нет $WHISPER_BIN" "Переустановите Whisper" "Пути"
[ -f "$WHISPER_MODEL" ] || fatal_error "Нет $WHISPER_MODEL" "Переустановите Whisper" "Пути"
[ -f "$PIPER_BIN" ] || fatal_error "Нет $PIPER_BIN" "Переустановите Piper" "Пути"
[ -f "$PIPER_MODEL" ] || fatal_error "Нет $PIPER_MODEL" "Переустановите Piper" "Пути"

cat > .env << EOF
export TELEGRAM_BOT_TOKEN="$BOT_TOKEN"
export WHISPER_BIN="$WHISPER_BIN"
export WHISPER_MODEL="$WHISPER_MODEL"
export PIPER_BIN="$PIPER_BIN"
export PIPER_MODEL="$PIPER_MODEL"
EOF

print_ok "Конфигурация сохранена"

# --- ШАГ 10 ---
print_header "10. Автозапуск"

cat > start_bot.sh << 'STARTEOF'
#!/bin/bash
cd ~/voice-bot || exit 1
source .env
exec python main.py
STARTEOF

chmod +x start_bot.sh
print_ok "Скрипт запуска создан"

grep -q "voice-bot/start_bot.sh" ~/.bashrc || \
    echo 'if ! pgrep -f "python main.py" > /dev/null; then ~/voice-bot/start_bot.sh & fi' >> ~/.bashrc
print_ok "Автозапуск настроен"

# --- ШАГ 11 ---
print_header "11. Финальная проверка"

ALL_OK=true
[ -f "$WHISPER_BIN" ] && echo -e "   ${GREEN}✓${NC} Whisper" || { echo -e "   ${RED}✗${NC} Whisper"; ALL_OK=false; }
[ -f "$WHISPER_MODEL" ] && echo -e "   ${GREEN}✓${NC} Whisper модель" || { echo -e "   ${RED}✗${NC} Whisper модель"; ALL_OK=false; }
[ -f "$PIPER_BIN" ] && echo -e "   ${GREEN}✓${NC} Piper" || { echo -e "   ${RED}✗${NC} Piper"; ALL_OK=false; }
[ -f "$PIPER_MODEL" ] && echo -e "   ${GREEN}✓${NC} Piper модель" || { echo -e "   ${RED}✗${NC} Piper модель"; ALL_OK=false; }
[ -f "$PROJECT_DIR/main.py" ] && echo -e "   ${GREEN}✓${NC} Код бота" || { echo -e "   ${RED}✗${NC} Код бота"; ALL_OK=false; }
[ -f "$PROJECT_DIR/.env" ] && echo -e "   ${GREEN}✓${NC} Конфиг" || { echo -e "   ${RED}✗${NC} Конфиг"; ALL_OK=false; }

[ "$ALL_OK" = false ] && fatal_error "Не все компоненты готовы!" "Проверьте ошибки выше" "Финальная проверка"

# --- ЗАПУСК ---
print_header "🎉 Установка завершена!"

~/voice-bot/start_bot.sh &
sleep 2

if pgrep -f "python main.py" > /dev/null; then
    print_ok "Бот запущен!"
    echo ""
    echo "📝 Что делать:"
    echo "   Откройте Telegram → найдите бота → /start"
    echo "   Голосовое → текст | Текст → голосовое"
    echo ""
    echo "🔧 Команды:"
    echo "   Логи:   cd ~/voice-bot && source .env && python main.py"
    echo "   Стоп:   pkill -f 'python main.py'"
    echo "   Старт:  ~/voice-bot/start_bot.sh &"
else
    print_warn "Запустите вручную:"
    echo "   cd ~/voice-bot && source .env && python main.py"
fi

echo ""
echo -e "${BLUE}=========================================="
echo "Установка завершена! Ошибок: $ERRORS"
echo -e "==========================================${NC}"
