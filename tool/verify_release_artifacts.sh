#!/usr/bin/env bash
set -euo pipefail

platform="${1:?platform is required (android|linux|macos)}"
arch="${2:?arch is required}"
tag_name="${3:?tag_name is required}"
dist_dir="${4:?dist_dir is required}"
checksum_file="${5:?checksum_file is required}"

mkdir -p "$(dirname "$checksum_file")"

require_nonempty_min_bytes() {
  local file="$1"
  local min_bytes="$2"
  local size
  size="$(wc -c < "$file")"
  if [ "$size" -lt "$min_bytes" ]; then
    echo "Artifact too small ($size bytes < $min_bytes): $file" >&2
    exit 1
  fi
}

verify_manifest_matches_core() {
  local root="$1"
  local core_name="$2"
  local manifest core_bin expected actual
  manifest="$(find "$root" -name manifest.json -type f | head -n 1)"
  core_bin="$(find "$root" -name "$core_name" -type f | head -n 1)"
  if [ -z "$manifest" ] || [ -z "$core_bin" ]; then
    echo "Missing manifest.json or $core_name in $root" >&2
    exit 1
  fi
  expected="$(sed -nE 's/.*"coreSha256"[[:space:]]*:[[:space:]]*"([0-9a-f]{64})".*/\1/p' "$manifest")"
  if [ -z "$expected" ]; then
    echo "Invalid manifest.json at $manifest" >&2
    exit 1
  fi
  actual="$(sha256sum "$core_bin" | awk '{print $1}')"
  if [ "$expected" != "$actual" ]; then
    echo "Core SHA256 mismatch: manifest=$expected actual=$actual" >&2
    exit 1
  fi
}

verify_android() {
  local abi expected_version apk apk_count entries bt_dir badging
  case "$arch" in
    arm64) abi="arm64-v8a" ;;
    arm) abi="armeabi-v7a" ;;
    amd64) abi="x86_64" ;;
    *)
      echo "Unsupported android arch: $arch" >&2
      exit 1
      ;;
  esac

  apk_count="$(find "$dist_dir" -maxdepth 1 -type f -name '*.apk' | wc -l | tr -d ' ')"
  if [ "$apk_count" -ne 1 ]; then
    echo "Expected 1 APK in $dist_dir, found $apk_count" >&2
    exit 1
  fi
  apk="$(find "$dist_dir" -maxdepth 1 -type f -name '*.apk' | head -n 1)"
  case "$(basename "$apk")" in
    *"$abi"*) ;;
    *)
      echo "APK filename does not contain ABI $abi: $apk" >&2
      exit 1
      ;;
  esac
  require_nonempty_min_bytes "$apk" 5242880

  unzip -t "$apk" >/dev/null
  entries="$(unzip -Z1 "$apk")"
  for required in "classes.dex" "lib/$abi/libclash.so" "lib/$abi/libcore.so" "lib/$abi/librust_api.so"; do
    if ! printf '%s\n' "$entries" | grep -qxF "$required"; then
      echo "APK missing $required: $apk" >&2
      exit 1
    fi
  done

  bt_dir="$(find "${ANDROID_HOME:?ANDROID_HOME is required}/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
  if [ -z "$bt_dir" ]; then
    echo "No Android build-tools found under $ANDROID_HOME/build-tools" >&2
    exit 1
  fi

  expected_version="$(printf '%s\n' "$tag_name" | sed -E 's/^v([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
  badging="$("$bt_dir/aapt2" dump badging "$apk")"
  if ! printf '%s\n' "$badging" | grep -q "versionName='$expected_version'"; then
    echo "APK versionName mismatch (expected $expected_version) in $apk" >&2
    exit 1
  fi

  if ! printf '%s\n' "$badging" | grep -q "package: name='com.nicelic.fclash'"; then
    echo "Release APK must use package com.nicelic.fclash" >&2
    exit 1
  fi
  "$bt_dir/apksigner" verify --verbose "$apk"

  (cd "$dist_dir" && sha256sum "$(basename "$apk")") > "$checksum_file"
}

verify_linux() {
  local deb_count rpm_count app_count deb rpm_pkg appimage tmpdir deb_contents helper_file helper_perm rpm_contents
  deb_count="$(find "$dist_dir" -maxdepth 1 -type f -name '*.deb' | wc -l | tr -d ' ')"
  rpm_count="$(find "$dist_dir" -maxdepth 1 -type f -name '*.rpm' | wc -l | tr -d ' ')"
  app_count="$(find "$dist_dir" -maxdepth 1 -type f -name '*.AppImage' | wc -l | tr -d ' ')"

  if [ "$deb_count" -ne 1 ] || [ "$rpm_count" -ne 1 ] || [ "$app_count" -ne 1 ]; then
    echo "Expected 1 .deb, 1 .rpm, 1 .AppImage in $dist_dir" >&2
    ls -la "$dist_dir" >&2
    exit 1
  fi

  deb="$(find "$dist_dir" -maxdepth 1 -type f -name '*.deb' | head -n 1)"
  rpm_pkg="$(find "$dist_dir" -maxdepth 1 -type f -name '*.rpm' | head -n 1)"
  appimage="$(find "$dist_dir" -maxdepth 1 -type f -name '*.AppImage' | head -n 1)"
  require_nonempty_min_bytes "$deb" 5242880
  require_nonempty_min_bytes "$rpm_pkg" 5242880
  require_nonempty_min_bytes "$appimage" 5242880

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  dpkg-deb --info "$deb" >/dev/null
  deb_contents="$(dpkg-deb --contents "$deb")"
  for needle in "FClash" "FClashCore" "FClashHelperService" "manifest.json" "librust_api.so"; do
    if ! printf '%s\n' "$deb_contents" | grep -q "$needle"; then
      echo ".deb missing $needle: $deb" >&2
      exit 1
    fi
  done

  dpkg-deb -x "$deb" "$tmpdir/deb"
  verify_manifest_matches_core "$tmpdir/deb" "FClashCore"
  helper_file="$(find "$tmpdir/deb" -name FClashHelperService -type f | head -n 1)"
  helper_perm="$(stat -c '%a' "$helper_file")"
  if printf '%s\n' "$helper_perm" | grep -qE '([2367][0-7]|[2367])$'; then
    echo "FClashHelperService in .deb must not be group/world writable (mode $helper_perm)" >&2
    exit 1
  fi

  rpm -qpi "$rpm_pkg" >/dev/null
  rpm_contents="$(rpm -qpl "$rpm_pkg")"
  for needle in "FClash" "FClashCore" "FClashHelperService" "manifest.json" "librust_api.so"; do
    if ! printf '%s\n' "$rpm_contents" | grep -q "$needle"; then
      echo ".rpm missing $needle: $rpm_pkg" >&2
      exit 1
    fi
  done

  cp "$appimage" "$tmpdir/test.AppImage"
  chmod +x "$tmpdir/test.AppImage"
  (cd "$tmpdir" && ./test.AppImage --appimage-extract >/dev/null)
  verify_manifest_matches_core "$tmpdir/squashfs-root" "FClashCore"
  if [ -z "$(find "$tmpdir/squashfs-root" -name 'librust_api.so' -type f)" ]; then
    echo ".AppImage missing librust_api.so: $appimage" >&2
    exit 1
  fi

  (
    cd "$dist_dir"
    sha256sum "$(basename "$deb")" "$(basename "$rpm_pkg")" "$(basename "$appimage")"
  ) > "$checksum_file"
}

verify_macos() {
  local expected_lipo dmg_count dmg mnt app main_bin core_bin rust_lib archs
  case "$arch" in
    arm64) expected_lipo="arm64" ;;
    amd64) expected_lipo="x86_64" ;;
    *)
      echo "Unsupported macos arch: $arch" >&2
      exit 1
      ;;
  esac

  dmg_count="$(find "$dist_dir" -maxdepth 1 -type f -name '*.dmg' | wc -l | tr -d ' ')"
  if [ "$dmg_count" -ne 1 ]; then
    echo "Expected 1 .dmg in $dist_dir, found $dmg_count" >&2
    exit 1
  fi
  dmg="$(find "$dist_dir" -maxdepth 1 -type f -name '*.dmg' | head -n 1)"
  require_nonempty_min_bytes "$dmg" 5242880

  hdiutil verify "$dmg"
  mnt="$(mktemp -d)"
  cleanup_mount() {
    hdiutil detach "$mnt" -quiet 2>/dev/null || true
    rm -rf "$mnt"
  }
  trap cleanup_mount RETURN

  hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mnt" >/dev/null
  app="$(find "$mnt" -maxdepth 2 -name '*.app' -type d | head -n 1)"
  if [ -z "$app" ]; then
    echo "No .app bundle found inside $dmg" >&2
    exit 1
  fi

  main_bin="$app/Contents/MacOS/FClash"
  core_bin="$(find "$app" -name 'FClashCore' -type f | head -n 1)"
  rust_lib="$(find "$app" -iname '*rust_api*' -type f | head -n 1)"
  if [ ! -x "$main_bin" ] || [ -z "$core_bin" ] || [ -z "$rust_lib" ]; then
    echo "macOS bundle missing required binaries (main=$main_bin core=$core_bin rust=$rust_lib)" >&2
    exit 1
  fi

  for bin in "$main_bin" "$core_bin"; do
    archs="$(lipo -archs "$bin")"
    if ! printf '%s\n' "$archs" | grep -qw "$expected_lipo"; then
      echo "Binary $bin arch mismatch: expected $expected_lipo, got '$archs'" >&2
      exit 1
    fi
  done

  (cd "$dist_dir" && shasum -a 256 "$(basename "$dmg")") > "$checksum_file"
}

case "$platform" in
  android) verify_android ;;
  linux) verify_linux ;;
  macos) verify_macos ;;
  *)
    echo "Unsupported platform for verify_release_artifacts.sh: $platform" >&2
    exit 1
    ;;
esac

echo "Verified $platform ($arch) artifacts:"
cat "$checksum_file"
