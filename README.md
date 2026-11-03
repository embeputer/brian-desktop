# Brian Desktop

A native macOS client for [Brian](https://github.com/embeputer/brian). The app is a client of the harness, not another agent.

On first launch you choose one of two paths. The choice is stored in UserDefaults under `dev.brian.desktop.connection` and later launches skip the screen and use it again. Change is in the chat window.

- **Run on this Mac.** The app looks for `brian` on `PATH` (and `BRIAN_BIN`). If it is missing, the app runs `npm install -g --ignore-scripts @brian-agent/cli`, then starts `brian --mode rpc`. Replies stream as JSONL text deltas. RPC has no network address; it is the child process's stdin and stdout.
- **Connect to a remote Brian.** This is `brian serve`, not RPC. You enter a host and port or a URL, plus the bearer token from that machine's `serve.json`. `POST /v1/prompt` returns one finished `{ "text" }` body, so the reply shows up all at once.

An older build stored only an executable path in `dev.brian.desktop.executable`. That value is read as a local choice when the new setting is absent.

## Requirements

- macOS 14 or later
- Swift 5.9 or later (Xcode 15 or a Swift toolchain)
- Node.js 22.19 or newer, and npm, if you want the app to install `brian` for you. A remote connection needs a machine that is already running `brian serve`.

Install the CLI from the harness repo:

```bash
npm install -g --ignore-scripts @brian-agent/cli
brian --version
```

From a checkout of [embeputer/brian](https://github.com/embeputer/brian), build the package and point the app at the CLI entry (it has a `node` shebang):

```bash
npm install --ignore-scripts
npm run build
export BRIAN_BIN="$PWD/packages/coding-agent/dist/bundle/cli.js"
```

Provider credentials are the ones `brian` already uses (`~/.brian`, or the environment of the process that launches the app). Start the app from a terminal when those credentials live in your shell profile.

## Run

```bash
git clone https://github.com/embeputer/brian-desktop
cd brian-desktop
swift run BrianDesktop
```

The first window asks you to connect to `brian serve` or to install and start `brian` locally. After that, the app reconnects the same way. A local session uses your home directory as the working directory. Type a prompt and press ⌘↩.

To build the installer, on a Mac:

```bash
./Scripts/package-dmg.sh
open Brian.dmg
```

The disk image opens a window titled Install Brian. Brian is on the left, the Applications folder is on the right, and the background tells you to drag the app across. That window is written by Finder, so the script has to run on macOS. `./Scripts/package-macos-app.sh` only builds `Brian.app` and skips the disk image.

The app is not sandboxed. The `brian` child runs with your user permissions, which is the harness's own model.

If macOS's short GUI `PATH` hides the binary, choose Change and paste its path. Leave that field empty to search `PATH`, then `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/.npm-global/bin`, and `~/bin`. The saved JSON has `mode` (`local` or `remote`), `executablePath`, `remoteAddress`, and `remoteToken`. The token is the serve bearer token and is stored in UserDefaults with the rest of the choice.

`BRIAN_ARGS`, when set, replaces the default argument list entirely. Include `--mode rpc` yourself:

```bash
BRIAN_BIN=/usr/bin/node \
BRIAN_ARGS="/path/to/brian/packages/coding-agent/dist/bundle/cli.js --mode rpc --no-session" \
swift run BrianDesktop
```

`rpc-entry.js` already injects `--mode rpc`. Pass only the extra arguments:

```bash
BRIAN_BIN=/path/to/brian/packages/coding-agent/dist/bundle/rpc-entry.js \
swift run BrianDesktop
```

## Check the client

The RPC client is a library (`BrianClient`) with no SwiftUI dependency. On macOS or Linux:

```bash
swift test
```

That covers JSONL framing (including a `U+2028` inside a record), command encoding, the saved connection choice, the install command, and both a scripted `brian serve` response and a fixture HTTP server that returns one `{ "text" }` body.

## What this version keeps plain

Messages are user text, assistant text, and short status lines. When Brian emits a `delivery` record, the raw envelope is stored on the assistant message as `deliveryJSON` and is not rendered. A later generative UI can read that envelope without a second client.

Dialogs an extension asks for (`select`, `confirm`, `input`, `editor`) are cancelled, with a status line, so the process does not wait forever. Notifications are shown as status text.
