# Brian Desktop

A native macOS client for [Brian](https://github.com/embeputer/brian). The app launches a local `brian` process in RPC mode, sends a prompt, and shows the streamed reply. It does not reimplement the agent.

The wire format is Brian's RPC protocol: JSON records on the child's stdin and stdout, one object per line, separated by LF. There is no handshake. Diagnostics stay on stderr. `brian serve`'s HTTP API on port 7333 returns a finished `{ "text" }` body and does not stream, so this app does not use it.

## Requirements

- macOS 14 or later
- Swift 5.9 or later (Xcode 15 or a Swift toolchain)
- A local `brian` binary on `PATH`, or `BRIAN_BIN` pointing at one

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

The window starts `brian --mode rpc --no-session` with your home directory as the working directory. Type a prompt and press ⌘↩. Text deltas appear as they arrive. Reconnect starts a fresh process.

To wrap a double-clickable app:

```bash
./Scripts/package-macos-app.sh
open Brian.app
```

The app is not sandboxed. The `brian` child runs with your user permissions, which is the harness's own model.

If macOS's short GUI `PATH` hides the binary, paste its path into the field at the top of the window. The app also looks in `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, and `~/.npm-global/bin`.

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

That covers JSONL framing (including a `U+2028` inside a record), command encoding, and a fixture process that speaks the same records as `brian --mode rpc`.

## What this version keeps plain

Messages are user text, assistant text, and short status lines. When Brian emits a `delivery` record, the raw envelope is stored on the assistant message as `deliveryJSON` and is not rendered. A later generative UI can read that envelope without a second client.

Dialogs an extension asks for (`select`, `confirm`, `input`, `editor`) are cancelled, with a status line, so the process does not wait forever. Notifications are shown as status text.
