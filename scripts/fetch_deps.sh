#!/usr/bin/env bash
# Fetches prebuilt native dependencies, each checked against a SHA256:
#  - proot + libs from Termux's apt repo (hashes from the signed repo index),
#    installed as jniLibs because Android only lets an app exec files from
#    its native library dir;
#  - Needle's Android engine (libneedle.a + needle.h) from a pinned
#    Hugging Face revision, linked into our JNI library by CMake.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- proot ---------------------------------------------------------------
REPO="https://packages-cf.termux.dev/apt/termux-main"
JNI="$ROOT/android/app/src/main/jniLibs/arm64-v8a"
curl -fsSL "$REPO/dists/stable/main/binary-aarch64/Packages" -o "$WORK/Packages"

fetch_deb() {
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

for p in proot libtalloc libandroid-shmem; do fetch_deb "$p"; done
P=data/data/com.termux/files/usr
mkdir -p "$JNI"
cp -L "$WORK/proot/$P/bin/proot"                          "$JNI/libproot.so"
cp -L "$WORK/proot/$P/libexec/proot/loader"               "$JNI/libproot-loader.so"
cp -L "$WORK/libtalloc/$P/lib/libtalloc.so.2"             "$JNI/libtalloc.so"
cp -L "$WORK/libandroid-shmem/$P/lib/libandroid-shmem.so" "$JNI/libandroid-shmem.so"

# --- Needle --------------------------------------------------------------
HF="https://huggingface.co/Cactus-Compute/needle3/resolve/93e88ede867e4311c39151285e74df513e4b835b/android-arm64"
NEEDLE="$ROOT/android/app/src/main/cpp/third_party/needle"
mkdir -p "$NEEDLE"
curl -fsSL "$HF/libneedle.a" -o "$NEEDLE/libneedle.a"
curl -fsSL "$HF/needle.h" -o "$NEEDLE/needle.h"
sha256sum -c - >/dev/null <<EOF
9be8b4b185ef1710f57179e3cc68835ac67fca8470bdbc6915d6966646d95385  $NEEDLE/libneedle.a
a27dac4b3239eead91d124b7f7dbce5495c13019903fd817b68c16d39b055a99  $NEEDLE/needle.h
EOF

echo "native deps installed"
