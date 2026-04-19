#!/usr/bin/env bash
set -euo pipefail

mode="${1:-dev}"
case "$mode" in
  dev|release|unittest) ;;
  *)
    echo "usage: ./build.sh [dev|release|unittest]" >&2
    exit 2
    ;;
esac

plugins_dir="${PLUGINS_DIR:-${OPENPLANET_DIR:-$HOME/OpenplanetNext}/Plugins}"

plugin_slug() {
  local root="$1"
  local manifest="${root%/}/info.toml"
  local pretty
  pretty="$(awk -F= '/^name/ { print $2; exit }' "$manifest" | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  pretty="${pretty:-$(basename "$root")}"
  echo "$pretty" | tr -d '+(),:;'\''"' | tr '[:upper:] ' '[:lower:]-'
}

local_dependency_root() {
  case "$1" in
    McpTM|mcp-tm) echo "../tm-mcptm" ;;
    AiApi|ai-api) echo "../tm-aiapi" ;;
    *) return 1 ;;
  esac
}

local_dependencies() {
  awk '
    /^\[script\]/ { in_script = 1; next }
    /^\[/ { in_script = 0 }
    in_script && /^[[:space:]]*dependencies[[:space:]]*=/ {
      line = $0
      gsub(/.*=\s*\[/, "", line)
      gsub(/\].*/, "", line)
      gsub(/"/, "", line)
      gsub(/,/, " ", line)
      print line
    }
  ' info.toml
}

stage_folder_plugin() {
  local root="$1"
  local slug="$2"
  local dev_suffix="${3:-0}"
  local build_mode="${4:-dev}"
  local dest="$plugins_dir/$slug"
  mkdir -p "$dest"
  rsync -a --delete "$root/src/" "$dest/"
  cp "$root/info.toml" "$dest/info.toml"
  case "$build_mode" in
    dev)
      sed -i 's/^#__DEFINES__/defines = ["DEV"]/' "$dest/info.toml"
      ;;
    unittest)
      sed -i 's/^#__DEFINES__/defines = ["UNITTEST"]/' "$dest/info.toml"
      ;;
  esac
  if [[ "$dev_suffix" == "1" ]]; then
    case "$build_mode" in
      dev)
        sed -i 's/^\(name[ \t="]*\)\(.*\)"/\1\2 (Dev)"/' "$dest/info.toml"
        ;;
      unittest)
        sed -i 's/^\(name[ \t="]*\)\(.*\)"/\1\2 (UnitTest)"/' "$dest/info.toml"
        ;;
    esac
  fi
  if [[ "${TM_PLUGIN_SKIP_LSP_CHECK:-0}" != "1" ]]; then
    openplanet-lsp check --plugins-dir "$plugins_dir" --plugin-files-search-path . "$dest"
  fi
  echo "Copied $(basename "$root") to $dest"
}

remote_load_folder() {
  local slug="$1"
  if ! command -v tm-remote-build >/dev/null 2>&1 || [[ "${TM_PLUGIN_SKIP_RELOAD:-0}" == "1" ]]; then
    return 0
  fi

  local op_dir host
  local host_args=()
  op_dir="$(dirname "$plugins_dir")"
  host="${TM_PLUGIN_REMOTE_HOST:-$(ss -ltnH 2>/dev/null | awk '$4 ~ /:30000$/ { sub(/:[0-9]+$/, "", $4); print $4; exit }')}"
  if [[ -n "$host" && "$host" != "0.0.0.0" && "$host" != "*" ]]; then
    host_args=(--host "$host")
  fi

  tm-remote-build load folder "$slug" -op OpenplanetNext "${host_args[@]}" -d "$op_dir" \
    -l "${TM_PLUGIN_REMOTE_LOG_DONE_LIMIT:-3}" \
    -i "${TM_PLUGIN_REMOTE_LOG_CHECK_INTERVAL:-0.5}"
}

stage_local_dependencies() {
  local dep root dep_slug
  for dep in $(local_dependencies); do
    if root="$(local_dependency_root "$dep")" && [[ -d "$root" ]]; then
      dep_slug="$(plugin_slug "$root")"
      stage_folder_plugin "$root" "$dep_slug" 0 "$mode"
      remote_load_folder "$dep_slug"
    fi
  done
}

plugin_name="$(plugin_slug ".")"

if [[ "$mode" == "dev" || "$mode" == "unittest" ]]; then
  if [[ "${TM_PLUGIN_STAGE_LOCAL_DEPS:-1}" != "0" ]]; then
    stage_local_dependencies
  fi
  stage_folder_plugin . "$plugin_name" 1 "$mode"
  remote_load_folder "$plugin_name"
else
  version="$(awk -F= '/^version/ { gsub(/[ "]/, "", $2); print $2; exit }' info.toml)"
  out="$plugin_name-$version.op"
  rm -f "$out"
  7z a "$out" ./src/* ./info.toml ./README.md
  echo "Built $out"
fi
