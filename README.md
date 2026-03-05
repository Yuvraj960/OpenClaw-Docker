# 🦞 OpenClaw + Ollama on Docker — Complete Setup Guide

Zero API costs. Runs entirely on your own machine.

---

## 📁 Files in This Package

| File | Purpose |
|---|---|
| `setup.ps1 / setup.sh` | **Run this first** — automates everything |
| `docker-compose.yml` | Docker service definitions |
| `.env.example` | Copy to `.env` and fill in your values |
| `openclaw.json` | OpenClaw model/gateway config |

---

## ✅ Prerequisites

Make sure these are installed **before** running setup:

1. **Docker Desktop** → https://www.docker.com/products/docker-desktop  
   *(Enable WSL2 backend during install when prompted)*

2. **Git** → https://git-scm.com/download/

3. **Ollama** → https://ollama.com  
   *(Start it — it runs in the system tray)*

---

## 🚀 Quick Start (Automated — Recommended)

Open **PowerShell** / **Terminal** (right-click → Run as Administrator) and run:

```powershell
# Windows

# 1. Navigate to where you downloaded this folder
cd C:\path\to\openclaw-docker-ollama

# 2. Allow script execution (one-time)
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# 3. Run setup (uses gpt-oss:20b + gemma3:12b by default)
.\setup.ps1
```

```bash
# macOS / Linux

# 1. Navigate to where you downloaded this folder
cd /path/to/openclaw-docker-ollama

# 2. Run setup (uses gpt-oss:20b + gemma3:12b by default)
chmod +x setup.sh
./setup.sh
```

### Change the models (optional):
```powershell
# Windows

# With custom models
.\setup.ps1 -OllamaPrimaryModel "mistral:latest" -OllamaSubagentModel "mistral:latest"

# All options
.\setup.ps1 -OllamaPrimaryModel "deepseek-r1:8b" -OllamaSubagentModel "qwen2.5-coder:7b" -InstallDir "C:\opt\openclaw" -GatewayToken "mysecrettoken"
```

```bash
# macOS / Linux

# With custom models
./setup.sh --primary-model mistral:latest --subagent-model mistral:latest

# All options
./setup.sh --primary-model deepseek-r1:8b --subagent-model qwen2.5-coder:7b --install-dir /opt/openclaw --token mysecrettoken
```

The script will:
- ✅ Check Docker, Git, Ollama
- ✅ Pull your selected models via Ollama
- ✅ Clone the OpenClaw GitHub repo
- ✅ Write `.env` and `openclaw.json`
- ✅ Build the Docker image
- ✅ Start the gateway
- ✅ Print your dashboard URL

---

## 🔧 Manual Setup (Step-by-Step)

If you prefer to do it yourself:

### Step 1 — Pull your model in Ollama
```powershell
ollama pull gpt-oss:20b
ollama pull gemma3:12b
# or any other model from https://ollama.com/search
```

### Step 2 — Clone OpenClaw
```powershell
git clone https://github.com/openclaw/openclaw.git
cd openclaw
```

### Step 3 — Copy config files
```powershell
# Windows

# Copy the files from this package into the cloned repo folder
Copy-Item ..\openclaw-docker-ollama\docker-compose.yml .
Copy-Item ..\openclaw-docker-ollama\.env.example .env
```

```bash
# macOS / Linux

# Copy the files from this package into the cloned repo folder
cp ../openclaw-docker-ollama/docker-compose.yml .
cp ../openclaw-docker-ollama/.env.example .env
```

Edit `.env`:
- Set `OPENCLAW_GATEWAY_TOKEN` to any long random string
- Set `OPENCLAW_PRIMARY_MODEL` to `ollama/llama3.2:latest` (or your model)

### Step 4 — Copy openclaw.json
```powershell
# Windows

# Create the config directory if it doesn't exist
New-Item -ItemType Directory -Force "$env:USERPROFILE\.openclaw"

# Copy the config
Copy-Item ..\openclaw-docker-ollama\openclaw.json "$env:USERPROFILE\.openclaw\openclaw.json"
```

```bash
# macOS / Linux

# Create the config directory if it doesn't exist
mkdir -p "$HOME/.openclaw"

# Copy the config
cp ../openclaw-docker-ollama/openclaw.json "$HOME/.openclaw/openclaw.json"
```

### Step 5 — Build and start
```powershell
docker compose build
docker compose up -d openclaw-gateway
```

### Step 6 — Get your dashboard URL
```powershell
docker compose run --rm openclaw-cli dashboard --no-open
```

Open the printed URL in your browser.

---

## 🌐 Accessing the Dashboard

Once running, open:
```
http://localhost:18789/?token=YOUR_TOKEN_HERE
```

Your token is in your `.env` file as `OPENCLAW_GATEWAY_TOKEN`.

---

## 🤖 Adding More Ollama Models

### 1. Pull the model in Ollama first:
```powershell
ollama pull deepseek-r1:8b
```

### 2. Add it to `openclaw.json` in the models array:
```json
{
  "id": "deepseek-r1:8b",
  "name": "DeepSeek R1 8B",
  "contextWindow": 65536,
  "maxOutput": 8192
}
```

### 3. Apply the change via CLI:
```powershell
docker compose exec openclaw-gateway node dist/index.js models list
```

Or simply restart the container:
```powershell
docker compose restart openclaw-gateway
```

---

## 📱 Telegram Integration (Optional)

Get free mobile access to your OpenClaw from your phone:

1. Open Telegram → search `@BotFather` → `/newbot` → follow steps → copy the bot token
2. Add to your `.env`:
   ```
   TELEGRAM_BOT_TOKEN=your_token_here
   ```
3. Restart the gateway:
   ```powershell
   docker compose restart openclaw-gateway
   ```
4. Approve pairing:
   ```powershell
   docker compose run --rm openclaw-cli pairing approve telegram YOUR_CODE
   ```

---

## 🛠️ Common Commands

```powershell
# Check if running
docker compose ps

# Live logs
docker compose logs -f openclaw-gateway

# Stop everything
docker compose down

# Restart gateway
docker compose restart openclaw-gateway

# List available models
docker compose exec openclaw-gateway node dist/index.js models list

# Switch active model
docker compose exec openclaw-gateway node dist/index.js config set agents.defaults.model.primary ollama/mistral:latest

# Get fresh dashboard URL
docker compose run --rm openclaw-cli dashboard --no-open
```

---

## ❓ Troubleshooting

| Problem | Fix |
|---|---|
| Build fails with OOM / exit 137 | Increase Docker Desktop RAM in Settings → Resources → Memory (set to 4GB+) |
| "Cannot connect to the Docker daemon" | Start Docker Desktop first |
| Models show 0 tokens / no response | Confirm Ollama is running: `curl http://localhost:11434/api/tags` |
| Dashboard shows Unauthorized | Get fresh token URL: `docker compose run --rm openclaw-cli dashboard --no-open` |
| Port 18789 already in use | Change `"127.0.0.1:18789:18789"` to `"127.0.0.1:19000:18789"` in docker-compose.yml |
| Ollama unreachable from container | Make sure `baseUrl` uses `host.docker.internal`, NOT `localhost` or `127.0.0.1` |

---

## 💡 Recommended Free Models by Use Case

| Use Case | Model | Pull Command |
|---|---|---|
| General chat | Llama 3.2 | `ollama pull llama3.2:latest` |
| Coding assistant | Qwen 2.5 Coder | `ollama pull qwen2.5-coder:7b` |
| Reasoning / analysis | DeepSeek R1 | `ollama pull deepseek-r1:8b` |
| Fast / lightweight | Phi-4 Mini | `ollama pull phi4-mini` |
| Large context tasks | Mistral | `ollama pull mistral:latest` |

> ⚠️ OpenClaw recommends a **minimum 64k context window** for local models.
> `qwen2.5-coder:7b` and `deepseek-r1:8b` both support 64k+.
