# Continuity for Omarchy

**A Reomarchy project.**

Continuity reopens a useful Omarchy desktop after login: applications return
to their workspaces, while applications with their own session engines restore
their internal state. It runs as isolated systemd user services and never loads
code inside Quickshell, which owns Omarchy's bar and lock screen.

This is an early MVP. It currently understands:

- **Herdr** — Herdr restores its saved panes and exact Codex session.
- **Chromium** — Chromium restores its own windows and tabs.
- **1Password** — the locked app window returns without reading vault data.
- **btop** — allow-listed terminal commands are relaunched safely.
- **Files** — Nautilus reopens a recognizable folder below your home directory.

Plain shell terminals are intentionally not replayed. Re-executing arbitrary
shell state after login would be surprising and unsafe.

Restore commands use strict adapter-specific allowlists and are launched as
argument arrays without implicit shell execution.

## Continuity and Tableau

[Tableau](https://github.com/novuon/omarchy_tableau) is a complementary Omarchy
plugin for capturing and switching between multiple named desktops. Loading a
Tableau is an explicit action: it replaces the current desktop with the chosen
applications, terminals, services, and layout, and it deliberately does not
restore one automatically at login.

Continuity keeps one rolling snapshot of the desktop that is actually running
and restores it automatically after login. It delegates internal state to
applications such as Chromium and Herdr rather than treating the snapshot as a
reusable desktop preset.

In short: use Tableau to **save and switch desks**; use Continuity to **resume
the desk you left**. They overlap in workspace and window reconstruction, but
their lifecycle and intent are different.

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

The installer copies the engine to `~/.local/libexec/` and enables three units
for the Omarchy graphical session:

- `reomarchy-session-restore.timer` waits briefly for the graphical session and
  desktop portal, then triggers one idempotent restore pass.
- `reomarchy-session-restore.service` performs that restore pass.
- `reomarchy-session-snapshot.timer` writes an atomic snapshot every 60 seconds.

Already-running applications are not duplicated, and an empty desktop never
overwrites the last useful state. A failure is contained to these units; it
cannot crash Quickshell or the lock screen.

The snapshot also records tiled/floating state, floating-window geometry,
pinning, fullscreen mode, and workspace placement. Chromium web apps are
restored separately from ordinary Chromium browser windows. Continuity can
reopen 1Password, but it never reads vault contents or restores unlock state,
and it replaces potentially identifying 1Password window titles with a fixed
generic title in the snapshot.

During automatic login restoration, Continuity uses Omarchy's native OSD to
show progress and completion feedback. This is an IPC call to the existing
shell, not plugin code loaded into Quickshell.

Check their status with:

```bash
systemctl --user status reomarchy-session-restore.timer
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
- Chromium owns tab restoration; Continuity does not read browser history or
  profile databases.
- Tiled windows return in their saved launch order, but complex split ratios and
  grouped/tabbed container layouts are not reconstructed yet.
- A shutdown-aware final snapshot is not part of this first version.
