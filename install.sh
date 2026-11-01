#!/usr/bin/env bash
# clip-history を現在のユーザーにインストール/アンインストールする。
#   ~/.local/bin/clip-history  -> このリポジトリの bin/clip-history へのシンボリックリンク
#   ~/.config/autostart/clip-history.desktop  ログイン時の自動起動
#   (--bind-super-v 指定時) 常駐プロセスが Super+V で "clip-history pick" を開く
#   (--record-primary 指定時) PRIMARY も記録する。--bind-super-v と一緒なら
#   Super+Shift+V で "clip-history pick --primary" を開く
set -euo pipefail

usage() {
  cat <<'EOF'
usage: install.sh [--bind-super-v] [--record-primary] [--start] [--dry-run]
       install.sh --uninstall [--dry-run]

  --bind-super-v    常駐プロセスが Super+V で "clip-history pick" を開くようにする。
                    Xfce のショートカットに以前の版が割り当てた Super+V があれば外す
                    (Xfce 側で取っていると、tilda の内側に一覧を出せないため)
  --record-primary  PRIMARY(マウスで選んだ文字)も記録する。--bind-super-v と一緒なら
                    Super+Shift+V で "clip-history pick --primary" を開く
  --start         インストール後、このセッションで常駐プロセスを起動する
  --uninstall     シンボリックリンクと自動起動設定を削除し、常駐プロセスを止める
  --dry-run       実行する内容を表示するだけで、何も変更しない
EOF
}
log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
run() { if [[ $dry_run == 1 ]]; then printf '[dry-run]'; printf ' %q' "$@"; echo; else "$@"; fi; }

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bin_dir="$HOME/.local/bin"
link="$bin_dir/clip-history"
autostart="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/clip-history.desktop"
shortcut='/commands/custom/<Super>v'
shortcut_primary='/commands/custom/<Shift><Super>v'

bind=0 record_primary=0 start=0 uninstall=0 dry_run=0
for arg in "$@"; do
  case $arg in
    --bind-super-v) bind=1 ;;
    --record-primary) record_primary=1 ;;
    --start) start=1 ;;
    --uninstall) uninstall=1 ;;
    --dry-run) dry_run=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
done

stop_daemon() {
  local pids
  # pick(一覧表示)は止めない
  pids=$(pgrep -a -u "$USER" -f '^python3 \S*clip-history' | awk '!/ pick( |$)/ {print $1}' | xargs || true)
  if [[ -n $pids ]]; then
    log "常駐プロセスを停止: $pids"
    # shellcheck disable=SC2086
    run kill $pids
  fi
}

if [[ $uninstall == 1 ]]; then
  stop_daemon
  [[ -L $link ]] && { log "削除: $link"; run rm "$link"; }
  [[ -f $autostart ]] && { log "削除: $autostart"; run rm "$autostart"; }
  if command -v xfconf-query >/dev/null; then
    if [[ $(xfconf-query -c xfce4-keyboard-shortcuts -p "$shortcut" 2>/dev/null) == *"clip-history pick" ]]; then
      log "Super+V の割り当てを削除"
      run xfconf-query -c xfce4-keyboard-shortcuts -p "$shortcut" -r
    fi
    if [[ $(xfconf-query -c xfce4-keyboard-shortcuts -p "$shortcut_primary" 2>/dev/null) == *"clip-history pick --primary" ]]; then
      log "Super+Shift+V の割り当てを削除"
      run xfconf-query -c xfce4-keyboard-shortcuts -p "$shortcut_primary" -r
    fi
  fi
  log "履歴データ(~/.local/share/clip-history、ピクチャ/clipboard)は残しています"
  exit 0
fi

# 依存の確認
python3 -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk' 2>/dev/null ||
  die "PyGObject (GTK 3) が必要です (例: Arch は python-gobject、Debian/Ubuntu は python3-gi gir1.2-gtk-3.0)"
command -v xclip >/dev/null || die "xclip が必要です"

log "リンク作成: $link -> $repo/bin/clip-history"
run mkdir -p "$bin_dir"
run ln -sfn "$repo/bin/clip-history" "$link"

log "自動起動を設定: $autostart"
run mkdir -p "$(dirname "$autostart")"
run cp "$repo/autostart/clip-history.desktop" "$autostart"
daemon_args=()
if [[ $record_primary == 1 ]]; then
  daemon_args+=(--record-primary)
  log "PRIMARY も記録するよう自動起動を設定"
fi
if [[ $bind == 1 ]]; then
  daemon_args+=(--hotkey Super+V)
  [[ $record_primary == 1 ]] && daemon_args+=(--primary-hotkey Super+Shift+V)
  log "ショートカットを常駐プロセスで受け付けるよう自動起動を設定: ${daemon_args[*]}"
fi
if [[ ${#daemon_args[@]} -gt 0 ]]; then
  run sed -i "s|clip-history\"|clip-history\" ${daemon_args[*]}|" "$autostart"
fi

# Xfce のショートカットが同じキーを取っていると、そちらが先に反応する
removed=0
if [[ $bind == 1 ]] && command -v xfconf-query >/dev/null; then
  for prop in "$shortcut" "$shortcut_primary"; do
    current=$(xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" 2>/dev/null || true)
    [[ -z $current ]] && continue
    if [[ $current == *"clip-history pick"* ]]; then
      log "Xfce のショートカットを外す: ${prop##*/} ($current)"
      run xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" -r
      removed=1
    else
      log "注意: Xfce のショートカット ${prop##*/} が別のコマンドに割り当てられています ($current)。外さないと使えません"
    fi
  done
fi
# 設定から外しても、xfsettingsd はしばらくするとキーを取り直すことがある(xfce4-settings 4.20 で確認)。
# 起動し直して、外した設定を確実に反映させる
if [[ $removed == 1 && -n ${DISPLAY:-} ]] && pgrep -u "$USER" -x xfsettingsd >/dev/null; then
  log "xfsettingsd を起動し直す"
  run setsid -f xfsettingsd --replace </dev/null >/dev/null 2>&1
fi

if [[ $start == 1 ]]; then
  [[ -n ${DISPLAY:-} ]] || die "--start には DISPLAY が必要です"
  stop_daemon
  log "常駐プロセスを起動 (ログ: ~/.cache/clip-history.log)"
  run mkdir -p "$HOME/.cache"
  # shellcheck disable=SC2016  # $@ と $HOME は起動される sh 側で展開する
  run setsid -f sh -c 'exec "$@" </dev/null >/dev/null 2>>"$HOME/.cache/clip-history.log"' sh "$link" "${daemon_args[@]}"
fi

log "完了。他のクリップボードマネージャ(clipman、CopyQ など)は止めてから使ってください"
