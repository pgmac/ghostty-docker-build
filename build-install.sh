#!/usr/bin/env bash
# Build Ghostty in Docker (see ./Dockerfile) and install the binary and
# share/* into ~/.local.
#
# Usage: build-install.sh [--version VERSION] [--build-only | --install-only] [--force]
#   --version VERSION  Ghostty release to build/install, e.g. 1.4.0 (default: $default_version)
#   --build-only       build into out/<version>/ but don't install
#   --install-only     install an existing out/<version>/ without building
#   --force            build even if free memory is below the safe minimum
#
# The Zig version and its checksum are looked up for the chosen release.
# Environment: PREFIX overrides the install prefix (default ~/.local).
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dockerfile=$here/Dockerfile
prefix=${PREFIX:-$HOME/.local}
default_version=1.4.0
version=$default_version
# zig peaks around 11 GB during the build; an OOM here took down the session
min_mem_gib=14

do_build=1
do_install=1
force=0

die() {
    echo "error: $*" >&2
    exit 1
}

while (($#)); do
    case $1 in
        --version)
            (($# >= 2)) || die "--version needs a value"
            version=$2
            shift
            ;;
        --build-only) do_install=0 ;;
        --install-only) do_build=0 ;;
        --force) force=1 ;;
        -h | --help)
            sed -n '2,/^set /p' "$0" | sed '$d; s/^# \{0,1\}//; s/\$default_version/'"$default_version"'/'
            exit 0
            ;;
        *) die "unknown argument: $1 (try --help)" ;;
    esac
    shift
done

[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 1.4.0, got '$version'"
outdir=$here/out/$version

# Sets zig_version and zig_sha256 for the Zig release this Ghostty version needs
resolve_zig() {
    command -v curl >/dev/null || die "curl not found"
    command -v jq >/dev/null || die "jq not found"

    zig_version=$(curl -fsSL "https://raw.githubusercontent.com/ghostty-org/ghostty/v$version/build.zig.zon" |
        sed -n 's/.*\.minimum_zig_version = "\([^"]*\)".*/\1/p') ||
        die "can't fetch build.zig.zon for Ghostty v$version (does that release exist?)"
    [[ -n $zig_version ]] || die "no minimum_zig_version in Ghostty v$version build.zig.zon"

    zig_sha256=$(curl -fsSL https://ziglang.org/download/index.json |
        jq -r --arg v "$zig_version" '.[$v]["x86_64-linux"].shasum // empty') ||
        die "can't fetch the Zig release index"
    [[ -n $zig_sha256 ]] || die "no x86_64-linux build of Zig $zig_version in the release index"
}

build() {
    command -v docker >/dev/null || die "docker not found"

    local avail_gib
    avail_gib=$(awk '/^MemAvailable:/ {print int($2 / 1048576)}' /proc/meminfo)
    if ((avail_gib < min_mem_gib && !force)); then
        die "only ${avail_gib} GiB memory available, build needs ~${min_mem_gib} GiB. Close heavy apps or use --force"
    fi

    resolve_zig
    echo "==> Building Ghostty $version with Zig $zig_version into $outdir"
    mkdir -p "$outdir"
    # The Dockerfile comes in on stdin so no build context is sent
    DOCKER_BUILDKIT=1 docker build \
        --build-arg "GHOSTTY_VERSION=$version" \
        --build-arg "ZIG_VERSION=$zig_version" \
        --build-arg "ZIG_SHA256=$zig_sha256" \
        --output "type=local,dest=$outdir" - <"$dockerfile"
}

install_files() {
    [[ -x $outdir/ghostty && -d $outdir/share ]] ||
        die "nothing to install in $outdir, run without --install-only first"

    echo "==> Installing into $prefix"
    mkdir -p "$prefix/bin" "$prefix/share"

    # Rename into place: copying over a running binary fails with "Text file busy"
    install -m 755 "$outdir/ghostty" "$prefix/bin/.ghostty.new"
    mv -f "$prefix/bin/.ghostty.new" "$prefix/bin/ghostty"

    # Drop the old themes and shell integration so removed files don't linger
    rm -rf "$prefix/share/ghostty"
    local dir
    for dir in "$outdir"/share/*; do
        # pkgconfig files point at the build container's paths
        [[ $(basename "$dir") == pkgconfig ]] && continue
        cp -a "$dir" "$prefix/share/"
    done

    # systemd and D-Bus look up a bare "ghostty" in their own default path, not
    # the session PATH, so the launcher fails. Use the absolute path instead.
    local file
    for file in \
        "$prefix/share/systemd/user/app-com.mitchellh.ghostty.service" \
        "$prefix/share/dbus-1/services/com.mitchellh.ghostty.service" \
        "$prefix/share/applications/com.mitchellh.ghostty.desktop"; do
        sed -i -E "s|^(ExecStart=)ghostty |\1$prefix/bin/ghostty |; s|^(Exec=)ghostty |\1$prefix/bin/ghostty |; s|^(TryExec=)ghostty\$|\1$prefix/bin/ghostty|" "$file"
    done

    if [[ $prefix == "$HOME/.local" ]]; then
        systemctl --user daemon-reload
    fi
}

verify() {
    local reported themes
    reported=$("$prefix/bin/ghostty" --version | sed -n '1s/^Ghostty //p')
    [[ $reported == "$version" ]] || die "installed binary reports '$reported', expected '$version'"
    themes=$(env -u GHOSTTY_RESOURCES_DIR "$prefix/bin/ghostty" +list-themes --plain | wc -l)
    ((themes > 0)) || die "installed binary can't find its resources under $prefix/share"
    echo "==> Ghostty $reported installed ($themes themes found)"

    if pgrep -u "$USER" -x ghostty >/dev/null; then
        echo "Ghostty is running the previous build. Quit it fully (Ctrl+Shift+Q) and relaunch."
    fi
}

((do_build)) && build
((do_install)) && install_files && verify
exit 0
