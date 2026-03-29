# Chrome CDP Setup

> One-click Chrome DevTools Protocol setup for [OpenClaw](https://github.com/openclaw/openclaw) browser automation.

Let AI agents control your **real Chrome browser** — with all your login sessions, cookies, and extensions intact.

## ✨ Features

- 🔍 **Auto-detect** Chrome / Chromium / Brave / Edge on macOS & Linux
- 🔗 **Profile symlink** — reuse your existing Chrome profile (logins, cookies, extensions)
- 🚀 **Auto-start** — LaunchAgent (macOS) / systemd (Linux), Chrome launches on boot
- 🛡️ **Proxy SSRF fix** — one-click patch for Surge / Clash / Quantumult X users
- ✅ **Diagnostic tool** — verify CDP connectivity with a single command

## Quick Start

```bash
# 1. Setup (one-time)
bash scripts/setup.sh

# 2. Verify
bash scripts/verify.sh

# 3. Fix proxy SSRF (only if using Surge/Clash)
bash scripts/patch-ssrf.sh
```

## How It Works

Chrome refuses `--remote-debugging-port` on its default user-data directory. This tool creates `~/.chrome-cdp-data/` with:

- Copies of `Local State` and `First Run` from your real Chrome profile
- A symlink `Default` → your original Chrome profile's `Default` directory

All login state, cookies, and extensions are preserved. CDP listens on `127.0.0.1:9222` (configurable via `CDP_PORT`).

## Auto-Start

| Platform | Method | Location |
|----------|--------|----------|
| macOS | LaunchAgent | `~/Library/LaunchAgents/com.openclaw.chrome-cdp.plist` |
| Linux | systemd user | `~/.config/systemd/user/chrome-cdp.service` |

## Proxy Users (Surge / Clash)

If you use proxy software with fake-IP DNS mode (198.18.x.x), OpenClaw's SSRF protection will block CDP connections and media downloads. Run `patch-ssrf.sh` to fix. **Re-run after every OpenClaw update.**

## Troubleshooting

See [references/troubleshooting.md](references/troubleshooting.md) for 8 common issues with fixes.

## Structure

```
├── SKILL.md                    # OpenClaw skill metadata
├── scripts/
│   ├── setup.sh                # One-click setup (11 steps)
│   ├── verify.sh               # Diagnostic report (5 checks)
│   └── patch-ssrf.sh           # Proxy SSRF fix
└── references/
    └── troubleshooting.md      # Common issues & fixes
```

## License

MIT

---

# Chrome CDP 一键配置

> 为 [OpenClaw](https://github.com/openclaw/openclaw) 浏览器自动化提供一键 Chrome DevTools Protocol 配置。

让 AI Agent 直接控制你的 **真实 Chrome 浏览器** —— 保留所有登录状态、Cookie 和扩展。

## ✨ 功能

- 🔍 **自动检测** Chrome / Chromium / Brave / Edge（macOS 和 Linux）
- 🔗 **Profile 软链接** —— 复用现有 Chrome 配置（登录态、Cookie、扩展全保留）
- 🚀 **开机自启** —— macOS LaunchAgent / Linux systemd，重启自动拉起
- 🛡️ **代理 SSRF 修复** —— Surge / Clash / Quantumult X 用户一键打 patch
- ✅ **诊断工具** —— 一条命令检查 CDP 连通性

## 快速开始

```bash
# 1. 安装（一次性）
bash scripts/setup.sh

# 2. 验证
bash scripts/verify.sh

# 3. 修复代理 SSRF（仅 Surge/Clash 用户需要）
bash scripts/patch-ssrf.sh
```

## 工作原理

Chrome 不允许在默认 user-data 目录上使用 `--remote-debugging-port`。本工具创建 `~/.chrome-cdp-data/`：

- 从真实 Chrome Profile 复制 `Local State` 和 `First Run`
- 将 `Default` 软链接到原始 Chrome Profile 的 `Default` 目录

所有登录状态、Cookie、扩展完整保留。CDP 监听 `127.0.0.1:9222`（可通过 `CDP_PORT` 自定义端口）。

## 代理用户注意

如果你使用 Surge / Clash 等代理软件的 fake-IP DNS 模式（198.18.x.x），OpenClaw 的 SSRF 保护会拦截 CDP 连接和媒体下载。运行 `patch-ssrf.sh` 修复。**每次 OpenClaw 更新后需重新执行。**

## 常见问题

详见 [references/troubleshooting.md](references/troubleshooting.md)，覆盖 8 个常见场景。
