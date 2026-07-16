# Screencast Picker

Interactive screen and window picker for Wayland screencast tooling. Select a monitor or window; the chosen source is emitted as an IPC signal so external scripts or tools can start the actual capture.

> This plugin is a **source selector only** — it does not record or stream. Use it with tools like `xdg-desktop-portal`, `wl-screenrec`, `wf-recorder`, `obs-studio`, or your own shell scripts via `noctalia-shell ipc listen`.

## Features

- **Screen list** — all connected monitors with resolution subtitles
- **Window list** — mapped windows (titles, classes) via compositor API
- **Live thumbnails** — `grim`-based previews on Hyprland (screens and all windows, regardless of occlusion or workspace)
- **IPC driven** — no bar widget or panel; trigger the picker and receive the result via `noctalia-shell ipc`

## Usage

Trigger the picker:

```sh
noctalia-shell ipc call plugin:screencast-picker showScreensharePicker
```

Listen for the result:

```sh
noctalia-shell ipc listen plugin:screencast-picker popupClosed
```

The result is either `screen:<name>`, `window:<address>`, or `cancelled`.

## Requirements

### Runtime

- `bash` — shell command execution
- `jq` — JSON parsing for window queries
- `hyprctl` — Hyprland compositor queries (Hyprland only)
- `grim` ≥ 1.5.0 — toplevel-export previews via `grim -T` (Hyprland only)
- `niri` — Niri compositor (Niri only; window thumbnails not yet supported on Niri)

### Noctalia Shell

- Noctalia Shell >= 4.4.1
- `Quickshell.Wayland` module (for `PanelWindow` overlay)

## Structure

```
screencast-picker/
├── i18n/
│   └── en.json
├── Main.qml
└── manifest.json
```

## IPC Commands

| Command | Description |
|---|---|
| `showScreensharePicker` | Open the picker overlay |

The picker emits `popupClosed(result)` when the user selects a source or cancels.

## License

MIT
