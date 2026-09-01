#!/usr/bin/env bash
set -euo pipefail

user_unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

systemctl --user disable --now reomarchy-session-snapshot.timer reomarchy-session-restore.timer reomarchy-session-restore.service 2>/dev/null || true
rm -f \
  "$user_unit_dir/reomarchy-session-restore.service" \
  "$user_unit_dir/reomarchy-session-restore.timer" \
  "$user_unit_dir/reomarchy-session-snapshot.service" \
  "$user_unit_dir/reomarchy-session-snapshot.timer" \
  "$HOME/.local/libexec/reomarchy-session"
systemctl --user daemon-reload

printf '%s\n' 'Uninstalled Continuity for Omarchy.'
printf '%s\n' 'The saved session was kept in ~/.local/state/reomarchy-session/.'
