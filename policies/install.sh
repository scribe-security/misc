#!/bin/sh

is_command() {
  command -v "$1" >/dev/null
}

http_download_curl() {
  local_file=$1
  source_url=$2
  header=$3
  if [ -z "$header" ]; then
    code=$(curl -w '%{http_code}' -L -o "$local_file" "$source_url")
  else
    code=$(curl -w '%{http_code}' -L -H "$header" -o "$local_file" "$source_url")
  fi
  if [ "$code" != "200" ]; then
    log_debug "http_download_curl received HTTP status $code"
    return 1
  fi
  return 0
}

http_download_wget() {
  local_file=$1
  source_url=$2
  header=$3
  if [ -z "$header" ]; then
    wget -q -O "$local_file" "$source_url"
  else
    wget -q --header "$header" -O "$local_file" "$source_url"
  fi
}

http_download() {
  log_debug "http_download $2"
  if is_command curl; then
    http_download_curl "$@"
    return
  elif is_command wget; then
    http_download_wget "$@"
    return
  fi
  log_crit "http_download unable to find wget or curl"
  return 1
}

http_download_stdout() {
  source_url=$1
  log_debug "http_download_stdout $source_url"
  if is_command curl; then
    curl --silent ${source_url}
    return
  elif is_command wget; then
    wget -q -O /dev/stdout ${source_url}
    return
  fi
  log_crit "http_download_stdout unable to find wget or curl"
  return 1
}

echoerr() {
  echo "$@" 1>&2
}

log_prefix() {
  echo "scribe"
}

_logp=6

log_set_priority() {
  _logp="$1"
}

log_priority() {
  if test -z "$1"; then
    echo "$_logp"
    return
  fi
  [ "$1" -le "$_logp" ]
}

log_tag() {
  case $1 in
    0) echo "emerg" ;;
    1) echo "alert" ;;
    2) echo "crit" ;;
    3) echo "err" ;;
    4) echo "warning" ;;
    5) echo "notice" ;;
    6) echo "info" ;;
    7) echo "debug" ;;
    *) echo "$1" ;;
  esac
}

log_debug() {
  log_priority 7 || return 0
  echoerr "$(log_prefix)" "$(log_tag 7)" "$@"
}

log_info() {
  log_priority 6 || return 0
  echoerr "$(log_prefix)" "$(log_tag 6)" "$@"
}

log_err() {
  log_priority 3 || return 0
  echoerr "$(log_prefix)" "$(log_tag 3)" "$@"
}

log_crit() {
  log_priority 2 || return 0
  echoerr "$(log_prefix)" "$(log_tag 2)" "$@"
}

asset_file_exists() (
  path="$1"
  if [ ! -f "${path}" ]; then
      return 1
  fi
)

uname_arch() {
  arch=$(uname -m)
  case $arch in
    x86_64) arch="amd64" ;;
    x86) arch="386" ;;
    i686) arch="386" ;;
    i386) arch="386" ;;
    aarch64) arch="arm64" ;;
    armv5*) arch="armv5" ;;
    armv6*) arch="armv6" ;;
    armv7*) arch="armv7" ;;
  esac

  uname_arch_check "${arch}"

  echo ${arch}
}

uname_arch_check() {
  arch=$1
  case "$arch" in
    386) return 0 ;;
    amd64) return 0 ;;
    arm64) return 0 ;;
    armv5) return 0 ;;
    armv6) return 0 ;;
    armv7) return 0 ;;
    ppc64) return 0 ;;
    ppc64le) return 0 ;;
    mips) return 0 ;;
    mipsle) return 0 ;;
    mips64) return 0 ;;
    mips64le) return 0 ;;
    s390x) return 0 ;;
    amd64p32) return 0 ;;
  esac
  log_crit "uname_arch_check '$(uname -m)' got converted to '$arch' which is not a GOARCH value.  Please file bug report at https://github.com/client9/shlib"
  return 1
}

uname_os() {
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  case "$os" in
    msys*) os="windows" ;;
    mingw*) os="windows" ;;
    cygwin*) os="windows" ;;
  esac

  uname_os_check "$os"
  echo "$os"
}

uname_os_check() {
  os=$1
  case "$os" in
    darwin) return 0 ;;
    dragonfly) return 0 ;;
    freebsd) return 0 ;;
    linux) return 0 ;;
    android) return 0 ;;
    nacl) return 0 ;;
    netbsd) return 0 ;;
    openbsd) return 0 ;;
    plan9) return 0 ;;
    solaris) return 0 ;;
    windows) return 0 ;;
  esac
  log_crit "uname_os_check '$(uname -s)' got converted to '$os' which is not a GOOS value. Please file bug at https://github.com/client9/shlib"
  return 1
}

get_latest_artifact() {
  download_url="$1"
  download_repo="$2"
  supbath="$3"

  log_debug "get_artifact(url=${download_url}, repo=${download_repo}, subpath=${subpath})"

  url=${download_url}/api/storage/${download_repo}/${subpath}
  log_debug "get_latest_artifact(url=${url}?lastModified)"
  latestArtifact=$(http_download_stdout ${url}?lastModified | grep uri | awk '{ print $3 }' | sed s/\"//g | sed s/,//g)
  
  if [ -z "${latestArtifact}" ]; then
    log_err "could not find latest artifact, url='${url}'"
    return 1
  fi
  
  latestDownloadUrl=$(http_download_stdout $latestArtifact | grep downloadUri | awk '{ print $3 }' | sed s/\"//g | sed s/,//g)
  log_debug "get_latest_artifact(latestArtifact=${latestArtifact}, latestDownloadUrl=${latestDownloadUrl})"

  echo "$latestDownloadUrl"
}

get_artifact() {
  download_url="$1"
  download_repo="$2"
  supbath="$3"
  asset_filename="$4"

  log_debug "get_artifact(url=${download_url}, repo=${download_repo}, subpath=${subpath}, asset_filename=${asset_filename})"

  url=${download_url}/${download_repo}/${subpath}
  downloadUrl=${url}/${asset_filename}

  log_debug "get_artifact(asset_filename=${asset_filename}, downloadUrl=${downloadUrl})"    
  echo "$downloadUrl"
}

asset_file_exists() (
  path="$1"
  if [ ! -f "${path}" ]; then
      return 1
  fi
)

download_asset() (
  download_url="$1"
  download_repo="$2"
  download_dir="$3"
  subpath="$4"
  asset_filename="$5"
  version="$6"

  log_debug "download_asset(url=${download_url}, repo=${download_repo}, subpath=${subpath}, download_dir=${download_dir}, version=${version:-latest})"

  if [ -z "$version" ]; then
    asset_url=$(get_latest_artifact "${download_url}" "${download_repo}" "${subpath}")
  else
    asset_url=$(get_artifact "${download_url}" "${download_repo}" "${subpath}" "${asset_filename}" )
  fi

  if [ -z "${asset_url}" ]; then
    log_err "could not find asset url, asset_url='${asset_url}'"
    return 1
  fi

  asset_filename=$(basename $asset_url)
  actualVersion=$(echo ${asset_filename} | cut -d '_' -f 2)
  log_info "Downloading, Version=${actualVersion}"

  asset_filepath="${download_dir}/${asset_filename}"
  http_download "${asset_filepath}" "${asset_url}"
  asset_file_exists "${asset_filepath}"

  log_debug "download_asset(path=${asset_filepath})"
  echo "${asset_filepath}"
)


usage() {
  this="install.sh"
  cat<<EOF
$this: Download ${project_name} ${tool}
Usage: $this [-b] download-dir [-d] [-v version]
  -d install directory Default - "${install_dir}"
  -v version
  -h usage

  Empty tag will choose latest
EOF
  exit 2
}

parse_args() {
  while getopts ":v:b:dh?x" arg; do
    case "$arg" in
      b) install_dir="$OPTARG" ;;
      h | \?) usage;;
      d) log_set_priority 10 ;;
      t) tag="${OPTARG}";;
      v) version="${OPTARG}";;
      x) set -x ;;
    esac
  done
  shift $((OPTIND - 1))
}

get_tag() {
  owner="$1"
  repo="$2"
  tag="$3"

  if [ -z "${tag}" ]; then
    log_debug "checking github for the current release tag"
    tag=""
  else
    log_debug "checking github for release tag='${tag}'"
  fi
  set -u

  tag=$(get_release_tag "${owner}" "${repo}" "${tag}")
  log_info "Using tag: ${tag}"
  if [ "$?" != "0" ]; then
    log_err "unable to find tag='${tag}'"
    log_err "do not specify a version or select a valid version from https://github.com/${OWNER}/${REPO}/releases"
    return 1
  fi

  echo "${tag}"
}


bundle_asset() {
  version="$1"
  asset_filename="bundle_${version}.tar.gz"
  log_debug "asset, Path: ${asset_filename}"
  echo "${asset_filename}"
}


pre_install_tool() {
  install_dir="."
  tool="bundle"
  project_name="Github-Posture"
  repo="${project_name}"
  owner="scribe-security"
  download_repo="scribe-generic-public-local"
  assert_base_url="https://scribesecuriy.jfrog.io/artifactory"
  install_dir="."
  subpath="github-posture/bundle"
}

install_tool() {
  asset_filename=$(bundle_asset "${version}")
  mkdir -p $install_dir
  download_url="${assert_base_url}"
  asset_url="${download_url}/${asset_filename}"
  asset_filepath=$(download_asset "${download_url}" "${download_repo}" "${install_dir}" "${subpath}" "${asset_filename}" "${version}")
}

os=$(uname_os)
arch=$(uname_arch)

pre_install_tool
parse_args "$@"
install_tool
log_info "Success - $project_name, Downloaded, Path=${asset_filepath}"
