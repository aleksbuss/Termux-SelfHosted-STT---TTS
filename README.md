# 📱 Termux Voice AI Bot

A pocket-sized AI server running on your Android smartphone. This project turns your phone into a fully autonomous **Telegram bot** for voice and text processing. No cloud APIs, no paid subscriptions, no data leaks — everything runs **100% locally** on your device's CPU.

---

## ✨ Features

- 🎙️ **Speech-to-Text (STT):** Send a voice message and the bot transcribes it with high accuracy using `whisper.cpp`.
- 🔊 **Text-to-Speech (TTS):** Send text and the bot reads it aloud with a natural-sounding **neural voice** using `Piper TTS`.
- 🌍 **Multi-language support:** Works with **Russian**, **English**, and **Spanish** for both STT and TTS.
- 🛡️ **Zero-Trust Security:** Built-in whitelist (`ALLOWED_USER_IDS`) ensures only you can interact with the bot.
- 🔒 **Full privacy:** Not a single byte of your data leaves the device. Zero cloud dependencies.
- ⚡ **One-liner install:** A single `curl` command downloads packages, compiles engines, downloads models, and configures autostart.
- 🔄 **Auto-start:** The bot launches automatically in the background when you open Termux.

---

## 📋 Requirements

| Requirement | Details |
|---|---|
| **Device** | Android smartphone or tablet (ARM64 / aarch64) |
| **Free storage** | ~500 MB (packages + Whisper model + voice models) |
| **RAM** | 2 GB minimum (4 GB recommended) |
| **Termux** | **Must be installed from [F-Droid](https://f-droid.org/en/packages/com.termux/)** — the Google Play version is outdated and will not work |
| **Internet** | Required only for initial installation and Telegram connectivity |

---

## 🛠 Pre-installation Setup

Before running the installer you need two things:

### 1. Install Termux from F-Droid

The Google Play version of Termux has been abandoned since 2020 and is missing critical updates. Download the current version from F-Droid:

👉 [**Download Termux from F-Droid**](https://f-droid.org/en/packages/com.termux/)

> **Tip:** If you don't have F-Droid, download the APK directly from the link above and allow installation from unknown sources in your Android settings.

### 2. Create a Telegram Bot Token

1. Open Telegram and search for [@BotFather](https://t.me/BotFather).
2. Send the command `/newbot`.
3. Choose a display name and a username for your bot.
4. Copy the **HTTP API Token** that BotFather gives you (it looks like `123456789:ABCdefGHIjklMNOpqrSTUvwxYZ...`).

> **Keep this token secret.** Anyone with this token can control your bot.

---

## 🚀 Installation (One-Liner)

Open Termux on your Android device, paste this command and press Enter:

```bash
curl -sSL https://raw.githubusercontent.com/aleksbuss/Termux-SelfHosted-STT---TTS/main/install.sh | bash
```

The script will:

1. Ask you to enter your Telegram Bot Token.
2. Update Termux packages.
3. Install system dependencies (`python`, `ffmpeg`, `git`, `cmake`, `clang`, `espeak`).
4. Clone and compile `whisper.cpp` from source (~2–5 minutes on most devices).
5. Download the Whisper `base` model (~150 MB).
6. Download `Piper TTS` and its neural voice models (`.onnx`).
7. Install Python dependencies (`aiogram`, `aiohttp`, `aiosqlite`).
8. Download the bot logic.
9. Create the `.env` configuration file and ask for your Telegram User ID for the security whitelist.
10. Set up auto-start scripts.
11. Run diagnostics (Smoke tests) to ensure all models are valid, then launch the bot.

> ⏱ **Total installation time:** approximately 5–15 minutes depending on your device and internet speed.

---

## 📖 Usage

### Voice-to-Text (STT)

1. Open your Telegram bot.
2. Record and send a **voice message**.
3. The bot will transcribe it and reply with the text.

### Text-to-Voice (TTS)

1. Open your Telegram bot.
2. Type and send a **text message**.
3. The bot will synthesize speech and reply with a voice message.

### Language Selection

The bot supports multiple languages for recognition and synthesis:

| Language | STT (Whisper) | TTS (Piper Neural) |
|---|---|---|
| 🇷🇺 Russian | ✅ | ✅ (Irina Medium) |
| 🇬🇧 English | ✅ | ✅ (Lessac Medium) |
| 🇪🇸 Spanish | ✅ | ✅ (Davefx Medium) |

Use the bot's inline commands or settings to switch between languages.

### Bot Commands

| Command | Description |
|---|---|
| `/start` | Welcome message and quick instructions |
| `/help` | Show available commands |
| `/lang` | Change recognition/synthesis language |

---

## ⚙️ Configuration

All settings are stored in `~/voice-bot/.env`. You can edit them manually:

```bash
nano ~/voice-bot/.env
```

### Environment Variables

| Variable | Description | Default |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | Your Telegram bot token from BotFather | *(set during install)* |
| `ALLOWED_USER_IDS` | Comma-separated list of Telegram User IDs allowed to use the bot | *(set during install)* |
| `WHISPER_BIN` | Path to the whisper-cli binary | `~/voice-bot/whisper.cpp/build/bin/whisper-cli` |
| `WHISPER_MODEL` | Path to the Whisper GGML model file | `~/voice-bot/whisper.cpp/models/ggml-base.bin` |
| `PIPER_BIN` | Path to the Piper binary | `~/voice-bot/piper/piper` |
| `MODELS_DIR` | Path to Piper models directory | `~/voice-bot/piper/models` |

---

## 🛡️ Architecture & Reliability

This bot isn't just a script, it is engineered for strict reliability on constrained mobile environments:
- **Concurrency Locks:** A global `Semaphore` limits heavy AI tasks to 1 thread, preventing your phone from freezing due to CPU overload.
- **SQLite WAL Mode:** Database writes use `Write-Ahead Logging` to eliminate `Database is locked` errors during concurrent Telegram requests.
- **Deadlock Protection:** If an AI engine hangs due to corrupted audio, an `asyncio.wait_for` timeout kills the stuck process to self-heal the pipeline.
- **Ephemeral Files:** All temporary audio files use `uuid4()` to prevent race conditions when multiple voice messages arrive at the exact same time.
- **Deep Diagnostics:** Validates file sizes (`>10MB`) and executable permissions before startup to ensure models were downloaded successfully.

---

## 🔧 Managing the Bot

### Start the bot

```bash
~/voice-bot/start_bot.sh
```

### Stop the bot

```bash
~/voice-bot/stop_bot.sh
```

Or manually:

```bash
pkill -f "python main.py"
```

### View logs

```bash
cat ~/voice-bot/bot.log
```

### Auto-start behavior

The installer adds a line to `~/.bashrc` that starts the bot when you open Termux. To disable auto-start, edit `~/.bashrc` and remove or comment out the line containing `voice-bot/start_bot.sh`.

---

## 🏗 Project Structure

```
~/voice-bot/
├── src/                 # Bot source code modules
│   ├── main.py          # Entrypoint
│   ├── bot.py           # Telegram handlers & middleware
│   ├── ai_engines.py    # Whisper/Piper subprocess logic
│   ├── database.py      # SQLite WAL DB manager
│   ├── diagnostics.py   # Boot validation
│   ├── config.py        # Environment variables
│   └── utils.py         # Formatting utilities
├── tests/               # 100% Coverage Test Suite
├── .env                 # Configuration (token, whitelist, paths)
├── start_bot.sh         # Start script
├── stop_bot.sh          # Stop script
├── bot.log              # Runtime logs
├── piper/               # Piper Neural TTS Engine
└── whisper.cpp/         # Whisper STT engine
```

---

## 🔍 How It Works

The bot operates as a pipeline of local AI engines:

```
Voice message ──► ffmpeg (OGG → WAV) ──► whisper.cpp ──► Text reply
Text message  ──► Piper (proot-distro) ──► WAV ──► ffmpeg (WAV → OGG) ──► Voice reply
```

1. **STT Pipeline:** When you send a voice message, the bot downloads the OGG file from Telegram, converts it to 16kHz mono WAV using `ffmpeg`, passes it to `whisper-cli` for transcription, and sends the text back.

2. **TTS Pipeline:** When you send a text message, the bot passes it to `Piper` (running inside a lightweight Ubuntu `proot-distro` container to satisfy Glibc requirements on Android) which synthesizes neural voice into a WAV file, converts it to OGG format via `ffmpeg`, and sends it back.

All processing happens on-device. The only network traffic is the Telegram Bot API communication (receiving messages and sending replies).

---

## 🐛 Troubleshooting

### Bot doesn't start

**Check the token:**
```bash
source ~/voice-bot/.env
echo $TELEGRAM_BOT_TOKEN
```
Make sure the token is set and valid.

**Check Python dependencies:**
```bash
pip list | grep aiogram
```
If missing, reinstall:
```bash
pip install aiogram aiohttp --break-system-packages
```

### Whisper doesn't recognize speech

**Check the binary exists:**
```bash
ls -la ~/voice-bot/whisper.cpp/build/bin/whisper-cli
```

If missing, recompile:
```bash
cd ~/voice-bot/whisper.cpp
rm -rf build && mkdir build && cd build
cmake .. && make -j$(nproc)
```

**Check the model exists:**
```bash
ls -la ~/voice-bot/whisper.cpp/models/ggml-base.bin
```

### TTS doesn't produce audio

**Check Piper models:**
```bash
ls -la ~/voice-bot/piper/models/
```
You should see `.onnx` and `.onnx.json` files.

If `proot-distro` errors occur, ensure Ubuntu is installed:
```bash
proot-distro list
```

### "Cannot access parent directories" error

This happens if the working directory was deleted. Simply close and reopen Termux, or run:
```bash
cd ~
```

### Installation fails at cmake / compilation

Make sure you have enough storage space (~500 MB free). Try:
```bash
pkg update && pkg upgrade -y
pkg install cmake clang make
```

---

## 📝 Whisper Model Options

The installer downloads the `base` model by default. You can use a different model for better accuracy (at the cost of speed and RAM):

| Model | Size | RAM Required | Relative Speed | Accuracy |
|---|---|---|---|---|
| `tiny` | ~75 MB | ~400 MB | Fastest | Lower |
| `base` | ~150 MB | ~500 MB | Fast | Good (**default**) |
| `small` | ~500 MB | ~1 GB | Medium | Better |
| `medium` | ~1.5 GB | ~2.5 GB | Slow | High |

To switch models:

```bash
cd ~/voice-bot/whisper.cpp
bash ./models/download-ggml-model.sh small
```

Then update `WHISPER_MODEL` in `.env` to point to the new file.

---

## 🤝 Contributing

Contributions are welcome! Feel free to:

- Open an issue for bug reports or feature requests
- Submit a pull request with improvements
- Suggest new language support or TTS engines

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).

---

## 🙏 Acknowledgments

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — C/C++ port of OpenAI's Whisper model
- [espeak-ng](https://github.com/espeak-ng/espeak-ng) — Open source speech synthesizer
- [aiogram](https://github.com/aiogram/aiogram) — Modern async Telegram Bot framework for Python
- [Termux](https://termux.dev/) — Android terminal emulator and Linux environment
- [ffmpeg](https://ffmpeg.org/) — Universal media converter

---

**Made with ❤️ for privacy enthusiasts and self-hosting nerds.**
