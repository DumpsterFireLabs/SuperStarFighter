#!/bin/sh
# Pass Godot game options unchanged. exec preserves signals and exit status.
set -eu
server_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case "$(uname -m)" in
    x86_64|amd64) server_arch=x86_64 ;;
    aarch64|arm64) server_arch=arm64 ;;
    *) echo 'Unsupported architecture: requires Linux x64 or ARM64.' >&2; exit 1 ;;
esac
server_binary="$server_dir/SuperStarFighter-Server.$server_arch"
if [ ! -x "$server_binary" ]; then
    echo "Missing executable: $server_binary (check package architecture and chmod +x)." >&2
    exit 1
fi
exec "$server_binary" --headless -- "$@"
