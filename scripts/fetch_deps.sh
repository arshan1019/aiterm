#!/usr/bin/env bash
# Fetches native dependencies, each checked against a SHA256:
#  - libtalloc + libandroid-shmem from Termux's apt repo (hashes from the
#    signed repo index), and proot built from Termux's source at a pinned
#    commit with the NDK (see below). Installed as jniLibs because Android
#    only lets an app exec files from its native library dir;
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

for p in libtalloc libandroid-shmem; do fetch_deb "$p"; done
P=data/data/com.termux/files/usr
mkdir -p "$JNI"
cp -L "$WORK/libtalloc/$P/lib/libtalloc.so.2"             "$JNI/libtalloc.so"
cp -L "$WORK/libandroid-shmem/$P/lib/libandroid-shmem.so" "$JNI/libandroid-shmem.so"

# proot from Termux's source, ahead of the packaged v5.1.107.96: commit
# b5af02e7 stops /proc/self/uid_map reads returning an empty map ("user
# namespace without a mapping": Claude Code's cross-session messaging
# turned itself off) and keeps SO_PEERCRED consistent across the one
# proot per terminal tab we run. Built like Termux's package (build.sh).
PROOT_COMMIT=b8c1f5c5c6730dc9d521d5bd5ce1cfeedecde087
PROOT_SHA256=b2dd751e3e4083f4a7dd2104a6330daa3823e9c2410d2a5bd43bfa97ea989d42
PROOT_CACHE="${PROOT_CACHE:-$ROOT/build/proot-$PROOT_COMMIT}"
if [ ! -f "$PROOT_CACHE/proot" ] || [ ! -f "$PROOT_CACHE/loader" ]; then
  NDK="${ANDROID_NDK_LATEST_HOME:-${ANDROID_NDK_HOME:-$(ls -d "${ANDROID_HOME:-/usr/local/lib/android/sdk}"/ndk/* | sort -V | tail -1)}}"
  BIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
  curl -fsSL "https://github.com/termux/proot/archive/$PROOT_COMMIT.tar.gz" -o "$WORK/proot.tar.gz"
  echo "$PROOT_SHA256  $WORK/proot.tar.gz" | sha256sum -c - >/dev/null
  tar -xzf "$WORK/proot.tar.gz" -C "$WORK"
  SRC="$WORK/proot-$PROOT_COMMIT"
  # The fix this build exists for.
  grep -q '(flags & O_ACCMODE) == O_RDONLY' "$SRC/src/syscall/enter.c"
  # Headers and link libraries from the Termux packages above.
  mkdir -p "$WORK/sysroot/include" "$WORK/sysroot/lib"
  cp -r "$WORK/libtalloc/$P/include/." "$WORK/libandroid-shmem/$P/include/." "$WORK/sysroot/include/"
  cp -L "$WORK/libtalloc/$P/lib/libtalloc.so" "$WORK/libandroid-shmem/$P/lib/libandroid-shmem.so" "$WORK/sysroot/lib/"
  make -C "$SRC/src" -j"$(nproc)" proot \
    CC="$BIN/aarch64-linux-android24-clang" STRIP="$BIN/llvm-strip" \
    OBJCOPY="$BIN/llvm-objcopy" OBJDUMP="$BIN/llvm-objdump" \
    PROOT_WITH_LIBANDROID_SHMEM=true PROOT_UNBUNDLE_LOADER=/unused HAS_LOADER_32BIT= \
    CPPFLAGS="-I$WORK/sysroot/include -DARG_MAX=131072 -DVERSION=\\\"5.1.107.96-g${PROOT_COMMIT:0:8}\\\"" \
    LDFLAGS="-L$WORK/sysroot/lib"
  mkdir -p "$PROOT_CACHE"
  "$BIN/llvm-strip" -o "$PROOT_CACHE/proot" "$SRC/src/proot"
  cp "$SRC/src/loader/loader" "$PROOT_CACHE/loader"
fi
cp "$PROOT_CACHE/proot"  "$JNI/libproot.so"
cp "$PROOT_CACHE/loader" "$JNI/libproot-loader.so"

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
