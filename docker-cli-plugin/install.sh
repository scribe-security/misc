#!/bin/sh

is_command() {
  command -v "$1" >/dev/null
}


echoerr() {
  echo -e "$@" 1>&2
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

# Set SET_ALIAS default
SET_ALIAS=${SET_ALIAS:-false}
SET_EXE_LINK=${SET_EXE_LINK:-false}

parse_args() {
  while getopts "t:b:p:dh?xDxAxL" arg; do
    case "$arg" in
      p) plugin_dir="$OPTARG" ;;
      h | \?) usage;;
      d) log_set_priority 10 ;;
      t) tools="${tools} ${OPTARG}";;
      b) branch="$OPTARG";base_url="https://raw.githubusercontent.com/scribe-security/misc/${branch}" ;;
      x) set -x ;;
      A) SET_ALIAS=true;;
      L) SET_EXE_LINK=true;;
    esac
  done
  if [ -z "$tools" ]; then
    tools="${supported_tools}"
  fi

  shift $((OPTIND - 1))
}

plugin_dir="${HOME}/.docker/cli-plugins"
scribe_default="${HOME}/.scribe/bin/"
supported_tools="docker-policy docker-policy-hook"

builtin_policies="scribe-default.yaml"
branch="master"
base_url="https://raw.githubusercontent.com/scribe-security/misc/${branch}"
tools="docker-policy docker-policy-hook"

parse_args "$@"
export PATH="${scribe_default}:$PATH"

install_plugin() {
    tool=$1
    plugin_dir=$2
    plugins=$3
    log_info "Installing Plugin '$base_url'"

    for plugin in ${plugins}; do
        log_info "Selected, tool=${tool}, plugin=${plugin}"
        if ! is_command $tool; then
                log_info "Tool not found, Downloading, Tool: $tool"
                curl -sSfL "${base_url}/install.sh" | sh -s -- -t $tool -D
        fi
        log_info "Downloading plugin, ${plugin}"
        asset_url="${base_url}/docker-cli-plugin/${plugin}"
        asset_filepath="${plugin_dir}/${plugin}"

        http_download "${asset_filepath}" "${asset_url}"
        chmod +x ${plugin_dir}/${plugin}
        log_info "Installed ${plugin_dir}/${plugin}"
    done
}

install_file() {
    local_file=$1
    plugin_dir=$2
    log_info "Installing File '$base_url'"

    log_info "Selected, file=${local_file}"
    asset_url="${base_url}/docker-cli-plugin/${local_file}"
    asset_filepath="${plugin_dir}/${local_file}"

    http_download "${asset_filepath}" "${asset_url}"
    log_info "Installed ${plugin_dir}/${local_file}"
}

install_policies() {
    local plugin_dir="$1"
    local policies="$2"
    
    for policy in $policies; do
        install_file "${policy}" "${plugin_dir}"
    done
}

setup_docker_alias() {
    local plugin_path="$1"
    local hook_path="${plugin_path}/docker-policy-hook"
    
    if [ ! -f "$hook_path" ]; then
        log_info "Error: docker-policy-hook not found at $hook_path"
        return 1
    fi
    
    # Add to shell rc file if it exists
    for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
        if [ -f "$rc" ]; then
            # Remove any existing docker alias
            sed -i '/alias docker=/d' "$rc"
            # Add new alias with full path
            echo "alias docker=\"${hook_path}\"" >> "$rc"
            log_info "Added alias to $rc"
        fi
    done
    
    # Set alias for current session
    alias docker="${hook_path}"
    log_info "Alias set for current session. Please source your shell's rc file or start a new session."
    type docker
    alias
}

# Default location /usr/local/bin
setup_docker_link() {
    local plugin_path="$1"
    local hook_path="${plugin_path}/docker-policy-hook"
    local link_path="/usr/local/bin/docker"
    
    if [ ! -f "$hook_path" ]; then
        log_info "Error: docker-policy-hook not found at $hook_path"
        return 1
    fi
    
    # Remove existing link
    if [ -L "$link_path" ]; then
        rm "$link_path"
        log_info "Removed existing link at $link_path"
    fi
    
    # Create new link
    ln -s "$hook_path" "$link_path"
    log_info "Created link at $link_path"

}

log_info "Installer - Scribe docker cli plugins"
[ -d $plugin_dir ] || mkdir -p $plugin_dir
for tool in $tools; do
    case "$tool" in
      "docker-policy")
        install_plugin "${tool}" "${plugin_dir}" "${tool}"
        install_policies "${plugin_dir}" "${builtin_policies}"
      ;;
      "docker-policy-hook")
        install_plugin "${tool}" "${plugin_dir}" "${tool}"
        if [ "$SET_ALIAS" = true ]; then
            log_info "Setting docker alias"
            setup_docker_alias "${plugin_dir}"
        fi
      ;;
    esac
done
set +x