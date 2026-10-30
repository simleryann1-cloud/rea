#!/bin/bash
# Prepares a Linux host (cloud session or WSL2) to run REA from this checkout:
# pinned Node.js, locked dependencies, the build, Ghidra and the Claude Code
# registration. Safe to rerun; completed steps are skipped.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node_version="$(tr -d '[:space:]' < "$repo/.nvmrc")"
# A stable path keeps the Claude Code registration valid across Node upgrades.
node_dir="$HOME/.local/rea-node"
ghidra_url="https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.4_build/ghidra_12.1.4_PUBLIC_20260921.zip"
ghidra_sha256="ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db"
ghidra_dir="$HOME/.local/ghidra_12.1.4_PUBLIC"

log() { echo "[rea-env] $*" >&2; }

# Node.js: the system one is usually older than the engines range.
if [ "$("$node_dir/bin/node" -v 2>/dev/null)" != "v$node_version" ]; then
  log "installing Node.js $node_version"
  tmp="$(mktemp -d)"
  archive="node-v$node_version-linux-x64.tar.xz"
  curl -fsSL --retry 3 -o "$tmp/$archive" "https://nodejs.org/dist/v$node_version/$archive"
  (cd "$tmp" && curl -fsSL --retry 3 "https://nodejs.org/dist/v$node_version/SHASUMS256.txt" | grep " $archive\$" | sha256sum -c --status -)
  rm -rf "$node_dir" && mkdir -p "$node_dir"
  tar -xJf "$tmp/$archive" -C "$node_dir" --strip-components=1
  rm -rf "$tmp"
fi
export PATH="$node_dir/bin:$PATH"

# Dependencies: reinstall only when the manifests or this script change.
cd "$repo"
hashes=node_modules/.rea-env.sha256
if ! sha256sum --check --status "$hashes" 2>/dev/null; then
  rm -f "$hashes"
  log "installing dependencies"
  npm ci --no-audit --no-fund >&2
  sha256sum .claude/rea-env.sh package.json package-lock.json > "$hashes"
fi

# Build: turbo replays cached outputs when sources are unchanged.
npm run build:cached >&2

# Ghidra: checksum-pinned release used by the repository's own CI.
if [ ! -f "$ghidra_dir/Ghidra/application.properties" ]; then
  log "installing Ghidra 12.1.4"
  tmp="$(mktemp -d)"
  curl -fsSL --retry 3 -o "$tmp/ghidra.zip" "$ghidra_url"
  echo "$ghidra_sha256  $tmp/ghidra.zip" | sha256sum -c --status -
  unzip -q "$tmp/ghidra.zip" -d "$tmp"
  rm -rf "$ghidra_dir" && mv "$tmp/ghidra_12.1.4_PUBLIC" "$ghidra_dir"
  rm -rf "$tmp"
fi
export GHIDRA_INSTALL_DIR="$ghidra_dir"
command -v java >/dev/null || log "Java 21+ JDK not found; Ghidra needs it (Ubuntu: sudo apt install openjdk-21-jdk)"

# `rea` on PATH, pointing at this checkout.
printf '#!/bin/sh\nexec "%s" "%s" "$@"\n' "$node_dir/bin/node" "$repo/scripts/rea.mjs" > "$node_dir/bin/rea"
chmod +x "$node_dir/bin/rea"

# Register the MCP server and skill with Claude Code (idempotent, with backup).
setup_log="$(mktemp)"
if ! rea setup --client claude_code --yes > "$setup_log" 2>&1; then
  cat "$setup_log" >&2
  exit 1
fi
rm -f "$setup_log"

# Make the environment visible to later shells.
exports="export PATH=\"$node_dir/bin:\$PATH\"; export GHIDRA_INSTALL_DIR=\"$ghidra_dir\""
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "$exports" >> "$CLAUDE_ENV_FILE"
elif ! grep -qF "# rea-env" "$HOME/.bashrc" 2>/dev/null; then
  echo "$exports # rea-env" >> "$HOME/.bashrc"
  log "added Node.js and GHIDRA_INSTALL_DIR to ~/.bashrc; open a new shell"
fi
log "ready"
