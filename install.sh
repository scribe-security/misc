#!/bin/sh
download_repo="scribe-generic-public-local"
download_url="https://scribesecuriy.jfrog.io/artifactory"
install_dir="${HOME}/.scribe/bin"


get_latest_artifact() {
  download_url="$1"
  download_repo="$2"
  name="$3"
  os="$4"
  arch="$5"

  log_debug "get_artifact(url=${download_url}, repo=${download_repo}, name=${name}, os=${os}, arch=${arch}, version=${version:-latest}, format=${format})"

  if [ -z "${ENV}" ]; then
    subpath=${name}/${os}/${arch}
  else
    subpath=${ENV}/${name}/${os}/${arch}
    log_info "Using dev artifacts, subpath='${subpath}'"
  fi


  url=${download_url}/api/storage/${download_repo}/${subpath}
  log_debug "get_latest_artifact(url=${url})"
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
  name="$3"
  os="$4"
  arch="$5"
  version="$6"
  format="$7"
  
  log_debug "get_artifact(url=${download_url}, repo=${download_repo}, name=${name}, os=${os}, arch=${arch}, version=${version:-latest}, format=${format})"

  if [ -z "${ENV}" ]; then
    subpath=${name}/${os}/${arch}/${version}
  else
    subpath=${ENV}/${name}/${os}/${arch}/${version}
    log_info "Using dev artifacts, subpath='${subpath}'"
  fi

  url=${download_url}/${download_repo}/${subpath}
  asset_filename=${name}_${version}_${os}-${arch}.${format}
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
  name="$4"
  os="$5"
  arch="$6"
  version="$7"
  format="$8"

  log_debug "download_asset(url=${download_url}, repo=${download_repo}, download_dir=${download_dir}, name=${name}, os=${os}, arch=${arch}, version=${version:-latest}, format=${format})"

  if [ -z "$version" ]; then
    asset_url=$(get_latest_artifact "${download_url}" "${download_repo}" "${name}" "${os}" "${arch}")
  else
    asset_url=$(get_artifact "${download_url}" "${download_repo}" "${name}" "${os}" "${arch}" "${version}" "${format}")
  fi

  if [ -z "${asset_url}" ]; then
    log_err "could not find asset url, name='${name}' os='${os}' arch='${arch}'"
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

download_install_asset() (
  download_url="$1"
  download_repo="$2"
  download_dir="$3"
  install_dir="$4"
  name="$5"
  os="$6"
  arch="$7"
  version="$8"
  format="$9"
  binary="${10}"

  log_debug "download_install_asset(url=${download_url}, repo=${download_repo}, download_dir=${download_dir}, install_dir="${install_dir}", name=${name}, os=${os}, arch=${arch}, version=${version}, format=${format})"

  asset_filepath=$(download_asset "${download_url}" "${download_repo}" "${download_dir}"  "${name}" "${os}" "${arch}" "${version}" "${format}")
  if [ -z "${asset_filepath}" ]; then
      log_err "could not find release asset for os='${os}' arch='${arch}' format='${format}' "
      return 1
  fi
  install_asset "${asset_filepath}" "${install_dir}" "${binary}"

)

# install_asset [asset-path] [destination-path] [binary]
#
install_asset() (
  asset_filepath="$1"
  download_dir="$2"
  binary="$3"

  log_debug "install_asset(asset=${asset_filepath}, download_dir=${download_dir}, binary=${binary})"

  # don't continue if we don't have anything to install
  if [ -z "${asset_filepath}" ]; then
      return
  fi

  archive_dir=$(dirname "${asset_filepath}")

  # unarchive the downloaded archive to the temp dir
  (cd "${archive_dir}" && unpack "${asset_filepath}")

  # create the destination dir
  test ! -d "${download_dir}" && install -d "${download_dir}"

  # install the binary to the destination dir
  install "${archive_dir}/${binary}" "${download_dir}/"
)

is_command() {
  command -v "$1" >/dev/null
}

echoerr() {
  echo "$@" 1>&2
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

get_binary_name() (
  os="$1"
  arch="$2"
  binary="$3"
  original_binary="${binary}"

  case "${os}" in
    windows) binary="${binary}.exe" ;;
  esac

  log_debug "get_binary_name(os=${os}, arch=${arch}, binary=${original_binary}) returned '${binary}'"

  echo "${binary}"
)


get_format_name() (
  os="$1"
  arch="$2"
  format="$3"
  original_format="${format}"

  case ${os} in
    windows) format=zip ;;
  esac

  log_debug "get_format_name(os=${os}, arch=${arch}, format=${original_format}) returned '${format}'"

  echo "${format}"
)

unpack() (
  archive=$1

  log_debug "unpack(archive=${archive})"
  case "${archive}" in
    *.tar.gz | *.tgz) tar --no-same-owner -xzf "${archive}" ;;
    *.tar) tar --no-same-owner -xf "${archive}" ;;
    *.zip) unzip -q "${archive}" ;;
    *.dmg) extract_from_dmg "${archive}" ;;
    *)
      log_err "unpack unknown archive format for ${archive}"
      return 1
      ;;
  esac
)

usage() {
  this="install.sh"
  cat<<EOF
$this: download go binaries for scribe security
Usage: $this [-b] bindir [-d] [-t tool]
  -b install directory , Default - "${install_dir}"
  -d debug log
  -t tool list 'tool:version', Default - "${supported_tools}"
  -h usage

  Empty version will select the latest version.
EOF
  exit 2
}

parse_args() {
  while getopts "t:b:dh?xD" arg; do
    case "$arg" in
      b) install_dir="$OPTARG" ;;
      d) log_set_priority 10 ;;
      h | \?) usage;;
      t) tools="${tools} ${OPTARG}";;
      D) ENV="dev";;
      x) set -x ;;
    esac
  done
  if [ -z "$tools" ]; then
    if [ ! -z "$SCRIBE_TOOLS" ]; then
      tools="${SCRIBE_TOOLS}"
    else
        tools="${supported_tools}"
    fi
  fi

  if [ ! -z "$SCRIBE_DEBUG" ]; then
    log_set_priority 10
  fi

  if [ ! -z "$SCRIBE_INSTALL_DIR" ]; then
    install_dir="${SCRIBE_INSTALL_DIR}"
  fi

  shift $((OPTIND - 1))
}

# Install script starts here
os=$(uname_os)
arch=$(uname_arch)
format=$(get_format_name "${os}" "${arch}" "tar.gz")
download_dir=$(mktemp -d)
supported_tools="valint gensbom"
tools=""
trap 'rm -rf -- "$download_dir"' EXIT

binid="${os}/${arch}"
parse_args "$@"
case "${binid}" in
     darwin/arm64)
                ;;
     darwin/amd64)
                ;;
     linux/amd64)
                ;;
     linux/arm64)
                ;;
     windows/amd64)
                ;;
     *)
                log_err "unsupported OS/ARCH combination: $binid , please contact scribe support"
                exit 1
                ;;
esac


log_info "Installer - Scribe CLI tools"
log_debug "Selected, Tools=${tools}"
[ -d $install_dir ] || mkdir -p $install_dir
for val in ${tools}; do
  tool=$(echo "${val}" | awk -F: '{print $1}')
  binary=$(get_binary_name "${os}" "${arch}" "${tool}")

  version=$(echo "${val}" | awk -F: '{print $2}')
  log_info "Selected, tool=${tool}, version=${version:-latest}"
  if echo "${supported_tools}" | grep -q "${tool}";
  then
    log_info "Trying to download, tool=${tool}, version=${version:-latest}"
    download_install_asset "${download_url}" "${download_repo}" "${download_dir}" "${install_dir}" "${tool}" "${os}" "${arch}" "${version}" "${format}" "${binary}"
    if [ "$?" != "0" ]; then
        log_err "failed to install ${tool}"
        exit 1
    fi
    log_info "Installed ${install_dir}/${binary}"
  else
      log_err "Tool not support, Supported=${supported_tools}"
  fi

    echo ""  
done
