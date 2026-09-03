#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cli="$repo_dir/bin/reomarchy-session"
resume_watch="$repo_dir/bin/reomarchy-resume-watch"

bash -n "$cli" "$resume_watch" "$repo_dir/install.sh" "$repo_dir/uninstall.sh"
rg -q 'terminal_cwd' "$cli"
rg -q 'launch_argv_direct' "$cli"
rg -q 'systemd-run --user --quiet --collect' "$cli"
rg -q 'chromium-webapp\|onepassword\) max_launch_attempts=2' "$cli"
rg -q 'tiled split proportions' "$repo_dir/README.md"
if rg -q 'shell_join_json|hl\.dsp\.exec_cmd' "$cli"; then
  printf '%s\n' 'restore commands must not be converted back into shell strings' >&2
  exit 1
fi
verify_output="$(systemd-analyze --user verify \
  "$repo_dir/systemd/reomarchy-session-restore.service" \
  "$repo_dir/systemd/reomarchy-session-restore.timer" \
  "$repo_dir/systemd/reomarchy-session-snapshot.service" \
  "$repo_dir/systemd/reomarchy-session-snapshot.timer" \
  "$repo_dir/systemd/reomarchy-resume-watch.service" 2>&1 || true)"
unexpected_verify_output="$(grep -Ev 'Command .*/\.local/libexec/reomarchy-(session|resume-watch) is not executable: No such file or directory' \
  <<<"$verify_output" || true)"
[[ -z "$unexpected_verify_output" ]] || {
  printf '%s\n' "$unexpected_verify_output" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

source "$cli"
capture="$tmp_dir/direct-launch.argv"
literal_path="$HOME/Project;"$'\n'"still-one-argument"
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

onepassword_classification="$(classify_client 1password 1 '1Password' '1Password')"
jq -e '
  .adapter == "onepassword"
  and .autoRestore == true
  and .groupKey == "app:1password"
  and .launch == ["gtk-launch", "1password"]' \
  <<<"$onepassword_classification" >/dev/null
onepassword_launch='["gtk-launch", "1password"]'
PATH="$repo_dir/tests/fakes:$PATH" REOMARCHY_TEST_CAPTURE="$capture" \
  launch_argv_direct onepassword "$onepassword_launch"
mapfile -d '' -t captured_argv < "$capture"
count="${#captured_argv[@]}"
[[ ${captured_argv[count-3]} == -- ]]
[[ ${captured_argv[count-2]} == gtk-launch ]]
[[ ${captured_argv[count-1]} == 1password ]]

fake_data="$tmp_dir/data"
mkdir -p "$fake_data/applications"
printf '%s\n' \
  '[Desktop Entry]' \
  'Type=Application' \
  'Name=Fixture App' \
  'Exec=/usr/bin/true' \
  'StartupWMClass=FixtureClass' \
  > "$fake_data/applications/org.example.Fixture.desktop"
desktop_id="$(XDG_DATA_HOME="$fake_data" XDG_DATA_DIRS=/nonexistent \
  desktop_id_for_class FixtureClass)"
[[ "$desktop_id" == org.example.Fixture ]]
desktop_classification="$(XDG_DATA_HOME="$fake_data" XDG_DATA_DIRS=/nonexistent \
  classify_client FixtureClass 999999 'Fixture' 'Fixture')"
jq -e '
  .adapter == "desktop-app"
  and .autoRestore == true
  and .groupKey == "desktop:org.example.Fixture"
  and .launch == ["gtk-launch", "org.example.Fixture"]' \
  <<<"$desktop_classification" >/dev/null
desktop_launch='["gtk-launch", "org.example.Fixture"]'
PATH="$repo_dir/tests/fakes:$PATH" REOMARCHY_TEST_CAPTURE="$capture" \
  XDG_DATA_HOME="$fake_data" XDG_DATA_DIRS=/nonexistent \
  launch_argv_direct desktop-app "$desktop_launch"
mapfile -d '' -t captured_argv < "$capture"
count="${#captured_argv[@]}"
[[ ${captured_argv[count-3]} == -- ]]
[[ ${captured_argv[count-2]} == gtk-launch ]]
[[ ${captured_argv[count-1]} == org.example.Fixture ]]

if (PATH="$repo_dir/tests/fakes:$PATH" REOMARCHY_TEST_CAPTURE="$capture" \
  XDG_DATA_HOME="$fake_data" XDG_DATA_DIRS=/nonexistent \
  launch_argv_direct desktop-app '["gtk-launch", "../unsafe"]' 2>/dev/null); then
  printf '%s\n' 'unsafe desktop ID was accepted' >&2
  exit 1
fi
printf '%s\n' \
  '[Desktop Entry]' \
  'Type=Application' \
  'Hidden=true' \
  'Exec=/usr/bin/true' \
  > "$fake_data/applications/org.example.Hidden.desktop"
if (PATH="$repo_dir/tests/fakes:$PATH" REOMARCHY_TEST_CAPTURE="$capture" \
  XDG_DATA_HOME="$fake_data" XDG_DATA_DIRS=/nonexistent \
  launch_argv_direct desktop-app '["gtk-launch", "org.example.Hidden"]' 2>/dev/null); then
  printf '%s\n' 'hidden desktop entry was accepted' >&2
  exit 1
fi

plain_shell_cwd() { printf '%s' "$HOME/Project"; }
shell_classification="$(classify_client foot 999999 'shell' 'foot')"
jq -e --arg home "$HOME" '
  .adapter == "terminal-shell"
  and .autoRestore == true
  and .groupKey == "terminal:shell:foot"
  and .cwd == ($home + "/Project")
  and .launch == ["xdg-terminal-exec", "--dir=" + $home + "/Project"]' \
  <<<"$shell_classification" >/dev/null
shell_launch="$(jq -cn --arg dir "--dir=$HOME/Project" '["xdg-terminal-exec", $dir]')"
PATH="$repo_dir/tests/fakes:$PATH" REOMARCHY_TEST_CAPTURE="$capture" \
  launch_argv_direct terminal-shell "$shell_launch"
mapfile -d '' -t captured_argv < "$capture"
count="${#captured_argv[@]}"
[[ ${captured_argv[count-3]} == -- ]]
[[ ${captured_argv[count-2]} == xdg-terminal-exec ]]
[[ ${captured_argv[count-1]} == "--dir=$HOME/Project" ]]

hyprctl() {
  printf '%s\n' '[{"address":"0xlive","pid":111,"class":"foot","workspace":{"name":"5"}}]'
}
shell_group="$(jq -cn --arg home "$HOME" '[
  {class:"foot", cwd:($home + "/Project"), workspace:{name:"5"}, focusHistoryID:0,
   launch:["xdg-terminal-exec", "--dir=" + $home + "/Project"]},
  {class:"foot", cwd:($home + "/Project"), workspace:{name:"6"}, focusHistoryID:1,
   launch:["xdg-terminal-exec", "--dir=" + $home + "/Project"]}
]')"
missing_shells="$(missing_terminal_shell_group "$shell_group")"
jq -e 'length == 1 and .[0].workspace.name == "6"' <<<"$missing_shells" >/dev/null
unset -f plain_shell_cwd hyprctl

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
  and ([.clients[] | select(.autoRestore)] | length) > 0
  and all(.clients[] | select(.adapter == "onepassword");
    .title == "1Password" and .initialTitle == "1Password")' "$state" >/dev/null
XDG_STATE_HOME="$tmp_dir" "$cli" plan >/dev/null
XDG_STATE_HOME="$tmp_dir" "$cli" restore >/dev/null

source "$resume_watch"
resume_capture="$tmp_dir/resume-capture"
fake_agents='{"id":"test","result":{"agents":[
  {"agent":"codex","agent_status":"idle","pane_id":"w1:p1","agent_session":{"kind":"id","value":"11111111-1111-1111-1111-111111111111"}},
  {"agent":"codex","agent_status":"working","pane_id":"w1:p2","agent_session":{"kind":"id","value":"22222222-2222-2222-2222-222222222222"}},
  {"agent":"claude","agent_status":"idle","pane_id":"w1:p3","agent_session":{"kind":"id","value":"33333333-3333-3333-3333-333333333333"}}
]}}'
herdr_call() {
  case "$1:$2" in
    agent:list) printf '%s\n' "$fake_agents" ;;
    agent:get) printf '%s\n' '{"result":{"agent":{"agent":"codex","agent_status":"idle","agent_session":{"kind":"id","value":"11111111-1111-1111-1111-111111111111"}}}}' ;;
    pane:process-info) printf '%s\n' '{"result":{"process_info":{"foreground_processes":[{"name":"codex","pid":4242}]}}}' ;;
    pane:run) printf 'run\t%s\t%s\n' "$3" "$4" >>"$REOMARCHY_TEST_CAPTURE" ;;
    *) return 1 ;;
  esac
}
network_ready() { :; }
REOMARCHY_TEST_CAPTURE="$resume_capture" refresh_agents >/dev/null
grep -Fqx $'terminate\t4242' "$resume_capture"
grep -Fqx $'run\tw1:p1\texec codex resume 11111111-1111-1111-1111-111111111111' "$resume_capture"
[[ $(wc -l <"$resume_capture") == 2 ]]

refresh_agents() { printf 'resume-signal\n' >>"$REOMARCHY_TEST_CAPTURE"; }
handle_sleep_signal_line '/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (true,)'
REOMARCHY_TEST_CAPTURE="$resume_capture" \
  handle_sleep_signal_line '/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (false,)'
[[ $(tail -n 1 "$resume_capture") == resume-signal ]]

printf 'smoke test passed\n'
