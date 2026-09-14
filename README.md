# Connection Watch

A macOS menu bar app that tells you whether your internet is actually working — and when it isn't, which part broke.

![Connection Watch showing connection health, ping and HTTP latency, and a latency chart](docs/screenshot.png)

## Why it's useful

"Connected" doesn't mean working. Connection Watch runs two independent probes — an ICMP ping burst and an HTTP request — and scores them separately, so when they disagree you get a diagnosis instead of a green dot:

| Symptom | Likely cause |
| --- | --- |
| Ping fine, HTTP slow | DNS or the far end |
| Both spiking together | Your local link |
| High jitter, no loss | Congested Wi-Fi |

It's quiet by design — background monitoring is one ping burst and one HTTP `HEAD` request every 10 seconds. The download speed test only runs when you press the button, because a monitor that saturates your connection to measure it is mostly measuring itself.

It also won't cry wolf. Plenty of corporate, hotel, and VPN networks silently drop ICMP. Connection Watch notices and scores on HTTP alone instead of parking a red light on a perfectly good connection.

## Features

- Live latency or health score right in the menu bar
- 0–100 health score from latency, jitter, packet loss, and HTTP response time
- Plain-language diagnostics — *"High jitter (±35ms)"*, *"ICMP filtered (using HTTP only)"*
- Latency chart with avg / min / max and packet loss
- On-demand download speed test
- **7-day rolling SQLite telemetry** with Wi-Fi SSID & interface type tracking (`Wi-Fi`, `Personal Hotspot / Tether`, `Ethernet`, `VPN`)
- **Companion CLI (`connection-watch`)** bundled inside the app with automatic `~/.local/bin/connection-watch` installation
- **One-click "Copy AI Skill"** button to equip any AI coding/system agent with full instructions to analyze your 7-day network history
- Notifications on state changes, rate limited so they don't nag
- Configurable ping target, probe interval, and thresholds
- Launch at login · Universal binary (Apple Silicon + Intel)

## Companion CLI & AI Agent Telemetry (`connection-watch`)

`Connection Watch.app` embeds a companion CLI executable at `Connection Watch.app/Contents/MacOS/connection-watch` and automatically links it into `~/.local/bin/connection-watch` (or `/usr/local/bin/connection-watch`) on launch.

All network probes, speed test benchmarks, app start/stop events, interface handoffs, and Wi-Fi network names (SSIDs) are persisted in a rolling 7-day SQLite database at:

```text
~/Library/Application Support/ConnectionWatch/telemetry.sqlite
~/Library/Application Support/ConnectionWatch/latest_status.json
```

### Asking an AI Agent to Analyze Your Network

Click **"Copy AI Skill"** in the bottom bar of the menu bar popover (or in Settings) and paste it into your AI agent (Claude Code, Cursor, Gemini CLI, etc.). Your agent will immediately know where the CLI and SQLite database live and how to answer questions like:

- *"Did my Wi-Fi drop or spike during my 2 PM meeting?"*
- *"Compare my latency and packet loss on `HomeWiFi` vs `iPhone Hotspot` over the last 7 days."*
- *"What time of day has the worst packet loss?"*

### CLI Usage

```sh
# Live status, active interface/SSID, and database counts
connection-watch status

# 7-day analytical summary with P50/P95 latencies, uptime %, and per-SSID breakdown
connection-watch summary --since 7d

# List all degraded or disconnected incidents with diagnostic reasons (JSON supported)
connection-watch outages --since 24h --json

# Filter raw samples by latency spikes, packet loss, interface, or Wi-Fi SSID
connection-watch samples --since 6h --min-latency 150
connection-watch samples --since 24h --loss-only --ssid "HomeWiFi"

# List all download speed benchmarks run in the last 7 days
connection-watch speedtests --since 7d

# Run any read-only SQL query directly against the 7-day SQLite database
connection-watch sql "SELECT wifi_ssid, COUNT(*) AS probes, ROUND(AVG(ping_latency_ms),1) AS avg_ping_ms, ROUND(AVG(packet_loss_pct),2) AS avg_loss_pct FROM telemetry_samples GROUP BY wifi_ssid;"

# Output the full AI Agent Skill Markdown or CLI help
connection-watch skill
connection-watch --help
```

## Install

Requires macOS 14 or later.

### Option 1 — Download a build

1. Download the latest `.zip` from [**Releases**](../../releases).
2. Unzip it and drag **Connection Watch.app** into **Applications**.
3. **First launch only:** right-click the app → **Open** → **Open**.

> [!NOTE]
> Releases are ad-hoc signed but not notarized by Apple, so macOS blocks them on first launch. Step 3 gets you past it. If you instead see a *"damaged and can't be opened"* error, clear the quarantine flag:
> ```sh
> xattr -dr com.apple.quarantine "/Applications/Connection Watch.app"
> ```

### Option 2 — Build it yourself

```sh
git clone https://github.com/LyalinDotCom/connection-watch.git
cd connection-watch
xcodebuild -scheme ConnectionWatch -configuration Release -derivedDataPath build
open build/Build/Products/Release
```

No dependencies and no package manager — or just open `ConnectionWatch.xcodeproj` and hit Run.

## Heads up

This is a side hobby project. I build it for myself, on my own schedule, with no roadmap and no support.

**I'm not accepting pull requests or feature requests.** If you want it to work differently, fork it — that's what the license is for.

## License

[Apache 2.0](LICENSE). Copy it, fork it, ship it.
