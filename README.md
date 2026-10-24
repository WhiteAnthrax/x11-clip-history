# x11-clip-history

[日本語](README.ja.md)

A small clipboard history manager (text and images) for X11 that is gentle to clipboard bridges such as **xrdp**.

It was written because clipboard sharing in xrdp sessions kept breaking until reconnecting, and common clipboard managers turned out to flood xrdp with requests.

## Why

xrdp relays the clipboard through `xrdp-chansrv`. In xrdp v0.10.x (`sesman/chansrv/clipboard.c`), chansrv:

- keeps only **one** pending selection request (`g_saved_selection_req_event`). When requests overlap, one of them may never be answered. We observed chansrv leaving a request unanswered for 30 seconds while clipman was requesting the same image.
- offers images only as `image/bmp` (CF_DIB). Requests for `image/png` and so on are refused (`unknown target` in the chansrv log).
- is **not** restarted on reconnect. Only the RDP channel and the client's format list are rebuilt.

Requests per copy, measured on Xvfb with a fake chansrv-like selection owner:

| Tool | Image | Text |
|---|---|---|
| xfce4-clipman 1.7 | png/jpeg/gif (refused), then bmp ×2 | 1 |
| CopyQ 16 (same with the image plugin disabled) | bmp ×5 | 5 |
| **clip-history** | **1** | **1** |

`clip-history` checks `TARGETS` and then requests exactly one format that is actually offered. It never sends a second request while one is pending, and gives up after 30 seconds.

Replacing clipman with clip-history is our current workaround. Whether overlapping requests are the root cause of the xrdp clipboard breaking is not confirmed yet.

## Features

- Records text and images copied to the CLIPBOARD selection. PRIMARY is ignored.
- Images are converted to PNG and saved under `<Pictures>/clipboard/` (300 files by default).
- Text is saved to `~/.local/share/clip-history/texts.json` with mode 600 (300 entries by default). Duplicates move to the top.
- `clip-history pick` shows the history in a zenity list and copies the selected item back to the clipboard. Running it again while the list is open closes the list, so it can be bound to a key such as Super+V as a toggle.
- The UI is shown in Japanese on a Japanese locale and in English otherwise.

## Requirements

- An X11 session (Wayland-native clipboards are not supported)
- Python 3 and PyGObject (GTK 3)
  - Arch: `python-gobject`
  - Debian/Ubuntu: `python3-gi gir1.2-gtk-3.0`
- `zenity`, `xclip`

## Install

```sh
git clone https://github.com/WhiteAnthrax/x11-clip-history.git
cd x11-clip-history
./install.sh --dry-run                 # show what will be done
./install.sh --bind-super-v --start    # Xfce: bind Super+V and start now
```

`install.sh` does the following:

- symlinks `~/.local/bin/clip-history` to `bin/clip-history`
- installs `~/.config/autostart/clip-history.desktop`
- with `--bind-super-v`, binds Super+V to `clip-history pick` (Xfce only)
- with `--start`, starts the daemon in the current session

On other desktops, bind `~/.local/bin/clip-history pick` to a key yourself.

Stop other clipboard managers (clipman, CopyQ, etc.) first. For clipman on Xfce, quit it and set `Hidden=true` in `~/.config/autostart/xfce4-clipman-plugin-autostart.desktop`.

Uninstall with `./install.sh --uninstall`. History data is kept.

## Usage

```sh
clip-history            # run the recorder (normally started by autostart)
clip-history pick       # show the history list
clip-history -h         # options (storage paths, limits, delay, -v for verbose logs)
```

Logs go to `~/.cache/clip-history.log` when started by autostart.

## Diagnosing xrdp clipboard failures

`bin/clip-snapshot.sh` records the clipboard state (selection owners, offered targets, whether data can be fetched, recent chansrv and xrdp logs). Run it inside the session when clipboard sharing stops, **before reconnecting**. It does not record clipboard contents, only their size. Output goes to `~/xrdp-clip-snapshots/`.

## Development

```sh
pre-commit install    # gitleaks, shellcheck, python syntax check
```

## License

MIT
