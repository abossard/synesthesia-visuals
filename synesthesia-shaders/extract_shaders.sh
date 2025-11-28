#!/usr/bin/env bash

if [ -n "${ZSH_VERSION:-}" ]; then
  set -eu
  set -o pipefail
else
  set -euo pipefail
fi

usage() {
  echo "Usage: $0 <shaders.json> [output-dir]" >&2
  echo "Example: $0 shaders_all-2.json extracted_shaders" >&2
}

if [[ ${1:-} == "" ]]; then
  usage
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "This script requires jq to be installed and available in PATH." >&2
  exit 1
fi

JSON_FILE=$1
OUT_ROOT=${2:-shaders_extracted}

if [[ ! -f $JSON_FILE ]]; then
  echo "Input file '$JSON_FILE' not found." >&2
  exit 1
fi

mkdir -p "$OUT_ROOT"

slugify() {
  local text
  text=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  text=$(printf '%s' "$text" | tr -cs '[:alnum:]_-' '_')
  text=${text##_}
  text=${text%%_}
  printf '%s' "${text:-shader}"
}

while IFS= read -r shader; do
  shader_id=$(jq -r '.info.id' <<<"$shader")
  shader_name=$(jq -r '.info.name' <<<"$shader")
  folder_name=$(slugify "${shader_id}_${shader_name}")
  shader_dir="$OUT_ROOT/${folder_name}"
  render_dir="$shader_dir/renderpasses"

  mkdir -p "$render_dir"

  jq '.info' <<<"$shader" >"$shader_dir/info.json"
  jq '.renderpass | map(del(.code))' <<<"$shader" >"$render_dir/metadata.json"

  while IFS= read -r pass; do
    idx=$(jq -r '.idx' <<<"$pass")
    pass_name=$(jq -r '.name' <<<"$pass")
    pass_type=$(jq -r '.type' <<<"$pass")
    file_slug=$(slugify "$(printf '%02d_%s_%s' "$((idx + 1))" "$pass_type" "$pass_name")")
    jq -r '.code' <<<"$pass" >"$render_dir/${file_slug}.glsl"
  done < <(jq -c '.renderpass | to_entries[] | {idx: .key, name: .value.name, type: .value.type, code: .value.code}' <<<"$shader")

  echo "Extracted ${shader_name} -> ${shader_dir}"
done < <(jq -c '.shaders[]' "$JSON_FILE")
