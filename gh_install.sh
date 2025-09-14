#!/bin/sh
set -ex

# -------------------------------------------------------------------
# Defaults (override with -R / -b or env vars)
# -------------------------------------------------------------------
REPO="${VALINT_DOWNLOAD_REPO:-scribe-security/valint-release}"   # owner/repo
API_BASE="${VALINT_DOWNLOAD_URL:-https://api.github.com}"         # GitHub API base
INSTALL_DIR="${SCRIBE_INSTALL_DIR:-$HOME/.scribe/bin}"
TOOL_DEFAULT="valint"
HTTP_VERSION_FLAG=${HTTP_VERSION_FLAG:---http2}

# ENV=dev|feature  → prefer prereleases for "latest"
# GITHUB_TOKEN     → use for auth/rate-limit

# -------------------------------------------------------------------
# Tiny logger
# -------------------------------------------------------------------
log()   { printf '%s %s %s\n' scribe "$1" "$2" >&2; }
info()  { log info "$*"; }
debug() { [ -n "$DEBUG" ] && log debug "$*"; :; }
err()   { log err "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

need() {
  command -v "$1" >/dev/null 2>&1 || { err "missing dependency: $1"; exit 1; }
}

require_http() {
  if have curl || have wget; then return 0; fi
  err "missing dependency: curl or wget"
  exit 1
}

ensure_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  os="$(goos)"; arch="$(goarch)"
  mkdir -p "$HOME/.scribe/bin"
  case "$os/$arch" in
    linux/amd64)
      url="https://github.com/jqlang/jq/releases/download/jq-1.6/jq-linux64"
      dst="$HOME/.scribe/bin/jq"
      ;;
    darwin/amd64)
      url="https://github.com/jqlang/jq/releases/download/jq-1.6/jq-osx-amd64"
      dst="$HOME/.scribe/bin/jq"
      ;;
    windows/amd64)
      url="https://github.com/jqlang/jq/releases/download/jq-1.6/jq-win64.exe"
      dst="$HOME/.scribe/bin/jq.exe"
      ;;
    *)
      err "jq not found and auto-bootstrap not defined for $os/$arch"
      return 1
      ;;
  esac
  if have curl; then
    curl -fsSL "$url" -o "$dst"
  else
    wget -q -O "$dst" "$url"
  fi
  chmod +x "$dst" 2>/dev/null || true
  export PATH="$HOME/.scribe/bin:$PATH"
}

# -------------------------------------------------------------------
# OS/ARCH helpers
# -------------------------------------------------------------------
goos()  { uname -s | tr '[:upper:]' '[:lower:]' | sed -E 's/(msys|mingw|cygwin).*/windows/'; }
goarch(){
  a=$(uname -m)
  case "$a" in
    x86_64) echo amd64 ;;
    i386|i686|x86) echo 386 ;;
    aarch64) echo arm64 ;;
    armv7*) echo armv7 ;;
    armv6*) echo armv6 ;;
    *) echo "$a" ;;
  esac
}

arch_regex(){
  case "$1" in
    amd64)  echo '(amd64|x86_64)';;
    386)    echo '(386|i386|i686|x86)';;
    arm64)  echo '(arm64|aarch64)';;
    armv7)  echo '(armv7|armhf)';;
    armv6)  echo 'armv6';;
    *)      printf '%s' "$1";;
  esac
}

# Preferred formats we can actually unpack/install ourselves
format_candidates_for_os(){
  case "$1" in
    windows) echo "zip";;
    darwin)  echo "tar.gz zip";;
    linux)   echo "tar.gz deb rpm apk zip";;
    *)       echo "tar.gz zip";;
  esac
}

# Binary name / archive fmt tweaks
bin_name_for(){
  os="$1"; bin="$2"
  [ "$os" = "windows" ] && echo "${bin}.exe" || echo "${bin}"
}

# -------------------------------------------------------------------
# GitHub API wrappers (curl + jq)
# -------------------------------------------------------------------
gh_curl() {
  url="$1"

  if have curl; then
    set -- -sS -L --compressed
    [ -n "$HTTP_VERSION_FLAG" ] && set -- "$@" "$HTTP_VERSION_FLAG"
    set -- "$@" -H "User-Agent: scribe-installer"
    set -- "$@" -H "Accept: application/vnd.github+json"
    [ -n "$GITHUB_TOKEN" ] && set -- "$@" -H "Authorization: Bearer ${GITHUB_TOKEN}"
    set -- "$@" "$url"
    curl "$@"
  else
    # wget path (HTTP/2 flag ignored; wget is HTTP/1.1)
    set -- --quiet --tries=3
    # --compression=auto (if supported) helps with gzip; harmless if unknown
    if wget --help 2>/dev/null | grep -q -- '--compression'; then
      set -- "$@" --compression=auto
    fi
    set -- "$@" --header="User-Agent: scribe-installer"
    set -- "$@" --header="Accept: application/vnd.github+json"
    [ -n "$GITHUB_TOKEN" ] && set -- "$@" --header="Authorization: Bearer ${GITHUB_TOKEN}"
    set -- "$@" -O - "$url"
    wget "$@"
  fi
}

gh_release_latest_json() {
  # Explicit opt-in to prereleases via -D or ENV=dev
  prefer_pre=0
  if [ "$ALLOW_PRERELEASE" = "1" ]; then
    prefer_pre=1
  elif printf %s "${ENV}" | tr '[:upper:]' '[:lower:]' | grep -Eq '^(dev|development|feature)$'; then
    prefer_pre=1
  fi

  # Try official /latest endpoint (only returns stable releases)
  if [ "$prefer_pre" -eq 0 ]; then
    body="$(gh_curl "${API_BASE}/repos/${REPO}/releases/latest")"
    if printf '%s' "$body" | jq -e '.assets? and (.draft==false) and (.prerelease==false)' >/dev/null 2>&1; then
      printf '%s' "$body"
      return 0
    fi
  fi

  # Fallback to /releases for manual filtering (e.g., prerelease if requested)
  list="$(gh_curl "${API_BASE}/repos/${REPO}/releases?per_page=30")"

  if [ "$prefer_pre" -eq 1 ]; then
    picked="$(printf '%s' "$list" | jq -e '
      (map(select(.draft==false and .prerelease==true)) | sort_by(.published_at) | reverse | .[0])
      // (map(select(.draft==false)) | sort_by(.published_at) | reverse | .[0])
    ' 2>/dev/null)" || picked=""
  else
    picked="$(printf '%s' "$list" | jq -e '
      (map(select(.draft==false and .prerelease==false)) | sort_by(.published_at) | reverse | .[0])
    ' 2>/dev/null)" || picked=""
  fi

  if [ -n "$picked" ] && [ "$picked" != "null" ]; then
    printf '%s' "$picked"
    return 0
  fi

  err "No suitable release found (stable=${prefer_pre:-0})"
  return 1
}

gh_release_tag_json() {
  # Args: tag (try with and without 'v' prefix)
  tag="$1"
  body="$(gh_curl "${API_BASE}/repos/${REPO}/releases/tags/v${tag}")"
  if printf '%s' "$body" | jq -e '.tag_name? // empty' >/dev/null; then
    printf '%s' "$body"; return 0
  fi
  body="$(gh_curl "${API_BASE}/repos/${REPO}/releases/tags/${tag}")"
  printf '%s' "$body"
}

# -------------------------------------------------------------------
# Asset selection
# -------------------------------------------------------------------
# Matches:
#   name[_v?VERSION]?_{os}-{arch}.fmt
#   name[_v?VERSION]?_{os}_{arch}.fmt
pick_asset_url_from_release() {
  # Args: release_json name os arch format
  rel_json="$1"; name="$2"; os="$3"; arch="$4"; fmt="$5"
  arch_rx="$(arch_regex "$arch")"
  sep='[-_]'
  # jq: select first asset whose .name matches regex
  printf '%s' "$rel_json" | jq -r --arg name "$name" --arg os "$os" --arg sep "$sep" --arg arch_rx "$arch_rx" --arg fmt "$fmt" '
    .assets[]
    | {n: .name, u: .browser_download_url}
    | select(.n
      | test("^" + $name + "(_v?[^_]+)?" + "_" + $os + $sep + $arch_rx + "\\." + $fmt + "$"))
    | .u
  ' | head -n 1
}

find_latest_asset_url() {
  # Args: name os arch
  name="$1"; os="$2"; arch="$3"

  rel="$(gh_release_latest_json)" || { err "failed to read latest release"; return 1; }
  [ -z "$rel" ] && { err "empty latest release response"; return 1; }

  for fmt in $(format_candidates_for_os "$os"); do
    url="$(pick_asset_url_from_release "$rel" "$name" "$os" "$arch" "$fmt" || true)"
    if [ -n "$url" ] && [ "$url" != "null" ]; then
      debug "matched latest asset fmt=$fmt → $url"
      printf '%s\n' "$url"
      return 0
    fi
  done

  err "no matching asset for ${name} ${os}/${arch} in latest release"
  # help: print available names
  printf '%s' "$rel" | jq -r '.assets[].name' >&2
  return 1
}

find_tag_asset_url() {
  # Args: name os arch version [format_hint]
  name="$1"; os="$2"; arch="$3"; ver="$4"; fmt_hint="$5"

  rel="$(gh_release_tag_json "$ver")" || { err "failed to read tag $ver"; return 1; }
  if ! printf '%s' "$rel" | jq -e '.tag_name? // empty' >/dev/null; then
    err "tag not found: $ver"
    return 1
  fi

  tried=""
  for fmt in ${fmt_hint:-} $(format_candidates_for_os "$os"); do
    case " $tried " in *" $fmt "*) continue;; esac
    tried="$tried $fmt"
    url="$(pick_asset_url_from_release "$rel" "$name" "$os" "$arch" "$fmt" || true)"
    if [ -n "$url" ] && [ "$url" != "null" ]; then
      debug "matched tag asset fmt=$fmt → $url"
      printf '%s\n' "$url"
      return 0
    fi
  done

  err "no matching asset for ${name} ${os}/${arch} in tag ${ver}"
  printf '%s' "$rel" | jq -r '.assets[].name' >&2
  return 1
}

# -------------------------------------------------------------------
# Download + install
# -------------------------------------------------------------------
http_download_file() {
  url="$1"
  dest="$2"

  if have curl; then
    set -- -sS -L --compressed -o "$dest"
    [ -n "$HTTP_VERSION_FLAG" ] && set -- "$@" "$HTTP_VERSION_FLAG"
    set -- "$@" -H "User-Agent: scribe-installer"
    set -- "$@" -H "Accept: application/octet-stream"
    [ -n "$GITHUB_TOKEN" ] && set -- "$@" -H "Authorization: Bearer ${GITHUB_TOKEN}"
    set -- "$@" "$url"
    curl "$@"
  else
    # wget path (HTTP/2 flag not applicable)
    set -- --quiet
    # gzip/deflate if supported
    if wget --help 2>/dev/null | grep -q -- '--compression'; then
      set -- "$@" --compression=auto
    fi
    set -- "$@" --header="User-Agent: scribe-installer"
    set -- "$@" --header="Accept: application/octet-stream"
    [ -n "$GITHUB_TOKEN" ] && set -- "$@" --header="Authorization: Bearer ${GITHUB_TOKEN}"
    set -- "$@" -O "$dest" "$url"
    wget "$@"
  fi
}


unpack() {
  archive="$1"
  case "$archive" in
    *.tar.gz|*.tgz) tar --no-same-owner -xzf "$archive" ;;
    *.tar)          tar --no-same-owner -xf  "$archive" ;;
    *.zip)          unzip -q "$archive" ;;
    *.deb|*.rpm|*.apk)
      err "package format '$archive' not auto-installed by this script (use tar.gz/zip asset)"; return 1 ;;
    *) err "unknown archive: $archive"; return 1 ;;
  esac
}

install_asset_file() {
  asset="$1"; dest_dir="$2"; binary="$3"
  workdir="$(dirname "$asset")"
  (cd "$workdir" && unpack "$asset")
  mkdir -p "$dest_dir"
  install "$workdir/$binary" "$dest_dir/"
}

download_install() {
  name="$1"; os="$2"; arch="$3"; version="$4"; binary="$5"
  tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT

  if [ -z "$version" ]; then
    url="$(find_latest_asset_url "$name" "$os" "$arch")"
  else
    url="$(find_tag_asset_url "$name" "$os" "$arch" "$version" "tar.gz")"
  fi

  [ -z "$url" ] && { err "asset url not found"; return 1; }
  file="$tmpdir/$(basename "$url")"
  info "Downloading: $(basename "$url")"
  http_download_file "$url" "$file"
  install_asset_file "$file" "$INSTALL_DIR" "$binary"
}

# -------------------------------------------------------------------
# CLI
#   -b DIR       install dir (default: $INSTALL_DIR)
#   -t TOOL[:VER]  (default tool: $TOOL_DEFAULT)
#   -R owner/repo (default: $REPO)
#   -L api base   (default: $API_BASE)
#   -d debug
# -------------------------------------------------------------------
TOOLS=""
usage() {
  cat <<EOF
Usage: $0 [-b DIR] [-t tool[:version]] [-R owner/repo] [-L api-base] [-d] [-D]
  -b   install directory (default: ${INSTALL_DIR})
  -t   tool list; may be repeated or comma-separated (default: ${TOOL_DEFAULT})
  -R   owner/repo (default: ${REPO})
  -L   API base (default: ${API_BASE})
  -d   debug logging
  -D   allow prerelease versions (e.g., dev builds)
Env:
  GITHUB_TOKEN      GitHub token for private repos / higher rate limits
  ENV=dev|feature   (also enables prerelease download)
EOF
  exit 2
}

while getopts "b:t:R:L:dhD?" opt; do
  case "$opt" in
    b) INSTALL_DIR="$OPTARG" ;;
    t) TOOLS="${TOOLS} ${OPTARG}" ;;
    R) REPO="$OPTARG" ;;
    L) API_BASE="$OPTARG" ;;
    d) DEBUG=1 ;;
    D) ALLOW_PRERELEASE=1 ;;   # ← THIS LINE enables prerelease support
    h|\?) usage ;;
  esac
done

shift $((OPTIND-1))

[ -n "$TOOLS" ] || TOOLS="$TOOL_DEFAULT"
TOOLS="$(printf '%s' "$TOOLS" | tr ',' ' ')"

require_http

ensure_jq || true
need jq

OS="$(goos)"
ARCH="$(goarch)"
BIN_DIR="$INSTALL_DIR"
mkdir -p "$BIN_DIR"
if [ "$OS" = "windows" ]; then
  debug "Detected Windows OS, no http version flag set"
  HTTP_VERSION_FLAG=""
fi

info "Installer (GitHub Releases) • repo=${REPO} • os=${OS} arch=${ARCH}"
for spec in $TOOLS; do
  tool="${spec%%:*}"
  ver="${spec#*:}"; [ "$ver" = "$tool" ] && ver=""
  bin="$(bin_name_for "$OS" "$tool")"

  debug "Selected: tool=${tool} version=${ver:-latest}"
  download_install "$tool" "$OS" "$ARCH" "$ver" "$bin" || { err "failed to install ${tool}"; exit 1; }
  info "Installed ${BIN_DIR}/${bin}"
done
