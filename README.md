# VibeProxy

<p align="center">
  <img src="icon.png" width="128" height="128" alt="VibeProxy Icon">
</p>

<p align="center">
<a href="https://automaze.io" rel="nofollow"><img alt="Automaze" src="https://img.shields.io/badge/By-automaze.io-4b3baf" style="max-width: 100%;"></a>
<a href="https://github.com/automazeio/vibeproxy/blob/main/LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/License-MIT-28a745" style="max-width: 100%;"></a>
<a href="http://x.com/intent/follow?screen_name=aroussi" rel="nofollow"><img alt="Follow on 𝕏" src="https://img.shields.io/badge/Follow-%F0%9D%95%8F/@aroussi-1c9bf0" style="max-width: 100%;"></a>
<a href="https://github.com/automazeio/vibeproxy"><img alt="Star this repo" src="https://img.shields.io/github/stars/automazeio/vibeproxy.svg?style=social&amp;label=Star%20this%20repo&amp;maxAge=60" style="max-width: 100%;"></a></p>
</p>

**Stop paying twice for AI.** VibeProxy is a beautiful native macOS menu bar app that lets you use your existing Claude Code, ChatGPT, **Gemini**, **Qwen**, **Kimi**, **Antigravity**, and **Z.AI GLM** subscriptions with powerful AI coding tools like **[Factory Droids](https://app.factory.ai/r/FM8BJHFQ)** – no separate API keys required.

Built on [CLIProxyAPIPlus](https://github.com/router-for-me/CLIProxyAPIPlus), it handles OAuth authentication, token management, and API routing automatically. One click to authenticate, zero friction to code.

> [!NOTE]
> This is a **fork** that adds Kimi provider support, an Ollama-compatible server, and other enhancements. Builds from this fork are **ad-hoc signed** and will trigger macOS Gatekeeper. See [Installation](#installation) for how to open the app.


<p align="center">
<br>
</p>

> [!TIP]
> 📣 **NEW: Kimi support + Ollama-compatible server!**<br>Connect Kimi (Moonshot AI) via OAuth device flow and optionally enable an Ollama-compatible server on port 11434 for tools that expect Ollama.
>
> **Latest models supported:** Gemini 3 Pro (via Antigravity), GPT-5.1 / GPT-5.1 Codex, Claude Sonnet 4.5 / Opus 4.5 with extended thinking, Kimi K2.5, GitHub Copilot, and Z.AI GLM-4.7! 🚀 
> 
> **Setup Guides:**
> - [Factory CLI Setup →](FACTORY_SETUP.md) - Use Factory Droids with your AI subscriptions
> - [Amp CLI Setup →](AMPCODE_SETUP.md) - Use Amp CLI with fallback to your subscriptions

---

## Features

- 🎯 **Native macOS Experience** - Clean, native SwiftUI interface that feels right at home on macOS
- 💎 **Liquid Glass UI** - Modern Liquid Glass design with smooth, responsive animations
- 🚀 **One-Click Server Management** - Start/stop the proxy server from your menu bar
- 🔐 **Easy Authentication** - Authenticate with Codex, Claude Code, Gemini, Qwen, Kimi, Antigravity (OAuth), and Z.AI GLM (API key) directly from the app
- 🛡️ **Vercel AI Gateway** - Route Claude requests through [Vercel's AI Gateway](https://vercel.com/docs/ai-gateway) for safer access to your Claude Max subscription without risking your account from direct OAuth token usage
- 👥 **Multi-Account Support** - Connect multiple accounts per provider with automatic round-robin distribution and failover when rate-limited
- 🎚️ **Provider Priority** - Enable/disable providers to control which models are available (instant hot reload)
- 🦙 **Ollama-Compatible Server** - Built-in Ollama-compatible API on port 11434, letting you use any Ollama chat client (like [Reins](https://github.com/ibrahimcetin/reins)) with all your connected providers
- 📊 **Real-Time Status** - Live connection status and automatic credential detection
- 🔄 **Automatic App Updates** - Starting with v1.6, VibeProxy checks for updates daily and installs them seamlessly via Sparkle
- 🎨 **Beautiful Icons** - Custom icons with dark mode support
- 💾 **Self-Contained** - Everything bundled inside the .app (server binary, config, static files)


## Installation

**Requirements:** macOS 26.1 or later. Precompiled releases only support Apple Silicon.

### Build from Source

1. **Clone and apply patches**
   ```bash
   git clone https://github.com/automazeio/vibeproxy.git
   cd vibeproxy

   # Apply Kimi support to CLIProxyAPIPlus backend
   git apply patches/cliproxyapiplus-kimi-support.patch

   # Apply Kimi UI support to VibeProxy
   git apply patches/vibeproxy-kimi-ui.patch

   # (Optional) Apply Sparkle update feed patch
   git apply patches/vibeproxy-sparkle-feed.patch
   ```

2. **Build the app**
   ```bash
   ./create-app-bundle.sh
   ```

3. **Install**
   ```bash
   mv VibeProxy.app /Applications/
   ```

### Opening an Ad-Hoc Signed Build

Builds from this fork are ad-hoc signed (not notarized) and will be blocked by Gatekeeper on first launch. To open the app:

1. Double-click `VibeProxy.app` — macOS will show a warning that it cannot verify the developer. Click **Done**.
2. Open **System Settings → Privacy & Security**, scroll down to the **Security** section, and click **Open Anyway** next to the VibeProxy message.
3. Launch `VibeProxy.app` again — click **Open** when prompted, then enter your administrator password.

Alternatively, remove the quarantine attribute before launching:
```bash
xattr -cr /Applications/VibeProxy.app
```

You only need to do this once — subsequent launches will work normally.

## Usage

### First Launch

1. Launch VibeProxy - you'll see a menu bar icon
2. Click the icon and select "Open Settings"
3. The server will start automatically
4. Click "Connect" for Claude Code, Codex, Gemini, Qwen, or Antigravity to authenticate, or "Add Account" for Z.AI GLM to enter your API key

### Authentication

When you click "Connect":
1. Your browser opens with the OAuth page
2. Complete the authentication in the browser
3. VibeProxy automatically detects your credentials
4. Status updates to show you're connected

### Server Management

- **Toggle Server**: Click the status (Running/Stopped) to start/stop
- **Menu Bar Icon**: Shows active/inactive state
- **Launch at Login**: Toggle to start VibeProxy automatically

### Ollama-Compatible Server

VibeProxy includes an Ollama-compatible API server on port 11434. Enable it in Settings to use any Ollama chat client with your connected providers.

- **Supported endpoints**: `/api/tags`, `/api/chat`, `/api/generate`
- **Streaming & non-streaming**: Both modes supported
- **Kimi compatibility**: Kimi thinking/reasoning content is handled gracefully — only the final response is returned to the client
- **Tested clients**: [Reins](https://github.com/ibrahimcetin/reins)

## Requirements

Precompiled releases only support Apple Silicon.
- macOS 26.1 or later

## Development

### Project Structure

```
VibeProxy/
├── src/
│   ├── Package.swift               # Swift Package Manager config
│   ├── Info.plist                  # macOS app metadata
│   └── Sources/
│       ├── main.swift              # App entry point
│       ├── AppDelegate.swift       # Menu bar & window management
│       ├── ServerManager.swift     # Server process control & auth
│       ├── ThinkingProxy.swift     # Extended thinking request modifier (port 8317)
│       ├── OllamaProxy.swift      # Ollama-compatible API server (port 11434)
│       ├── TunnelManager.swift     # Network tunneling
│       ├── SettingsView.swift      # Main UI
│       ├── AuthStatus.swift        # Auth file monitoring
│       ├── IconCatalog.swift       # Icon management
│       ├── NotificationNames.swift # Notification constants
│       └── Resources/
│           ├── AppIcon.icns        # App icon
│           ├── cli-proxy-api-plus  # CLIProxyAPIPlus binary
│           ├── config.yaml         # CLIProxyAPIPlus config
│           ├── icon-active.png     # Menu bar icon (active)
│           ├── icon-inactive.png   # Menu bar icon (inactive)
│           └── icon-*.png          # Service icons (claude, codex, gemini, qwen, zai)
├── patches/                        # Git patches for additional features
├── scripts/                        # Release and utility scripts
├── create-app-bundle.sh            # App bundle creation script
├── Makefile                        # Build automation
└── CHANGELOG.md                    # Version history
```

### Key Components

- **AppDelegate**: Manages the menu bar item and settings window lifecycle
- **ServerManager**: Controls the CLIProxyAPIPlus server process and OAuth authentication
- **ThinkingProxy**: HTTP proxy (port 8317) that intercepts requests to add extended thinking parameters for Claude models and handles Kimi reasoning content
- **OllamaProxy**: Translates between Ollama API format and OpenAI API format (port 11434)
- **TunnelManager**: Network tunneling utilities
- **SettingsView**: SwiftUI interface with native macOS design
- **AuthStatus**: Monitors `~/.cli-proxy-api/` for authentication files with real-time updates

## Credits

VibeProxy is built on top of [CLIProxyAPIPlus](https://github.com/router-for-me/CLIProxyAPIPlus), an excellent unified proxy server for AI services with support for third-party providers.

Special thanks to the CLIProxyAPIPlus project for providing the core functionality that makes VibeProxy possible.

## License

MIT License - see LICENSE file for details

## Support

- **Report Issues**: [GitHub Issues](https://github.com/automazeio/vibeproxy/issues)
- **Website**: [automaze.io](https://automaze.io)

---

© 2025-2026 [Automaze, Ltd.](https://automaze.io) All rights reserved.
