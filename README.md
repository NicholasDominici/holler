# Holler 👋

Ring someone's desk without standing up.

You're in an open office. The person you need is ten feet away — but they're
wearing headphones, and a Slack huddle feels absurd for someone you can
physically see. Holler is a tiny macOS menu bar app: everyone on the office
Wi-Fi shows up in the dropdown by name, you click one, and a banner slides in
under their menu bar — **"Hunter is pinging you 👋"** — with a ding. You get a
quiet ✓ in your menu bar confirming it landed. That's it. No accounts, no
server, no dismissal flow.

## Install

### Homebrew

```sh
brew install nicholasdominici/tap/holler
cp -R "$(brew --prefix)/opt/holler/Holler.app" /Applications/
open /Applications/Holler.app
```

Holler builds from source on your machine (a few seconds), so there are no
Gatekeeper warnings. Requires Xcode command line tools
(`xcode-select --install`).

### From source

```sh
git clone https://github.com/NicholasDominici/holler
cd holler
make install        # builds Holler.app and copies it to /Applications
open /Applications/Holler.app
```

### Direct download

Grab `Holler-x.y.z.zip` from the
[latest release](https://github.com/NicholasDominici/holler/releases/latest),
unzip, and drag Holler.app into /Applications. Because the app isn't
notarized, macOS will block the first launch — go to System Settings →
Privacy & Security and click **Open Anyway** (once per machine). The
Homebrew/source installs skip that dance entirely, which is why they're
listed first.

## How it works

- Each running copy advertises itself over **Bonjour** (`_holler._tcp`) on the
  local network and browses for everyone else. Discovery is automatic — open
  the menu and whoever's on the same Wi-Fi is just there.
- A ping is a one-shot TCP message straight to the other Mac. The receiver
  shows the banner, plays a sound, and acks; the sender's menu bar icon
  flashes ✓ (or ✕ with a warning if the peer couldn't be reached).
- Names are self-assigned (defaults to your macOS full name, change it any
  time from the menu) and stored locally in `UserDefaults`. Nothing leaves
  the local network.
- **Wired In** — need to focus? Menu → Wired In → 10 minutes / 30 minutes /
  1 hour. Your menu bar icon becomes headphones, everyone else sees
  "— Wired In" next to your name, and pings aimed at you are silently
  suppressed — the sender just sees "🎧 you're Wired In" instead of a ✓.
  It ends automatically (no indefinite mode on purpose).
- **Pause media on ping** (Settings…, off by default) — when someone pings
  you, Holler sends a system pause (like tapping ⏸) so you can hear them
  walking over.

100% native Swift + AppKit + Network.framework. No Electron, no dependencies,
no backend.

## First run

1. macOS will ask for **Local Network** permission — allow it, that's how
   Holler sees your coworkers. (If you denied it, re-enable in
   System Settings → Privacy & Security → Local Network.)
2. Holler asks for your name — this is what coworkers see in their menu.
3. Optionally enable **Launch at Login** from the menu.

## Usage

- Click the 👋 wave icon in the menu bar.
- Everyone else running Holler on the network is listed by name. Click one
  to ping them.
- They get a banner + ding; you get a brief ✓ on the menu bar icon.
- **Wired In** mutes incoming pings for 10/30/60 minutes and tells senders
  why their ping didn't land.
- **Settings…** has the optional pause-media-on-ping behavior.
- **Change My Name…** updates what others see, live.

## Notes

- Pings only reach people on the same network (and the network must allow
  peer-to-peer traffic / mDNS — most office Wi-Fi does; some guest networks
  isolate clients).
- The app is ad-hoc signed by your own build. First launch of a copy someone
  else built may require right-click → Open.

## Development

```sh
make run     # build the .app bundle and launch it
make app     # just build into build/Holler.app
make clean
```

Run the bundled `.app` rather than the bare `swift run` binary — local
network permission and login items are granted per app bundle.
