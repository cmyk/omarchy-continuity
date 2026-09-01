#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cli="$repo_dir/bin/reomarchy-session"

bash -n "$cli"
jq -e '
  .schemaVersion == 1
  and .id == "reomarchy.session"
  and (.kinds | index("service")) != null
  and .entryPoints.service == "Service.qml"' "$repo_dir/manifest.json" >/dev/null

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

XDG_STATE_HOME="$tmp_dir" "$cli" snapshot --quiet
state="$tmp_dir/reomarchy-session/session.json"
jq -e '
  .schemaVersion == 1
  and (.capturedAt | type == "string")
  and (.activeWorkspace.id | type == "number")
  and ([.clients[] | select(.autoRestore)] | length) > 0' "$state" >/dev/null
XDG_STATE_HOME="$tmp_dir" "$cli" plan >/dev/null
XDG_STATE_HOME="$tmp_dir" "$cli" restore >/dev/null

printf 'smoke test passed\n'
