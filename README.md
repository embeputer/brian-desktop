# Brian Desktop

A native macOS client for [Brian](https://github.com/embeputer/brian). The app is a client of the harness, not another agent.

On first launch you choose one of two paths. The choice is stored in UserDefaults under `dev.brian.desktop.connection` and later launches skip the screen and use it again. Change is in the chat window.

- **Run on this Mac.** The app looks for `brian` on `PATH` (and `BRIAN_BIN`). If it is missing, the app runs `npm install -g --ignore-scripts @brian-agent/cli`, then starts `brian --mode rpc`. Replies stream as JSONL text deltas. RPC has no network address; it is the child process's stdin and stdout.
- **Connect to a remote Brian.** This is `brian serve`, not RPC. You enter a host and port or a URL, plus the bearer token from that machine's `serve.json`. `brian serve` itself only speaks plain http, and the token is never sent over plain http to another machine: a bare `localhost`, `127.x.x.x`, or `[::1]` address uses `http://…:7333`, any other bare host uses https, and an `http://` URL to another machine is refused. Reach a remote serve through an https proxy in front of it, or an SSH tunnel (`ssh -L 7333:127.0.0.1:7333 host`) and `localhost:7333`. The app's App Transport Security exception covers `localhost` only. `POST /v1/prompt` returns one finished `{ "text" }` body, so the reply shows up all at once.

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

The first window is a welcome screen with Continue. The name is set in New Spirit. macOS does not include that face, so a licensed New Spirit or PP New Spirit file (`.otf` or `.ttf`) in `Sources/BrianDesktop/Resources/Fonts` is copied into the app and registered. The line under the name uses the same system font as “How would you like to run brian?”. The next window asks how you want to run Brian: on this Mac, or on a server that is already running `brian serve`. Welcome is stored at `dev.brian.desktop.welcome.seen` and is not shown again. After a connection is saved, later launches skip both screens and reconnect the same way. A local session uses your home directory as the working directory. Type a prompt and press ⌘↩.

Tools, in the chat window, is the rest of the local harness. It uses the same RPC session for the model, thinking level, slash commands, and the session (new, rename, open a file, clone, fork). It runs one-shot `brian` commands for skills, memory, routines, MCP servers, the saved default model, `auth check` for xAI and Codex, and a Beeper token. A remote connection only shows what `GET /v1/status` returns.

The window starts a little transparent (90% solid) and blurs the desktop behind that transparency. Brian → Settings → Appearance has a Fully solid toggle, a transparency slider, and a blur slider. The choice is stored in UserDefaults under `dev.brian.desktop.appearance.solid`, `dev.brian.desktop.appearance.transparency`, and `dev.brian.desktop.appearance.blur`.

To build the installer, on a Mac:

```bash
./Scripts/package-dmg.sh
open Brian.dmg
```

The disk image opens a window titled Install Brian. Brian is on the left, the Applications folder is on the right, and the background tells you to drag the app across. That window is written by Finder, so the script has to run on macOS. `./Scripts/package-macos-app.sh` only builds `Brian.app` and skips the disk image.

The app is not sandboxed. The `brian` child runs with your user permissions, which is the harness's own model.

## Updates

On launch, Brian checks the release feed. A failed check, or a Mac that is already on the newest release, does not show a dialog. When the feed has a newer version this Mac can install, a sheet appears:

> A new version of Brian is available
>
> Brian 0.2.0 is now available — you have 0.1.0. Would you like to download it now?

Release notes from the feed are shown under that sentence when the item includes them. **Later** dismisses the sheet until the next launch. **Install Update** downloads the `.dmg` or `.zip`, and the same sheet then says the version is ready to install. **Install and Relaunch** quits Brian, replaces this copy, and opens the new one. The same check is in the Brian menu as **Check for Updates…**. That menu item says **Brian is up to date** when nothing newer is installable.

The feed is a JSON appcast attached to the latest GitHub release:

`https://github.com/embeputer/brian-desktop/releases/latest/download/appcast.json`

The packaged app reads that URL from `SUFeedURL` in `Scripts/Info.plist`. `BRIAN_UPDATE_FEED` overrides both when it is an https URL.

```json
{
  "items": [
    {
      "version": "0.2.0",
      "build": "2",
      "minimumSystemVersion": "14.0",
      "downloadURL": "https://github.com/embeputer/brian-desktop/releases/download/v0.2.0/Brian.dmg",
      "releaseNotes": "What changed.",
      "length": 12000000
    }
  ]
}
```

`version` is `CFBundleShortVersionString`. `build` is `CFBundleVersion`. A single object, without the `items` array, is the same as a one-entry feed. The download URL has to be https, and its path has to end in `.dmg` or `.zip`. The archive contains `Brian.app` with bundle id `dev.brian.desktop`, and that bundle's version has to match the feed. `Scripts/package-dmg.sh` builds the disk image. A zip of `Brian.app` works the same way.

`.github/workflows/macos.yml` runs that script on `macos-latest` for every pull request and every push to `main`, then uploads `Brian.dmg` as a workflow artifact. Those runs do not create a GitHub release and do not change `appcast.json`.

A push of a tag named `v` plus `CFBundleShortVersionString` runs the same build and then creates the GitHub release for that tag. `v0.2.0` is the tag when the plist says `0.2.0`. The release assets are `Brian.dmg` and one `appcast.json`. That file is the feed at `https://github.com/embeputer/brian-desktop/releases/latest/download/appcast.json` once this release is the latest one. The item's `version` and `build` are the built app's, `length` is the disk image size in bytes, and `downloadURL` is `https://github.com/embeputer/brian-desktop/releases/download/v0.2.0/Brian.dmg` with that tag. One tag is one version: the file lists that release only.

The running app is the one that gets replaced. If you started Brian with `swift run` and it is not an app bundle, the install goes to `/Applications/Brian.app`, or `~/Applications/Brian.app` when `/Applications` is not writable. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Scripts/Info.plist` before tagging that version. The release job stops when the tag and the built app disagree. The fallback used when the binary has no bundle plist is the same pair (`0.1.0` / `1` until that file changes).

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

That covers JSONL framing (including a `U+2028` inside a record), command encoding, the saved connection choice, the install command, the release-feed check, both a scripted `brian serve` response and a fixture HTTP server that returns one `{ "text" }` body, and the JSON shapes for skills, memory, routines, MCP, auth check, and the RPC model and session commands.

## What this version keeps plain

Messages are user text, assistant text, and short status lines. When Brian emits a `delivery` record, the raw envelope is stored on the assistant message as `deliveryJSON` and is not rendered. A later generative UI can read that envelope without a second client.

Dialogs an extension asks for (`select`, `confirm`, `input`, `editor`) are cancelled, with a status line, so the process does not wait forever. Notifications are shown as status text.

`brian connect` and `brian login` need a terminal, so this window does not sign in to xAI, Codex, or any other provider. It can show whether those credentials are already saved, and it can switch the model after that. It does not start `brian routines daemon`, and it does not list session files: RPC can open a path, and `brian status` only counts the files. `brian serve` cannot list or change MCP servers, skills, memory, models, or sessions.
