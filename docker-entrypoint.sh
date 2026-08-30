#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_user="opencode"
readonly service_group="opencode"
readonly expected_owner="$(id -u "${service_user}"):$(id -g "${service_group}")"

readonly persistent_paths=(
  "/home/opencode/.config/opencode"
  "/home/opencode/.local/share/opencode"
  "/home/opencode/.local/state/opencode"
  "/home/opencode/.cache/opencode"
  "/home/opencode/.ssh"
  "/workspace"
)

for persistent_path in "${persistent_paths[@]}"; do
  mkdir -p -- "${persistent_path}"

  # EasyPanel volumes may be created as root. Repair existing volume contents
  # only when the volume root is not already owned by the runtime user.
  if [[ "$(stat --format='%u:%g' -- "${persistent_path}")" != "${expected_owner}" ]]; then
    chown --recursive --no-dereference "${service_user}:${service_group}" -- "${persistent_path}"
  fi
done

exec gosu "${service_user}:${service_group}" "$@"
