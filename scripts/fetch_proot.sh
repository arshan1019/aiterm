#!/usr/bin/env bash
# Pulls proot and its shared-library deps from Termux's official apt repo,
# verifies each .deb against the SHA256 in the repo index, and installs
# them as jniLibs. Android only allows executing files from the app's
# native library dir, so that is where proot has to live.
set -euo pipefail

REPO="https://packages-cf.termux.dev/apt/termux-main"
ARCH="aarch64"
ABI="arm64-v8a"
OUT="$(cd "$(dirname "$0")/.." && pwd)/android/app/src/main/jniLibs/$ABI"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -fsSL "$REPO/dists/stable/main/binary-$ARCH/Packages" -o "$WORK/Packages"

fetch() {
  local pkg="$1" stanza file sha
  stanza="$(awk -v RS='' -v p="$pkg" '$0 ~ "^Package: " p "\n"' "$WORK/Packages")"
  file="$(sed -n 's/^Filename: //p' <<<"$stanza")"
  sha="$(sed -n 's/^SHA256: //p' <<<"$stanza")"
  [ -n "$file" ] && [ -n "$sha" ] || { echo "no index entry for $pkg" >&2; exit 1; }
  curl -fsSL "$REPO/$file" -o "$WORK/$pkg.deb"
  echo "$sha  $WORK/$pkg.deb" | sha256sum -c - >/dev/null
  mkdir -p "$WORK/$pkg"
  # Some sandboxes (e.g. proot on a phone) refuse chmod on symlinks and tar
  # exits non-zero; the copies below fail loudly if a file is really missing.
  (cd "$WORK/$pkg" && ar x "../$pkg.deb" && { tar --no-same-owner -xf data.tar.* 2>/dev/null || true; })
}

for p in proot libtalloc libandroid-shmem; do fetch "$p"; done

P=data/data/com.termux/files/usr
mkdir -p "$OUT"
cp -L "$WORK/proot/$P/bin/proot"                       "$OUT/libproot.so"
cp -L "$WORK/proot/$P/libexec/proot/loader"            "$OUT/libproot-loader.so"
cp -L "$WORK/libtalloc/$P/lib/libtalloc.so.2"          "$OUT/libtalloc.so"
cp -L "$WORK/libandroid-shmem/$P/lib/libandroid-shmem.so" "$OUT/libandroid-shmem.so"
echo "proot installed to $OUT"
