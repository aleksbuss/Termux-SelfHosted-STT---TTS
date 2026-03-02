#!/bin/bash

# ==========================================
#  Termux Voice AI Bot - Установщик
#  С правильной обработкой ошибок
# ==========================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Счетчик ошибок
ERRORS=0

# Функция вывода заголовка
print_header() {
    echo ""
    echo "=========================================="
    echo -e "${BLUE}$1${NC}"
    echo "=========================================="
}

# Функция успеха
print_ok() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Функция предупреждения
print_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Функция ошибки
print_error() {
    echo -e "${RED}❌ $1${NC}"
    ((ERRORS++))
}

# Функция фатальной ошибки (выход)
fatal_error() {
    echo ""
    print_error "$1"
    echo ""
    echo -e "${YELLOW}💡 Что делать:${NC}"
    echo "   $2"
    echo ""
    echo -e "${YELLOW}📍 Шаг установки:${NC} $3"
    echo -e "${YELLOW}🔍 Проверьте выше сообщение об ошибке${NC}"
    echo ""
    echo "Если не получается — откройте Issue на GitHub:"
    echo "https://github.com/aleksbuss/Termux-SelfHosted-STT---TTS/issues"
    exit 1
}

# Функция проверки команды
run_check() {
    local cmd="$1"
    local step_name="$2"
    local fix_hint="$3"
    
    echo "   Выполняю: $step_name..."
    eval "$cmd" > /tmp/install_log.txt 2>&1
    
    if [ $? -eq 0 ]; then
        print_ok "$step_name"
        return 0
    else
        print_error "$step_name"
        echo "   Лог ошибки:"
        cat /tmp/install_log.txt | sed 's/^/   > /'
        echo ""
        echo -e "${YELLOW}   💡 $fix_hint${NC}"
        return 1
    fi
}

# Функция проверки интернета
check_internet() {
    echo "   Проверка интернет-соединения..."
    if ping -c 1 google.com > /dev/null 2>&1; then
        print_ok "Интернет есть"
        return 0
    else
        fatal_error "Нет подключения к интернету" \
                   "Проверьте Wi-Fi/мобильные данные. Попробуйте: ping google.com" \
                   "Проверка сети"
    fi
}

# ==========================================
#  НАЧАЛО УСТАНОВКИ
# ==========================================

clear
print_header "🚀 Установка Termux Voice AI Bot"

echo ""
echo "Этот скрипт установит:"
echo "  🎙  Whisper.cpp (распознавание речи)"
echo "  🔊  Piper TTS (синтез речи)"
echo "  🤖  Telegram-бота"
echo ""
echo -e "${YELLOW}⚠️  Требуется:~50MB трафика и 5-10 минут времени${NC}"
echo ""

# --- ШАГ 0: Проверка среды ---
print_header "0. Проверка окружения"

# Проверяем, что мы в Termux
if [ ! -d "/data/data/com.termux" ]; then
    fatal_error "Этот скрипт только для Termux!" \
               "Установите Termux из F-Droid: https://f-droid.org/packages/com.termux/" \
               "Проверка Termux"
fi
print_ok "Termux обнаружен"

# Проверяем архитектуру
ARCH=$(uname -m)
if [[ "$ARCH" != "aarch64" && "$ARCH" != "arm64" ]]; then
    print_warn "Архитектура $ARCH — не тестировалась. Ожидается aarch64."
    echo "   Продолжить? (y/n)"
    read -r confirm < /dev/tty
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        exit 1
    fi
else
    print_ok "Архитектура aarch64"
fi

check_internet

# --- ШАГ 1: Ввод токена ---
print_header "1. Настройка бота"

echo "🔑 Введите токен вашего Telegram-бота (от @BotFather):"
echo "   (вставьте токен и нажмите Enter)"
read -r BOT_TOKEN < /dev/tty

# Очистка токена
BOT_TOKEN=$(echo "$BOT_TOKEN" | tr -d '[:space:]')

if [ -z "$BOT_TOKEN" ]; then 
    fatal_error "Токен не может быть пустым!" \
               "Получите токен у @BotFather в Telegram, затем запустите скрипт снова" \
               "Ввод токена"
fi

# Проверка формата токена
if [[ ! "$BOT_TOKEN" =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
    print_warn "Токен выглядит некорректно (ожидается: 123456789:ABC...)"
    echo "   Вы ввели: ${BOT_TOKEN:0:20}..."
    echo "   Продолжить всё равно? (y/n)"
    read -r confirm < /dev/tty
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        exit 1
    fi
fi

print_ok "Токен принят"

# --- ШАГ 2: Подготовка системы ---
print_header "2. Обновление системы"

# Обновление репозиториев
if ! run_check "pkg update -y" \
              "Обновление списка пакетов" \
              "Попробуйте вручную: pkg update"; then
    fatal_error "Не удалось обновить пакеты" \
               "Проверьте интернет. Попробуйте: termux-change-repo (сменить зеркало)" \
               "pkg update"
fi

# Обновление установленных пакетов
if ! run_check "pkg upgrade -y" \
              "Обновление установленных пакетов" \
               "Попробуйте вручную: pkg upgrade"; then
    print_warn "Не удалось обновить некоторые пакеты (не критично)"
fi

# --- ШАГ 3: Установка зависимостей ---
print_header "3. Установка зависимостей"

REQUIRED_PKGS="python ffmpeg git wget curl clang make cmake"
echo "   Пакеты: $REQUIRED_PKGS"

if ! run_check "pkg install -y $REQUIRED_PKGS" \
              "Установка пакетов" \
              "Попробуйте по одному: pkg install python, затем pkg install ffmpeg..."; then
    fatal_error "Не удалось установить зависимости" \
               "Некоторые пакеты могут конфликтовать. Попробуйте: pkg install python (отдельно)" \
               "pkg install"
fi

# Проверка Python
if ! command -v python &> /dev/null; then
    fatal_error "Python не установился" \
               "Попробуйте: pkg install python -y" \
               "Проверка Python"
fi
print_ok "Python $(python --version 2>&1 | cut -d' ' -f2)"

# --- ШАГ 4: Создание проекта ---
print_header "4. Создание проекта"

PROJECT_DIR="$HOME/voice-bot"

# Проверяем, не существует ли уже
if [ -d "$PROJECT_DIR" ]; then
    print_warn "Папка $PROJECT_DIR уже существует"
    echo "   1) Удалить и создать заново"
    echo "   2) Использовать существующую (может быть битой)"
    echo "   3) Отменить установку"
    echo "   Выберите (1/2/3):"
    read -r choice < /dev/tty
    
    case $choice in
        1)
            echo "   Удаляю старую папку..."
            rm -rf "$PROJECT_DIR"
            ;;
        2)
            echo "   Используем существующую папку"
            ;;
        3)
            exit 0
            ;;
        *)
            fatal_error "Неверный выбор" "Запустите скрипт снова" "Выбор действия"
            ;;
    esac
fi

mkdir -p "$PROJECT_DIR"
if [ $? -ne 0 ]; then
    fatal_error "Не могу создать папку $PROJECT_DIR" \
               "Проверьте права: ls -la ~" \
               "Создание папки"
fi
cd "$PROJECT_DIR" || fatal_error "Не могу зайти в папку проекта" "Проверьте: cd $PROJECT_DIR" "Переход в папку"

print_ok "Папка проекта готова: $PROJECT_DIR"

# --- ШАГ 5: Whisper.cpp ---
print_header "5. Установка Whisper (Голос → Текст)"

WHISPER_DIR="$PROJECT_DIR/whisper.cpp"

if [ -f "$WHISPER_DIR/main" ] && [ -f "$WHISPER_DIR/models/ggml-base.bin" ]; then
    print_ok "Whisper уже установлен"
else
    # Скачивание
    if [ ! -d "$WHISPER_DIR" ]; then
        if ! run_check "git clone https://github.com/ggerganov/whisper.cpp.git" \
                      "Скачивание Whisper" \
                      "Проверьте интернет. Альтернатива: скачайте вручную с GitHub"; then
            fatal_error "Не удалось скачать Whisper" \
                       "Попробуйте вручную: git clone https://github.com/ggerganov/whisper.cpp.git" \
                       "git clone whisper"
        fi
    fi
    
    cd "$WHISPER_DIR" || fatal_error "Не могу зайти в папку whisper" "" "Переход в whisper"
    
    # Компиляция
    echo "   ⏳ Компиляция (это займет 2-5 минут)..."
    if ! run_check "make" \
                  "Компиляция Whisper" \
                  "Возможно, не хватает памяти. Закройте другие приложения и попробуйте: make -j1"; then
        fatal_error "Ошибка компиляции" \
                   "1) Закройте другие приложения (освободите RAM)\n   2) Попробуйте: make clean && make\n   3) Или скачайте готовый бинарник" \
                   "make"
    fi
    
    # Скачивание модели
    echo "   ⏳ Скачивание модели (~150MB)..."
    if ! run_check "bash ./models/download-ggml-model.sh base" \
                  "Скачивание модели base" \
                  "Проверьте место: df -h. Или скачайте вручную: wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin -O models/ggml-base.bin"; then
        fatal_error "Не удалось скачать модель" \
                   "Проверьте место на диске: df -h" \
                   "download-ggml-model.sh"
    fi
    
    cd "$PROJECT_DIR" || fatal_error "Не могу вернуться в папку проекта" "" "Возврат в проект"
    print_ok "Whisper установлен"
fi

# Проверка бинарника
if [ ! -f "$WHISPER_DIR/main" ]; then
    fatal_error "Бинарник whisper не найден после установки!" \
               "Попробуйте удалить папку whisper.cpp и запустить снова" \
               "Проверка бинарника"
fi

# --- ШАГ 6: Piper TTS ---
print_header "6. Установка Piper (Текст → Голос)"

PIPER_DIR="$PROJECT_DIR/piper_tts"
mkdir -p "$PIPER_DIR"
cd "$PIPER_DIR" || fatal_error "Не могу зайти в папку piper" "" "Переход в piper"

# Проверяем, установлен ли уже
if [ -f "piper" ] && [ -f "ru_RU-irina-medium.onnx" ]; then
    print_ok "Piper уже установлен"
else
    # Скачивание бинарника
    echo "   ⏳ Скачивание Piper (~50MB)..."
    PIPER_URL="https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_arm64.tar.gz"
    
    if ! run_check "wget -q --show-progress $PIPER_URL -O piper.tar.gz" \
                  "Скачивание Piper" \
                  "Проверьте интернет. URL: $PIPER_URL"; then
        # Пробуем альтернативное имя файла
        print_warn "Не удалось скачать piper_arm64.tar.gz, пробуем piper_linux_aarch64.tar.gz..."
        PIPER_URL="https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_linux_aarch64.tar.gz"
        
        if ! run_check "wget -q --show-progress $PIPER_URL -O piper.tar.gz" \
                      "Скачивание Piper (альт.)" \
                      "Проверьте https://github.com/rhasspy/piper/releases вручную"; then
            fatal_error "Не удалось скачать Piper" \
                       "Зайдите на https://github.com/rhasspy/piper/releases и скачайте вручную для aarch64" \
                       "wget piper"
        fi
    fi
    
    # Распаковка
    if ! run_check "tar -xf piper.tar.gz" \
                  "Распаковка Piper" \
                  "Архив может быть битым. Удалите piper.tar.gz и запустите снова"; then
        fatal_error "Ошибка распаковки Piper" \
                   "Удалите piper.tar.gz и попробуйте снова" \
                   "tar"
    fi
    
    # Проверяем, где бинарник (разные архивы могут иметь разную структуру)
    if [ -f "piper" ]; then
        print_ok "Бинарник piper найден"
    elif [ -f "piper/piper" ]; then
        mv piper/piper ./piper
        print_ok "Бинарник piper найден (в подпапке)"
    else
        print_warn "Бинарник piper не найден в ожидаемом месте, ищем..."
        FOUND_PIPER=$(find . -name "piper" -type f 2>/dev/null | head -1)
        if [ -n "$FOUND_PIPER" ]; then
            cp "$FOUND_PIPER" ./piper
            print_ok "Бинарник найден: $FOUND_PIPER"
        else
            fatal_error "Бинарник piper не найден после распаковки!" \
                       "Проверьте: ls -la и найдите бинарник вручную" \
                       "Поиск бинарника"
        fi
    fi
    
    # Скачивание голоса
    echo "   ⏳ Скачивание голоса 'Ирина' (~60MB)..."
    VOICE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ru/ru_RU/irina/medium/ru_RU-irina-medium.onnx"
    CONFIG_URL="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ru/ru_RU/irina/medium/ru_RU-irina-medium.onnx.json"
    
    if ! run_check "wget -q --show-progress $VOICE_URL -O ru_RU-irina-medium.onnx" \
                  "Скачивание голоса" \
                  "Проверьте интернет. Альтернатива: скачайте вручную с HuggingFace"; then
        fatal_error "Не удалось скачать голос" \
                   "Скачайте вручную: $VOICE_URL" \
                   "wget voice"
    fi
    
    if ! run_check "wget -q --show-progress $CONFIG_URL -O ru_RU-irina-medium.onnx.json" \
                  "Скачивание конфига голоса" \
                   "Без конфига голос не заработает"; then
        fatal_error "Не удалось скачать конфиг голоса" \
                   "Скачайте вручную: $CONFIG_URL" \
                   "wget config"
    fi
    
    cd "$PROJECT_DIR" || fatal_error "Не могу вернуться в проект" "" "Возврат в проект"
    print_ok "Piper установлен"
fi

# --- ШАГ 7: Python зависимости ---
print_header "7. Установка Python-библиотек"

echo "   Установка aiogram и aiohttp..."
if ! run_check "pip install aiogram aiohttp --break-system-packages" \
              "Установка Python-пакетов" \
              "Попробуйте: pip install aiogram aiohttp (без --break-system-packages) или обновите pip: pip install --upgrade pip"; then
    # Пробуем без флага (для старых версий pip)
    print_warn "Пробуем без --break-system-packages..."
    if ! run_check "pip install aiogram aiohttp" \
                  "Установка Python-пакетов (попытка 2)" \
                  "Проверьте: python --version и pip --version"; then
        fatal_error "Не удалось установить Python-библиотеки" \
                   "1) Обновите pip: pip install --upgrade pip\n   2) Установите вручную: pip install aiogram aiohttp\n   3) Проверьте ошибки выше" \
                   "pip install"
    fi
fi

# Проверка импорта
if ! python -c "import aiogram; import aiohttp" 2>/dev/null; then
    fatal_error "Библиотеки установились, но не импортируются!" \
               "Попробуйте: python -m pip install aiogram aiohttp" \
               "Проверка импорта"
fi
print_ok "Python-библиотеки готовы"

# --- ШАГ 8: Скачивание кода бота ---
print_header "8. Загрузка кода бота"

MAIN_URL="https://raw.githubusercontent.com/aleksbuss/Termux-SelfHosted-STT---TTS/main/main.py"

if ! run_check "curl -sSL $MAIN_URL -o main.py" \
              "Скачивание main.py" \
              "Проверьте интернет. URL: $MAIN_URL"; then
    fatal_error "Не удалось скачать код бота" \
               "Проверьте, существует ли файл в репозитории: $MAIN_URL" \
               "curl main.py"
fi

# Проверка, что файл не пустой
if [ ! -s "main.py" ]; then
    fatal_error "main.py пустой!" \
               "Проверьте URL: $MAIN_URL" \
               "Проверка main.py"
fi

# Проверка, что это не HTML (ошибка 404)
if head -1 main.py | grep -q "<!DOCTYPE\|<html\|<!doctype"; then
    rm main.py
    fatal_error "Скачался HTML вместо Python-кода (404 ошибка)" \
               "Проверьте правильность URL в скрипте: $MAIN_URL" \
               "Проверка содержимого"
fi

print_ok "Код бота загружен ($(wc -l < main.py) строк)"

# --- ШАГ 9: Создание конфигурации ---
print_header "9. Настройка конфигурации"

# Определяем пути
WHISPER_BIN="$PROJECT_DIR/whisper.cpp/main"
WHISPER_MODEL="$PROJECT_DIR/whisper.cpp/models/ggml-base.bin"
PIPER_BIN="$PROJECT_DIR/piper_tts/piper"
PIPER_MODEL="$PROJECT_DIR/piper_tts/ru_RU-irina-medium.onnx"

# Проверяем существование файлов
[ -f "$WHISPER_BIN" ] || fatal_error "Whisper бинарник не найден: $WHISPER_BIN" "Переустановите Whisper" "Проверка путей"
[ -f "$WHISPER_MODEL" ] || fatal_error "Whisper модель не найдена: $WHISPER_MODEL" "Переустановите Whisper" "Проверка путей"
[ -f "$PIPER_BIN" ] || fatal_error "Piper бинарник не найден: $PIPER_BIN" "Переустановите Piper" "Проверка путей"
[ -f "$PIPER_MODEL" ] || fatal_error "Piper модель не найдена: $PIPER_MODEL" "Переустановите Piper" "Проверка путей"

# Создаем .env
cat > .env << EOF
export TELEGRAM_BOT_TOKEN="$BOT_TOKEN"
export WHISPER_BIN="$WHISPER_BIN"
export WHISPER_MODEL="$WHISPER_MODEL"
export PIPER_BIN="$PIPER_BIN"
export PIPER_MODEL="$PIPER_MODEL"
EOF

if [ $? -ne 0 ]; then
    fatal_error "Не удалось создать файл .env" \
               "Проверьте права на запись: ls -la $PROJECT_DIR" \
               "Создание .env"
fi

# Проверяем, что токен записался правильно
if ! grep -q "$BOT_TOKEN" .env; then
    fatal_error "Токен не записался в .env!" \
               "Проверьте содержимое: cat .env" \
               "Проверка .env"
fi

print_ok "Конфигурация сохранена в .env"

# --- ШАГ 10: Скрипт запуска ---
print_header "10. Настройка автозапуска"

# Создаем start_bot.sh
cat > start_bot.sh << 'EOF'
#!/bin/bash
# Автозапуск Voice Bot
cd ~/voice-bot || exit 1
source .env
exec python main.py
EOF

chmod +x start_bot.sh
if [ $? -ne 0 ]; then
    print_warn "Не удалось сделать start_bot.sh исполняемым"
else
    print_ok "Скрипт запуска создан"
fi

# Добавляем в .bashrc
BASHRC_LINE='if ! pgrep -f "python main.py" > /dev/null; then ~/voice-bot/start_bot.sh & fi'

if grep -q "voice-bot/start_bot.sh" ~/.bashrc; then
    print_ok "Автозапуск уже настроен"
else
    echo "$BASHRC_LINE" >> ~/.bashrc
    if [ $? -eq 0 ]; then
        print_ok "Автозапуск добавлен в .bashrc"
    else
        print_warn "Не удалось добавить автозапуск в .bashrc (не критично)"
        echo "   Добавьте вручную: echo '$BASHRC_LINE' >> ~/.bashrc"
    fi
fi

# --- ШАГ 11: Финальная проверка ---
print_header "11. Финальная проверка"

echo "   Проверка установки..."

# Проверка всех компонентов
ALL_OK=true

[ -f "$WHISPER_BIN" ] && echo -e "   ${GREEN}✓${NC} Whisper бинарник" || { echo -e "   ${RED}✗${NC} Whisper бинарник"; ALL_OK=false; }
[ -f "$WHISPER_MODEL" ] && echo -e "   ${GREEN}✓${NC} Whisper модель" || { echo -e "   ${RED}✗${NC} Whisper модель"; ALL_OK=false; }
[ -f "$PIPER_BIN" ] && echo -e "   ${GREEN}✓${NC} Piper бинарник" || { echo -e "   ${RED}✗${NC} Piper бинарник"; ALL_OK=false; }
[ -f "$PIPER_MODEL" ] && echo -e "   ${GREEN}✓${NC} Piper модель" || { echo -e "   ${RED}✗${NC} Piper модель"; ALL_OK=false; }
[ -f "main.py" ] && echo -e "   ${GREEN}✓${NC} Код бота" || { echo -e "   ${RED}✗${NC} Код бота"; ALL_OK=false; }
[ -f ".env" ] && echo -e "   ${GREEN}✓${NC} Конфигурация" || { echo -e "   ${RED}✗${NC} Конфигурация"; ALL_OK=false; }

if [ "$ALL_OK" = false ]; then
    echo ""
    fatal_error "Не все компоненты установлены!" \
               "Проверьте ошибки выше и запустите скрипт снова" \
               "Финальная проверка"
fi

# --- ЗАПУСК ---
print_header "🎉 УСПЕХ! Установка завершена"

echo ""
echo -e "${GREEN}✅ Ваш Voice AI Bot готов к работе!${NC}"
echo ""
echo "📍 Папка проекта: $PROJECT_DIR"
echo "🤖 Токен бота: ${BOT_TOKEN:0:20}..."
echo ""
echo "🚀 Запускаю бота..."
echo ""

# Пробуем запустить
~/voice-bot/start_bot.sh &

sleep 2

# Проверяем, запустился ли
if pgrep -f "python main.py" > /dev/null; then
    print_ok "Бот запущен в фоне!"
    echo ""
    echo "📝 Что делать дальше:"
    echo "   1. Откройте Telegram и найдите своего бота"
    echo "   2. Нажмите /start"
    echo "   3. Отправьте голосовое — получите текст"
    echo "   4. Отправьте текст — получите голосовое"
    echo ""
    echo "🔧 Полезные команды:"
    echo "   Логи в реальном времени: cd ~/voice-bot && source .env && python main.py"
    echo "   Остановить бота: pkill -f 'python main.py'"
    echo "   Перезапустить: ~/voice-bot/start_bot.sh &"
    echo "   Проверить статус: pgrep -f 'python main.py' && echo 'Работает' || echo 'Остановлен'"
    echo ""
    echo "⭐ Если бот понравился — поставьте звезду на GitHub!"
    echo "   https://github.com/aleksbuss/Termux-SelfHosted-STT---TTS"
else
    echo ""
    print_warn "Бот не удалось запустить автоматически"
    echo ""
    echo "💡 Попробуйте вручную:"
    echo "   cd ~/voice-bot"
    echo "   source .env"
    echo "   python main.py"
    echo ""
    echo "Если ошибка — скопируйте текст ошибки и создайте Issue на GitHub"
fi

echo ""
echo "=========================================="
echo -e "${BLUE}Установка завершена с $ERRORS предупреждений${NC}"
echo "=========================================="
