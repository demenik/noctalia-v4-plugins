#!/usr/bin/env bash

TARGET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/noctalia/plugins"
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/tmp/noctalia-plugins-backup-$$"
PLUGIN_PREFIX="563115:"

declare -a LINKED_ITEMS
declare -a BACKED_UP_ITEMS
declare -a COPIED_ITEMS

cleanup() {
  set +e
  echo -e "\n\n[+] Terminating script. Restoring previous state..."

  for entry in "${LINKED_ITEMS[@]}"; do
    plugin_name="${entry%%|*}"
    item_name="${entry#*|}"
    target_item_path="$TARGET_DIR/${PLUGIN_PREFIX}$plugin_name/$item_name"

    if [ -L "$target_item_path" ]; then
      echo "[-] Removing symlink: $plugin_name/$item_name"
      rm "$target_item_path"
    fi
  done

  for entry in "${COPIED_ITEMS[@]}"; do
    plugin_name="${entry%%|*}"
    item_name="${entry#*|}"
    target_item_path="$TARGET_DIR/${PLUGIN_PREFIX}$plugin_name/$item_name"

    if [ -f "$target_item_path" ]; then
      echo "[-] Removing copied file: $plugin_name/$item_name"
      rm "$target_item_path"
    fi
  done

  for entry in "${BACKED_UP_ITEMS[@]}"; do
    plugin_name="${entry%%|*}"
    item_name="${entry#*|}"
    target_item_path="$TARGET_DIR/${PLUGIN_PREFIX}$plugin_name/$item_name"
    backup_item_path="$BACKUP_DIR/$plugin_name/$item_name"

    if [ -e "$backup_item_path" ] || [ -L "$backup_item_path" ]; then
      echo "[+] Restoring backup: $plugin_name/$item_name"
      mv "$backup_item_path" "$target_item_path"
    fi
  done

  for entry in "${LINKED_ITEMS[@]}"; do
    plugin_name="${entry%%|*}"
    target_plugin_dir="$TARGET_DIR/${PLUGIN_PREFIX}$plugin_name"
    if [ -d "$target_plugin_dir" ] && [ -z "$(ls -A "$target_plugin_dir")" ]; then
      echo "[-] Removing empty target plugin dir: $plugin_name"
      rmdir "$target_plugin_dir"
    fi
  done

  if [ -d "$BACKUP_DIR" ]; then
    rm -rf "$BACKUP_DIR"
  fi

  echo "[+] Restarting Noctalia via systemctl..."
  systemctl --user restart noctalia.service
  echo "[+] Noctalia restarted successfully."

  echo "[+] Restore completed. Exiting."
  exit 0
}

trap cleanup EXIT SIGINT SIGTERM

set -e

echo "[+] Starting Noctalia plugin development mount..."
echo "[+] Target folder: $TARGET_DIR"
echo "[+] Workspace:     $WORKSPACE_DIR"

mkdir -p "$TARGET_DIR"
mkdir -p "$BACKUP_DIR"

while IFS= read -r -d '' manifest_path; do
  plugin_dir="$(dirname "$manifest_path")"
  plugin_name="$(basename "$plugin_dir")"

  if [[ "$plugin_name" == .* ]]; then
    continue
  fi

  echo "[+] Found plugin in workspace: $plugin_name"
  target_plugin_dir="$TARGET_DIR/${PLUGIN_PREFIX}$plugin_name"
  mkdir -p "$target_plugin_dir"

  while IFS= read -r -d '' item; do
    item_name="$(basename "$item")"

    if [[ "$item_name" == .* ]]; then
      continue
    fi

    target_item_path="$target_plugin_dir/$item_name"
    backup_item_path="$BACKUP_DIR/$plugin_name/$item_name"

    if [ "$item_name" = "settings.json" ]; then
      if [ -e "$target_item_path" ]; then
        echo "[~] Preserving local settings.json for: $plugin_name"
      else
        echo "[+] Copying default settings.json for: $plugin_name"
        cp "$item" "$target_item_path"
        COPIED_ITEMS+=("$plugin_name|$item_name")
      fi
      continue
    fi

    if [ -e "$target_item_path" ] || [ -L "$target_item_path" ]; then
      echo "[+] Backing up: $plugin_name/$item_name -> $backup_item_path"
      mkdir -p "$BACKUP_DIR/$plugin_name"
      mv "$target_item_path" "$backup_item_path"
      BACKED_UP_ITEMS+=("$plugin_name|$item_name")
    fi

    echo "[+] Symlinking: $plugin_name/$item_name"
    ln -s "$item" "$target_item_path"
    LINKED_ITEMS+=("$plugin_name|$item_name")

  done < <(find "$plugin_dir" -mindepth 1 -maxdepth 1 -print0)

done < <(find "$WORKSPACE_DIR" -maxdepth 2 -name manifest.json -print0)

if [ ${#LINKED_ITEMS[@]} -eq 0 ] && [ ${#COPIED_ITEMS[@]} -eq 0 ]; then
  echo "[!] No plugins found in the workspace!"
  exit 1
fi

echo "[+] Restarting Noctalia via systemctl to load linked plugins..."
systemctl --user restart noctalia.service
echo "[+] Noctalia restarted successfully."

get_last_mod_time() {
  find "$WORKSPACE_DIR" -maxdepth 3 \( -name "*.qml" -o -name "*.js" -o -name "*.json" -o -name "*.svg" \) -not -path "*/.*" -printf '%T@\n' 2>/dev/null | sort -n | tail -n 1
}

LAST_MOD=$(get_last_mod_time)

echo "[+] Plugins are actively linked. Watching for changes in files..."
echo "[+] Press Ctrl+C to terminate script and restore original state."

while true; do
  sleep 1
  CURRENT_MOD=$(get_last_mod_time)
  if [ "$CURRENT_MOD" != "$LAST_MOD" ]; then
    echo "[+] File change detected. Restarting Noctalia..."
    systemctl --user restart noctalia.service
    echo "[+] Noctalia restarted successfully."
    LAST_MOD="$CURRENT_MOD"
  fi
done
