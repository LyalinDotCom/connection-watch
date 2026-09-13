# ConnectionWatch

A macOS menu bar app that tells you whether your internet is actually working — and if not, which part is broken.

![ConnectionWatch popover showing connection health, ping and HTTP latency, and a latency chart](docs/screenshot.png)

## Why

Most connection monitors answer one question: *is there a link?* That's rarely the question you actually have. Your Wi-Fi says connected, your video call is stuttering, and you want to know whether it's your laptop, your router, or your ISP.

ConnectionWatch runs two independent probes and scores them separately, so the failure mode is visible:

- **Ping (ICMP)** — a 3-packet burst that measures raw network latency, jitter, and packet loss.
- **HTTP** — a `HEAD` request that measures real time-to-first-byte, which is what your browser actually feels.

When those two disagree, that *is* the diagnosis. Ping fine but HTTP slow means DNS or the far end. Both spiking together means your local link. High jitter with no loss means a congested Wi-Fi channel.

**It stays out of the way.** Background probes cost roughly 100 bytes every 10 seconds. The download speed test only ever runs when you click the button — a monitor that saturates your connection to measure it is measuring its own interference.

**It doesn't cry wolf.** Plenty of corporate, hotel, and VPN networks silently drop ICMP. ConnectionWatch detects that and scores on HTTP alone instead of showing a permanent red light on a perfectly good connection. State changes use a hysteresis band so a connection hovering at a threshold doesn't flap between good and degraded.

## Features

- Live latency or health score right in the menu bar
- 0–100 health score from latency, jitter, packet loss, and HTTP response time
- Plain-language diagnostics — *"High jitter (±35ms)"*, *"ICMP filtered (using HTTP only)"*
- Latency chart with Wave, Bars, and Pulse views, plus avg/min/max and loss
- On-demand download speed test
- Notifications when the connection changes state, rate limited so they don't nag
- Pause monitoring when you don't want it running
- Configurable ping target, probe interval, and thresholds
- Launch at login
- Universal binary — Apple Silicon and Intel

## Install

Grab the latest `.zip` from [**Releases**](../../releases), unzip, and drag **ConnectionWatch.app** to your Applications folder.

Builds are ad-hoc signed but not notarized by Apple, so Gatekeeper blocks the first launch. Right-click the app → **Open** → **Open**. If macOS insists the app is damaged, clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/ConnectionWatch.app
```

Requires macOS 14 or later.

## Build from source

```sh
git clone https://github.com/LyalinDotCom/connection-watch.git
cd connection-watch
xcodebuild -scheme ConnectionWatch -configuration Release build
```

Run the tests with:

```sh
xcodebuild -scheme ConnectionWatchTests -destination 'platform=macOS' test
```

No dependencies, no package manager — just open `ConnectionWatch.xcodeproj` in Xcode if you prefer.

## How it works

A polling loop runs the ICMP and HTTP probes in parallel every 10 seconds, dropping to 5 seconds while the connection is degraded or just after a network change. Results land in a 240-sample ring buffer.

The health score weights ping latency at 35%, stability (packet loss and jitter) at 35%, and HTTP latency at 30%. Severe problems — a failed HTTP probe, heavy packet loss — force a degraded state regardless of the arithmetic. Only a genuinely unreachable network reports as disconnected; a slow-but-working link is always degraded, never "down".

HTTP probes rotate across Google, Cloudflare, and Apple connectivity-check endpoints and fall back to a second host before reporting a failure, so one CDN hiccup doesn't trigger a false alarm.

The app isn't sandboxed, because it shells out to `/sbin/ping`.

## Project status

This is a side hobby project. I build it for myself, I work on it when I feel like it, and there's no roadmap or support commitment.

**I'm not accepting pull requests or taking feature requests.** Please don't open PRs — I won't merge them. Bug reports are fine if something is genuinely broken, but I make no promises about fixing them.

If you want it to do something different, fork it. That's what the license is for.

## License

[Apache License 2.0](LICENSE). Copy it, fork it, ship it, do whatever you want with it.
