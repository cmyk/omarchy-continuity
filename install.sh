#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
user_unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
libexec_dir="$HOME/.local/libexec"

if omarchy plugin list --json 2>/dev/null \
  | jq -e 'any(.[]; .id == "reomarchy.session" and .enabled == true)' >/dev/null; then
  printf '%s\n' 'Refusing to install while the old Quickshell service is enabled.' >&2
  printf '%s\n' 'Disable it first: omarchy plugin disable reomarchy.session' >&2
  exit 1
fi

install -Dm755 "$repo_dir/bin/reomarchy-session" "$libexec_dir/reomarchy-session"
install -Dm644 "$repo_dir/systemd/reomarchy-session-restore.service" \
  "$user_unit_dir/reomarchy-session-restore.service"
install -Dm644 "$repo_dir/systemd/reomarchy-session-snapshot.service" \
  "$user_unit_dir/reomarchy-session-snapshot.service"
install -Dm644 "$repo_dir/systemd/reomarchy-session-snapshot.timer" \
  "$user_unit_dir/reomarchy-session-snapshot.timer"

systemctl --user daemon-reload
systemctl --user enable --now reomarchy-session-restore.service reomarchy-session-snapshot.timer

printf '%s\n' 'Installed Reomarchy Session Restore outside Quickshell.'
printf '%s\n' 'Inspect it with: systemctl --user status reomarchy-session-restore.service reomarchy-session-snapshot.timer'
