# Ghostty build and install

Builds [Ghostty](https://ghostty.org) for Linux inside Docker and installs the binary and its `share/` files into `~/.local`. Currently set up for **1.4.0**.

## Usage

```sh
./build-install.sh                 # build, then install into ~/.local
./build-install.sh --build-only    # build into out/<version>/ only
./build-install.sh --install-only  # install an existing out/<version>/ build
./build-install.sh --force         # build even if free memory is low
PREFIX=/some/dir ./build-install.sh   # install somewhere other than ~/.local
```

When it finishes, quit any running Ghostty fully (`Ctrl+Shift+Q`) and relaunch it. A running instance keeps using the old build.

You need Docker with BuildKit. The build takes a few minutes and uses about 11 GB of memory, so the script refuses to start with less than 14 GiB free.

## What it does

1. Reads `GHOSTTY_VERSION` from the `Dockerfile`.
2. Builds in an Ubuntu 26.04 container: downloads the Zig compiler (SHA256 checked) and the official Ghostty source tarball (minisign signature checked), then runs `zig build -Doptimize=ReleaseFast`.
3. Exports the binary and `share/` to `out/<version>/`.
4. Installs them:
   - `~/.local/bin/ghostty`
   - `~/.local/share/*`, which holds themes, shell integration, terminfo, the desktop launcher, and systemd and D-Bus files. `pkgconfig` is skipped.
5. Rewrites the launcher files to use the absolute binary path, then reloads the systemd user manager. Without this the launcher fails, because systemd doesn't search `~/.local/bin`.
6. Checks the installed binary reports the right version and finds its themes.

Ghostty finds its resources relative to the binary, so keep `share/` beside `bin/` (for example, `~/.local/bin` and `~/.local/share`).

## Upgrading to a new Ghostty version

Edit these lines at the top of the `Dockerfile`, then run `./build-install.sh`:

| Line | Where to find the value |
|---|---|
| `GHOSTTY_VERSION` | the release you want |
| `ZIG_VERSION` | `minimum_zig_version` in that release's `build.zig.zon` |
| `ZIG_SHA256` | `x86_64-linux` entry in <https://ziglang.org/download/index.json> |

Also check the new release's minimum GTK and libadwaita versions (in `src/apprt/gtk/gtk_version.zig` and `adw_version.zig`). If the base image is too old, change the `FROM` line. 1.4.0 needs GTK 4.18 and libadwaita 1.7, which is why this uses Ubuntu 26.04 rather than 24.04.

The official release tarball is used instead of a git checkout because it includes prebuilt UI resources, so no `blueprint-compiler` is needed.

## Troubleshooting

- **Build killed or desktop session crashed:** the build ran out of memory.
  Close heavy applications and run it again.
- **Launcher is slow or does nothing:** check
  `journalctl --user -u app-com.mitchellh.ghostty.service`. Re-running `./build-install.sh --install-only` re-applies the absolute paths.
- **No themes or shell integration:** the binary can't find `share/`. Check
  `echo $GHOSTTY_RESOURCES_DIR`. A shell started from an older Ghostty can carry a stale value, so open a fresh one.
- **`sudo` says the terminal type is unknown:** install the terminfo system-wide:

  ```sh
  sudo install -D ~/.local/share/terminfo/x/xterm-ghostty /usr/share/terminfo/x/xterm-ghostty
  ```
