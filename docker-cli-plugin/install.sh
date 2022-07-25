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

echoerr() {
  echo -n "$@\n" 1>&2
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

usage() {
  this="install.sh"
  cat<<EOF
$this: download go binaries for scribe security
Usage: $this [-p] plugindir [-d] [-t tool]
  -p plugin directory , Default - "${plugin_dir}"
  -t plugin list 'tool:version', Default - "${supported_tools}"
  -h usage

  Tool not found will be downloaded
EOF
  exit 2
}

parse_args() {
  while getopts "t:b:p:dh?xD" arg; do
    case "$arg" in
      p) plugin_dir="$OPTARG" ;;
      h | \?) usage;;
      d) log_set_priority 10 ;;
      t) tools="${tools} ${OPTARG}";;
      x) set -x ;;
    esac
  done
  if [ -z "$tools" ]; then
    tools="${supported_tools}"
  fi

  shift $((OPTIND - 1))
}

plugin_dir="${HOME}/.docker/cli-plugins"
scribe_default="${HOME}/.scribe/bin/"
supported_tools="gensbom"
gensbom_plugins="docker-bom docker-verify"
branch="feature/docker_cli_plugin"
base_url="https://raw.githubusercontent.com/scribe-security/misc/${branch}"
tools=""
parse_args "$@"
export PATH="${scribe_default}:$PATH"

install_plugin() {
    tool=$1
    plugin_dir=$2
    plugins=$3

    for plugin in ${plugins}; do
        log_info "Selected, tool=${tool}, plugin=${plugin}"
        if ! is_command $tool; then
                log_info "Tool not found, Downloading, Tool: $tool"
                curl -sSfL "${base_url}/install.sh" | sh -s -- -t $tool $@
            return
        fi

        asset_url="${base_url}/docker-cli-plugin/${plugin}"
        asset_filepath="${plugin_dir}/${plugin}"

        http_download "${asset_filepath}" "${asset_url}"
        chmod +x ${plugin_dir}/${plugin}
        log_info "Installed ${plugin_dir}/${plugin}"
    done
}

log_info "Installer - Scribe docker cli plugins"
for tool in ${tools}; do
    case "$tool" in
      gensbom)  
        install_plugin gensbom "${plugin_dir}" "${gensbom_plugins}"
      ;;
    esac
done
