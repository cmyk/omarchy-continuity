#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cli="$repo_dir/bin/reomarchy-session"

bash -n "$cli" "$repo_dir/install.sh" "$repo_dir/uninstall.sh"
rg -q 'terminal_cwd' "$cli"
rg -q 'launch_argv_direct' "$cli"
rg -q 'systemd-run --user --quiet --collect' "$cli"
rg -q '\[\[ "\$adapter" == chromium-webapp \]\] && max_launch_attempts=2' "$cli"
if rg -q 'shell_join_json|hl\.dsp\.exec_cmd' "$cli"; then
  printf '%s\n' 'restore commands must not be converted back into shell strings' >&2
  exit 1
fi
verify_output="$(systemd-analyze --user verify \
  "$repo_dir/systemd/reomarchy-session-restore.service" \
  "$repo_dir/systemd/reomarchy-session-restore.timer" \
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

source "$cli"
capture="$tmp_dir/direct-launch.argv"
literal_path="$HOME/Project; still-one-argument"
launch="$(jq -cn --arg path "$literal_path" '["nautilus", "--new-window", $path]')"
PATH="$repo_dir/tests/fakes:$PATH" REOMARCHY_TEST_CAPTURE="$capture" \
  launch_argv_direct files "$launch"
mapfile -d '' -t captured_argv < "$capture"
count="${#captured_argv[@]}"
[[ $count -ge 4 ]]
[[ ${captured_argv[count-4]} == -- ]]
[[ ${captured_argv[count-3]} == nautilus ]]
[[ ${captured_argv[count-2]} == --new-window ]]
[[ ${captured_argv[count-1]} == "$literal_path" ]]

tampered='["omarchy-launch-browser", "--restore-last-session", "; touch /tmp/not-allowed"]'
if (PATH="$repo_dir/tests/fakes:$PATH" REOMARCHY_TEST_CAPTURE="$capture" \
  launch_argv_direct chromium "$tampered" 2>/dev/null); then
  printf '%s\n' 'tampered launch array was accepted' >&2
  exit 1
fi

retry_launch_count="$tmp_dir/retry-launch-count"
retry_poll_count="$tmp_dir/retry-poll-count"
retry_visible_after=102
printf '0\n' > "$retry_launch_count"
printf '0\n' > "$retry_poll_count"
live_has_adapter() { return 1; }
launch_argv_direct() {
  local count
  count="$(< "$retry_launch_count")"
  printf '%d\n' "$((count + 1))" > "$retry_launch_count"
}
new_addresses_for_class() {
  local count
  count="$(< "$retry_poll_count")"
  count="$((count + 1))"
  printf '%d\n' "$count" > "$retry_poll_count"
  ((count >= retry_visible_after)) && printf '0xwebapp\n'
}
sleep() { :; }
hyprctl() {
  if [[ "${1:-}" == clients && "${2:-}" == -j ]]; then
    if (( $(< "$retry_poll_count") >= retry_visible_after )); then
      printf '%s\n' '[{"address":"0xwebapp","class":"Chromium","title":"X","workspace":{"name":"1"}}]'
    else
      printf '%s\n' '[]'
    fi
  else
    printf '%s\n' '{}'
  fi
}
retry_group='[{"adapter":"chromium-webapp","class":"Chromium","initialTitle":"x.com_/","title":"X","launch":["omarchy-launch-webapp","https://x.com/"],"workspace":{"id":1,"name":"1"},"geometry":{"at":[0,0],"size":[800,600]},"floating":false,"pinned":false,"fullscreen":0}]'
launch_group "$retry_group" >/dev/null
[[ $(< "$retry_launch_count") == 2 ]]

# A window appearing during the settle delay must prevent a duplicate launch.
printf '0\n' > "$retry_launch_count"
printf '0\n' > "$retry_poll_count"
retry_visible_after=101
launch_group "$retry_group" >/dev/null
[[ $(< "$retry_launch_count") == 1 ]]
unset -f live_has_adapter launch_argv_direct new_addresses_for_class sleep hyprctl

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
