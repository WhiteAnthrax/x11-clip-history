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

- Records text and images copied to the CLIPBOARD selection, and, with `--record-primary`, text selected with the mouse (PRIMARY) in a separate history (off by default). See [CLIPBOARD and PRIMARY](#clipboard-and-primary).
- Images are converted to PNG and saved under `<Pictures>/clipboard/` (1,000 files by default; screenshots of a few MB each add up to several GB, so adjust `--keep-images` as needed).
- Text and the list of images are stored in SQLite at `~/.local/share/clip-history/history.db` with mode 600 (10,000 text entries by default). Copying the same text or image again moves it to the top.
- `texts.json` / `primary.json` and saved images from earlier versions are imported into the database when the daemon first starts. The JSON files are kept with a `.migrated` suffix.
- When enabled, PRIMARY is stored in the same database as a separate history (10,000 entries by default). A selection is recorded once it has not changed for 1 second; a selection that only extends or shrinks the previous entry (within 30 seconds) replaces it. Note that everything you select with the mouse is recorded, including passwords shown in a terminal, which is why it is off by default. To keep selected text, copy it (e.g. Ctrl+Insert) so that it goes into the CLIPBOARD history.
- `clip-history pick` shows the history in a list (images with thumbnails; the selected item is previewed on the right, with the full text for text entries) and copies the selected item back to the clipboard. Typing in the search box at the top filters the list by full text (images by file name); space-separated words must all match. Up/Down in the search box move the cursor in the list and Enter picks the item. Esc clears the search, or closes the list when the search is empty. Running it again while the list is open closes the list, so it can be bound to a key such as Super+V as a toggle.
- `clip-history pick --primary` does the same for the PRIMARY history and puts the selected item back into PRIMARY (Super+Shift+V).
- The UI is shown in Japanese on a Japanese locale and in English otherwise.

## Requirements

- An X11 session (Wayland-native clipboards are not supported)
- Python 3 and PyGObject (GTK 3)
  - Arch: `python-gobject`
  - Debian/Ubuntu: `python3-gi gir1.2-gtk-3.0`
- `xclip`

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
- with `--bind-super-v`, makes the daemon open `clip-history pick` on Super+V (`--hotkey Super+V`), and removes the Xfce Super+V shortcut set by earlier versions
- with `--record-primary`, makes the autostart entry record PRIMARY too; together with `--bind-super-v`, Super+Shift+V opens `clip-history pick --primary`
- with `--start`, starts the daemon in the current session

The daemon grabs the key directly from X instead of using the desktop's shortcut settings. If the desktop binds the same key, it wins (the log says the key is used by another program). You can still bind `clip-history pick` in the desktop's shortcut settings instead, but then the tilda support below does not work.

### Drop-down terminals such as tilda

With tilda's "hide when focus is lost" option, pressing a desktop shortcut hides tilda immediately, because X tells tilda that it lost focus as soon as the key grab activates. So when tilda is the active window, the daemon grabs the key on tilda's own window and shows the list inside tilda. tilda stays visible, and focus returns to it when the list closes. The window class is set with `--embed-class` (WM_CLASS, default `tilda`).

Stop other clipboard managers (clipman, CopyQ, etc.) first. For clipman on Xfce, quit it and set `Hidden=true` in `~/.config/autostart/xfce4-clipman-plugin-autostart.desktop`.

Uninstall with `./install.sh --uninstall`. History data is kept.

## Usage

```sh
clip-history            # run the recorder (normally started by autostart)
clip-history pick       # show the CLIPBOARD history
clip-history pick --primary  # show the PRIMARY history (with --record-primary)
clip-history -h         # options (storage paths, limits, delay, -v for verbose logs)
```

Logs go to `~/.cache/clip-history.log` when started by autostart.

## CLIPBOARD and PRIMARY

X11 has two selections that are both called "the clipboard":

| | CLIPBOARD | PRIMARY |
|---|---|---|
| Set by | Copy (Ctrl+C, etc.) | Just selecting text with the mouse |
| Pasted with | Ctrl+V, Ctrl+Shift+V in terminals | Middle click, **Shift+Insert in VTE terminals** (tilda, GNOME Terminal, etc.) |
| Shared over xrdp | Yes | No |

Text copied on the RDP client arrives in CLIPBOARD only. If you paste it with Shift+Insert in a VTE terminal, you get the text you last selected on Linux instead. Use Ctrl+Shift+Insert (or the terminal's own paste key) to paste CLIPBOARD.

## Diagnosing xrdp clipboard failures

`bin/clip-snapshot.sh` records the clipboard state (selection owners, offered targets, whether data can be fetched, recent chansrv and xrdp logs). Run it inside the session when clipboard sharing stops, **before reconnecting**. It does not record clipboard contents, only their size. Output goes to `~/xrdp-clip-snapshots/`.

Two more tools help to find out where the clipboard stops:

- `bin/clip-owner-log` logs every CLIPBOARD owner change with the owner's process name (e.g. `xrdp-chansrv` when the client announced a copy). It does not request any data. Example: `bin/clip-owner-log >> ~/.cache/clip-owner.log`
- `bin/chansrv-trace.sh` (run as root) traces what xrdp passes to `xrdp-chansrv` and logs only the message headers: channel and message type (format list, data request, data response). Clipboard contents are not written anywhere. Example: `sudo bash bin/chansrv-trace.sh -t 300` writes `~/.cache/chansrv-trace.log`.

## Development

```sh
pre-commit install    # gitleaks, shellcheck, python syntax check
```

## License

MIT
