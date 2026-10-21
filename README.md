# Amazon Quick Desktop for Linux (unofficial)

Run the **Amazon Quick desktop app on Linux**. Amazon ships Amazon Quick on desktop, the agentic AI assistant in the Amazon Quick suite (alongside Quick Sight), only for Windows and macOS. This project builds a working Linux version on your own machine from Amazon's official Windows installer: the app's Electron interface runs natively, and its Windows helper runs under [Wine](https://www.winehq.org/).

It works on Arch, Fedora, Ubuntu, Debian and other x86-64 distributions, on both Wayland and X11, and it updates itself when Amazon publishes a new release.

> **Unofficial.** This project is not affiliated with, endorsed by, or supported by Amazon or AWS. It contains no Amazon code or binaries. The build script downloads the official installer from Amazon and assembles the app locally, for your own use under your organization's Amazon Quick subscription. Don't redistribute the built app.

## Contents

- [Quick start](#quick-start)
- [Requirements](#requirements)
- [Signing in](#signing-in)
- [Updates](#updates)
- [How it works](#how-it-works)
- [Wine fixes this project applies](#wine-fixes-this-project-applies)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [Known limitations](#known-limitations)
- [FAQ](#faq)

## Quick start

```sh
git clone https://github.com/babyhuey/amazon-quick-desktop-linux.git
cd amazon-quick-desktop-linux
./install.sh
```

The first build downloads about 700 MB (the Amazon installer plus Electron) and takes a few minutes. When it finishes, open **Amazon Quick** from your app menu or run `amazon-quick`. The first launch spends about 15 seconds setting up Wine.

`install.sh` also turns on a daily update check. Use `./install.sh --no-timer` to skip that and run `./update.sh` yourself.

## Requirements

- An x86-64 Linux desktop
- An Amazon Quick account on a plan that includes the desktop app, with desktop sign-in enabled by your Quick administrator
- A recent Wine release (tested with Wine 11.20), plus `winetricks` and `cabextract`
- 7-Zip (`7z` or `7zz`), `curl`, `python3`
- About 3 GB of free disk space
- Recommended: Chromium, Google Chrome, Edge or Brave for sign-in (see [Signing in](#signing-in))

Install the packages:

| Distribution | Command |
|---|---|
| Arch, Manjaro | `sudo pacman -S wine winetricks cabextract 7zip curl python` |
| Fedora | `sudo dnf install wine winetricks cabextract 7zip curl python3` |
| Ubuntu, Debian | `sudo apt install wine winetricks cabextract 7zip curl python3` |

Ubuntu and Debian ship older Wine releases. If the app doesn't start, install the current development build from [WineHQ](https://gitlab.winehq.org/wine/wine/-/wikis/Download).

## Signing in

Click **Continue with SSO** (or a social login). Amazon Quick opens a sign-in page in your browser, and the result comes back to the app automatically.

Sign-in needs a Quick web session in that browser. If you've never signed in to the Quick web console in that browser, you'll be asked to do so first. If you end up in the web console instead of back in the app, click **Continue with SSO** in the app again.

The app opens sign-in pages in the first Chromium-family browser it finds (Chromium, Chrome, Edge or Brave). It only falls back to your system default if none is installed. That's because Firefox often breaks this flow:

- **Container add-ons** (Multi-Account Containers, AWS SSO Containers, Granted) can open the sign-in page in a container that doesn't have your Quick session.
- **Strict Enhanced Tracking Protection** can block or partition the cookies the sign-in hands between Quick, AWS and your identity provider.

The result is a loop: you sign in, land in the web console, and the app never hears back. To use Firefox anyway, sign in to the Quick web console in the same container the sign-in tab opens in, or add exceptions for the Quick and identity provider domains. Then point the app at Firefox:

```sh
WINEPREFIX=~/.local/share/amazon-quick/wineprefix wine reg add 'HKCU\Software\Wine\WineBrowser' /v Browsers /t REG_SZ /d xdg-open /f
```

## Updates

The daily `amazon-quick-update.timer` (a systemd user timer) asks Amazon's download server whether the installer has changed. When it has, the timer rebuilds the app and shows a desktop notification. The new version is used the next time you start the app.

Every build is smoke-tested before it's switched in. If the test fails, you keep the version you had. Check the timer and its last run:

```sh
systemctl --user list-timers amazon-quick-update.timer
journalctl --user -u amazon-quick-update.service
```

To update right away, run `./update.sh`. Add `--force` to rebuild even if nothing changed.

Pull this repo now and then (`git pull`) to pick up fixes for new upstream releases.

## How it works

Amazon Quick on desktop has two parts:

1. **The interface**, an [Electron](https://www.electronjs.org/) app. Its JavaScript is the same on every platform and already handles Linux, so `build.sh` takes it from the Windows installer and runs it on the official Linux build of the matching Electron version.
2. **A local helper process.** In the shipping cloud mode, the AI itself runs in AWS. The helper signs you in, stores your token, and runs local tools such as file search, document conversion and local MCP servers. It's a compiled Windows program with no Linux build, so it runs under Wine. The interface talks to it over `localhost`, which works the same under Wine.

What `build.sh` does:

1. Downloads the official installer from Amazon (cached by ETag), and the matching Electron release for Linux from GitHub, verified against Electron's published SHA-256 checksums.
2. Unpacks the app into `~/.local/share/amazon-quick/app-<version>`.
3. Swaps in `files/quickwork-agent`, a small wrapper that the interface starts in place of the native helper. The wrapper runs the Windows helper under Wine and converts Linux paths to Windows paths.
4. Smoke-tests the new build, then points `~/.local/share/amazon-quick/current` at it. The previous build is kept, so updating never pulls files out from under a running copy.
5. Installs the `amazon-quick` launcher, the desktop entry and the `amazonquick://` and `awsquick://` link handlers.

On first launch, `files/setup-prefix.sh` creates a dedicated Wine prefix in `~/.local/share/amazon-quick/wineprefix`. Your default `~/.wine` is never touched.

## Wine fixes this project applies

Each of these breaks the app on stock Wine:

| Problem | Symptom | Fix |
|---|---|---|
| `wineboot` waits on a hidden "install Wine Mono/Gecko?" dialog | First launch hangs forever | `WINEDLLOVERRIDES="mscoree,mshtml="`; the helper needs neither .NET nor the built-in browser engine |
| Wine's `_locking()` doesn't set `errno` when a file lock is busy | Python `filelock` raises `OSError` (errno 0) instead of retrying, so sign-in state can't be read or saved | `winetricks ucrtbase2019` installs Microsoft's C runtime into the prefix |
| A Wine process can't start the Linux Electron binary as Node | `WinError 6` when the helper starts its network proxy or other Node tools | The wrapper points the helper at the Windows `node.exe` it already bundles |
| Windows Node crashes when it inherits a Linux pipe as stdio | `Error: open EBADF` from Node, and the proxy never reports its port | The wrapper sends the helper's stderr to a log file instead of a pipe |

The prefix is also limited to your user (`chmod 700`), because Wine only obfuscates the stored sign-in token.

## Troubleshooting

Log files:

| Log | What's in it |
|---|---|
| `~/.config/quickwork/logs/` | The interface's log, including helper startup (`[AgentBridge]`) |
| `~/.local/state/amazon-quick/agent.log` | The helper's own output |
| `~/.local/state/amazon-quick/prefix-setup.log` | First-run Wine setup |

Run the app from a terminal to watch it start:

```sh
amazon-quick
```

A healthy start includes `LEP proxy ready`, `Agent is ready` and `Window ready-to-show`.

Check that the helper starts under Wine, without touching your installed app or sign-in:

```sh
./smoke-test.sh ~/.local/share/amazon-quick/current
```

| Problem | What to try |
|---|---|
| First launch hangs | Look at `prefix-setup.log`. Delete `~/.local/share/amazon-quick/wineprefix` and launch again. You'll need to sign in again. |
| "Agent failed to start - timeout" | Check `agent.log`. Try a newer Wine release; this project is tested with 11.20. |
| Sign-in loops back to the web console | See [Signing in](#signing-in). Make sure a Chromium-family browser is installed, then delete the prefix so it picks the browser up. |
| Sign-in never returns to the app | `xdg-mime query default x-scheme-handler/amazonquick` should print `amazon-quick.desktop`. Re-run `./build.sh` to register it. |
| The window doesn't open on Wayland | Run `amazon-quick --ozone-platform=x11`. |
| The app says it's out of date | Run `./update.sh`. If the build fails, check this repo's issues for the upstream release. |

## Uninstall

```sh
./uninstall.sh          # removes the app, launcher and timer; keeps sign-in and settings
./uninstall.sh --purge  # also removes the Wine prefix, settings and ~/.quickwork
```

## Known limitations

- **Local folder access is the least tested feature.** The Windows helper sees your files as `Z:\home\...` paths.
- **Amazon's built-in auto-updater is turned off on Linux.** This project's update timer replaces it.
- **The sign-in token is kept in Wine's credential store,** not your desktop keyring.
- **x86-64 only.** There is no Windows on Arm build to start from.

## FAQ

**Is there an official Amazon Quick desktop app for Linux?**
Not as of this writing. Amazon offers the desktop app for Windows and macOS, the Quick web console in any browser, and browser extensions for Chrome, Edge and Firefox.

**Does this run Amazon Quick in a virtual machine?**
No. The interface runs natively, and only the small helper process runs under Wine.

**Why not port the helper to Linux?**
It's a compiled, protected Windows program. Running Amazon's unmodified build under Wine is simpler and needs no changes to Amazon's code.

**Does this send my data anywhere new?**
No. The app talks only to the same Amazon endpoints as the Windows version. This project adds no telemetry.

## Automation in this repository

`.github/workflows/upstream-check.yml` runs daily. When Amazon publishes a new installer, it test-builds the app on a GitHub runner with current WineHQ Wine and launches it headlessly. It then opens an issue labeled `upstream-release` with the result: passing results are closed right away, and failures stay open with logs. It never uploads the built app.

## License

The scripts and documentation in this repository are released under the [MIT License](LICENSE). Amazon Quick is a trademark of Amazon.com, Inc. or its affiliates. The app downloaded by `build.sh` is covered by Amazon's own terms.
