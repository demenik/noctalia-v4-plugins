#!/bin/sh
SHELL_BIN="${NOCTALIA_SHELL:-$(command -v noctalia-shell 2>/dev/null)}"
if [ -z "$SHELL_BIN" ]; then
  for _p in \
    /etc/profiles/per-user/"${USER}"/bin/noctalia-shell \
    "${HOME}/.local/state/nix/profiles/profile/bin/noctalia-shell" \
    "${HOME}/.nix-profile/bin/noctalia-shell"; do
    if [ -x "$_p" ]; then
      SHELL_BIN="$_p"
      break
    fi
  done
fi

if [ -n "$XDPH_WINDOW_SHARING_LIST" ]; then
  ALLOW_TOKEN="0"
  for _arg in "$@"; do
    if [ "$_arg" = "--allow-token" ]; then
      ALLOW_TOKEN="1"
      break
    fi
  done

  # Try plugin picker; fallback to hyprland-share-picker on immediate failure
  if [ -n "$SHELL_BIN" ]; then
    "$SHELL_BIN" ipc call plugin:screencast-picker showScreensharePickerForXdph \
      "$XDPH_WINDOW_SHARING_LIST" "$ALLOW_TOKEN" 2>/dev/null &
    PLUGIN_RESULT=$("$SHELL_BIN" ipc wait plugin:screencast-picker popupClosed 2>/dev/null)
    case "$PLUGIN_RESULT" in
    "[SELECTION]"*)
      echo "$PLUGIN_RESULT"
      exit 0
      ;;
    esac
  fi

  exec hyprland-share-picker "$@"
fi

# Non-XDPH mode (standalone usage)
if [ -z "$SHELL_BIN" ]; then
  echo "screencast-picker: noctalia-shell not found. Set NOCTALIA_SHELL env var or add it to PATH." >&2
  exit 1
fi
"$SHELL_BIN" ipc call plugin:screencast-picker showScreensharePicker 2>/dev/null &
exec "$SHELL_BIN" ipc wait plugin:screencast-picker popupClosed 2>/dev/null
