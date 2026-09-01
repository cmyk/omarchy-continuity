# Reomarchy Session Restore

Reopens a useful Omarchy desktop after login: applications return to their
workspaces, while applications with their own session engines restore their
internal state. It runs as isolated systemd user services and never loads code
inside Quickshell, which owns Omarchy's bar and lock screen.

This is an early MVP. It currently understands:

- **Herdr** — Herdr restores its saved panes and exact Codex session.
- **Chromium** — Chromium restores its own windows and tabs.
- **btop** — allow-listed terminal commands are relaunched safely.
- **Files** — Nautilus reopens a recognizable folder below your home directory.

Plain shell terminals are intentionally not replayed. Re-executing arbitrary
shell state after login would be surprising and unsafe.

## Try it without changing anything

```bash
./bin/reomarchy-session snapshot
./bin/reomarchy-session plan
./bin/reomarchy-session restore
```

`restore` is a dry run unless `--execute` is supplied.

## Install

Clone the repository, then run:

```bash
./install.sh
```

The installer copies the engine to `~/.local/libexec/` and enables two units
for the Omarchy graphical session:

- `reomarchy-session-restore.service` performs one idempotent restore pass.
- `reomarchy-session-snapshot.timer` writes an atomic snapshot every 60 seconds.

Already-running applications are not duplicated, and an empty desktop never
overwrites the last useful state. A failure is contained to these units; it
cannot crash Quickshell or the lock screen.

The snapshot also records tiled/floating state, floating-window geometry,
pinning, fullscreen mode, and workspace placement. Chromium web apps are
restored separately from ordinary Chromium browser windows.

Check their status with:

```bash
systemctl --user status reomarchy-session-restore.service
systemctl --user status reomarchy-session-snapshot.timer
```

Uninstall with `./uninstall.sh`. The saved session is deliberately retained.

State is stored at:

```text
~/.local/state/reomarchy-session/session.json
```

## Current limits

- Workspace placement is best-effort while applications are still creating
  windows.
- Chromium owns tab restoration; Reomarchy does not read browser history or
  profile databases.
- Tiled windows return in their saved launch order, but complex split ratios and
  grouped/tabbed container layouts are not reconstructed yet.
- A shutdown-aware final snapshot is not part of this first version.
