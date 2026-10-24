# Polkit Agent

This plugin provides a Polkit authentication agent for Noctalia. It allows you to authenticate actions that require elevated privileges directly within the shell.

![Preview](preview.png)

## Important

To use this plugin, you **must disable or uninstall your existing polkit authentication agent** (e.g., `polkit-gnome`, `polkit-kde-agent`, `lxpolkit`, etc).

Having multiple polkit agents running simultaneously will cause conflicts and prevent this plugin from working correctly.

> You may need to **restart your session or computer** after enabling this plugin for the changes to take effect and for the new agent to be registered properly.

## sudo askpass

The plugin also ships `bin/noctalia-askpass`, a `SUDO_ASKPASS` helper that shows the same popup for `sudo`. This is useful where no terminal is available, for example for commands run by AI agents or from launchers, where sudo fails with "A terminal is required to authenticate".

Point `SUDO_ASKPASS` at the helper inside the installed plugin directory (plugins from custom repositories get a prefixed folder name, e.g. `<prefix>:polkit-agent`):

```sh
export SUDO_ASKPASS="$HOME/.config/noctalia/plugins/polkit-agent/bin/noctalia-askpass"
```

Then run sudo with `-A`:

```sh
sudo -A systemctl restart some.service
```

Notes:

- sudo-rs (and sudo) only use the helper when `-A` is passed; it is **not** picked up automatically when there is no TTY. Making that automatic (e.g. a wrapper that adds `-A` when stdin is not a terminal) is up to your system configuration.
- The popup shows the sudo prompt and the command being run. A wrong password makes sudo ask again; cancelling or pressing Escape aborts.
- The helper gives up after 120 seconds (override with `NOCTALIA_ASKPASS_TIMEOUT`). If the shell binary is not called `noctalia-shell`, set `NOCTALIA_SHELL`.
- Only one request is shown at a time. An askpass request made while a polkit prompt is open is rejected; a polkit request made while an askpass prompt is open waits until it is answered.
- The password is passed back through a private FIFO (mode 0600, in `$XDG_RUNTIME_DIR`) and never appears on a command line or in logs.
