# 📱 Termux Voice AI Bot

Turn a spare Android phone into a personal **Telegram bot** for voice transcription and speech synthesis. No cloud APIs, no subscriptions — everything runs locally on the phone's CPU inside Termux. The only network traffic is the Telegram Bot API itself.

---

## ✨ Features

- 🎙️ **Speech-to-Text (STT):** Send (or forward) a voice message, audio file, or video note — the bot replies with the transcript, using `whisper.cpp`.
- 🔊 **Text-to-Speech (TTS):** Send text and the bot replies with a spoken voice message, using `Piper`.
- 🌍 **Multi-language:** Russian, English, and Spanish for both STT and TTS.
- 🔒 **Single-user by design:** A user-ID whitelist (`ALLOWED_USER_IDS`) — messages from anyone else are silently ignored.
- ⚡ **One-command install:** A single script installs packages, compiles whisper.cpp, downloads models, and configures autostart. Read `install.sh` before running it — it's short.
- 🔄 **Auto-start:** Launches when you open Termux; with the [Termux:Boot](https://f-droid.org/en/packages/com.termux.boot/) app installed it also survives reboots.

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

Phones are a constrained environment, so a few deliberate choices:

- **One AI task at a time:** A `Semaphore` queues transcription/synthesis requests instead of running them in parallel — five forwarded voice notes wait their turn rather than throttling the SoC.
- **Hung-process timeout:** If an engine hangs on corrupted audio, `asyncio.wait_for` kills the subprocess instead of blocking the pipeline forever.
- **SQLite in WAL mode:** Avoids `database is locked` errors when reads and writes overlap.
- **Unique temp filenames:** Per-request random names, cleaned up in `finally` blocks, so concurrent messages don't collide and storage doesn't fill with leftovers.
- **Startup checks:** Verifies binaries are executable and models have plausible sizes before polling starts, so a broken install fails loudly instead of silently.

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

The installer adds a marked block (between `# >>> voice-bot autostart >>>` and `# <<< voice-bot autostart <<<`) to `~/.bashrc` that starts the bot when you open Termux, and a boot script at `~/.termux/boot/voice-bot.sh` that starts it on device boot if the [Termux:Boot](https://f-droid.org/en/packages/com.termux.boot/) app is installed.

To disable auto-start, delete the marked block from `~/.bashrc` and remove `~/.termux/boot/voice-bot.sh`.

---

## 🏗 Project Structure

```
~/voice-bot/
├── main.py              # Entrypoint
├── src/                 # Bot source code modules
│   ├── bot.py           # Telegram handlers & middleware
│   ├── ai_engines.py    # Whisper/Piper subprocess logic
│   ├── database.py      # SQLite DB manager (WAL mode)
│   ├── diagnostics.py   # Startup validation
│   ├── config.py        # Environment variables
│   └── utils.py         # Text normalization utilities
├── tests/               # Unit tests (pytest)
├── .env                 # Configuration (token, whitelist, paths)
├── start_bot.sh         # Start script
├── stop_bot.sh          # Stop script
├── bot.log              # Runtime logs
├── piper/               # Piper TTS engine + voice models
└── whisper.cpp/         # whisper.cpp STT engine + model
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

**Check Python dependencies** (the bot runs in its own venv):
```bash
source ~/voice-bot/venv/bin/activate
pip list | grep aiogram
```
If missing, reinstall:
```bash
pip install -r ~/voice-bot/requirements.txt
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

