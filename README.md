# Ghostty build and install

Builds [Ghostty](https://ghostty.org) for Linux inside Docker and installs the binary and its `share/` files into `~/.local`. Builds **1.4.0** unless you pick another version.

## Usage

```sh
./build-install.sh                 # build 1.4.0, then install into ~/.local
./build-install.sh --version 1.4.1 # build and install a different release
./build-install.sh --build-only    # build into out/<version>/ only
./build-install.sh --install-only  # install an existing out/<version>/ build
./build-install.sh --force         # build even if free memory is low
PREFIX=/some/dir ./build-install.sh   # install somewhere other than ~/.local
```

`--version` takes a release number such as `1.4.0`, and combines with the other flags.

When it finishes, quit any running Ghostty fully (`Ctrl+Shift+Q`) and relaunch it. A running instance keeps using the old build.

You need Docker with BuildKit, plus `curl` and `jq` on the host. `mise.toml` provides `jq` (and `shellcheck`, for linting the script): run `mise install` in this folder. Docker and `curl` come from your system. The build takes a few minutes and uses about 11 GB of memory, so the script refuses to start with less than 14 GiB free.

## What it does

1. Takes the Ghostty version from `--version` (default set by `default_version` in the script).
2. Looks up the Zig version that release needs (`minimum_zig_version` in its `build.zig.zon`) and that Zig release's SHA256 from <https://ziglang.org/download/index.json>.
3. Builds in an Ubuntu 26.04 container, passing the three values to the `Dockerfile` as build args. It downloads the Zig compiler (SHA256 checked) and the official Ghostty source tarball (minisign signature checked), then runs `zig build -Doptimize=ReleaseFast`.
4. Exports the binary and `share/` to `out/<version>/`.
5. Installs them:
   - `~/.local/bin/ghostty`
   - `~/.local/share/*`, which holds themes, shell integration, terminfo, the desktop launcher, and systemd and D-Bus files. `pkgconfig` is skipped.
6. Rewrites the launcher files to use the absolute binary path, then reloads the systemd user manager. Without this the launcher fails, because systemd doesn't search `~/.local/bin`.
7. Checks the installed binary reports the right version and finds its themes.

Ghostty finds its resources relative to the binary, so keep `share/` beside `bin/` (for example, `~/.local/bin` and `~/.local/share`).

## Upgrading to a new Ghostty version

Run `./build-install.sh --version X.Y.Z`. The Zig version and checksum are looked up automatically, so there is nothing else to edit. To make a new release the default, change `default_version` at the top of `build-install.sh`.

The `Dockerfile` needs the `GHOSTTY_VERSION`, `ZIG_VERSION` and `ZIG_SHA256` build args, so run it through the script rather than with plain `docker build`.

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
