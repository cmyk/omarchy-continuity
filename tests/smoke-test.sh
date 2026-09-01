#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cli="$repo_dir/bin/reomarchy-session"

bash -n "$cli" "$repo_dir/install.sh" "$repo_dir/uninstall.sh"
rg -q 'terminal_cwd' "$cli"
verify_output="$(systemd-analyze --user verify \
  "$repo_dir/systemd/reomarchy-session-restore.service" \
  "$repo_dir/systemd/reomarchy-session-snapshot.service" \
  "$repo_dir/systemd/reomarchy-session-snapshot.timer" 2>&1 || true)"
unexpected_verify_output="$(grep -v 'Command .*/\.local/libexec/reomarchy-session is not executable: No such file or directory' \
  <<<"$verify_output" || true)"
[[ -z "$unexpected_verify_output" ]] || {
  printf '%s\n' "$unexpected_verify_output" >&2
  exit 1
}

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
