#!/usr/bin/env bash
# xrdp のクリップボード共有が止まったときに、再接続する前の状態を記録する。
# 使い方: 共有が効かなくなったら、再接続する前に xrdp セッション内の端末で実行する。
set -euo pipefail

usage() { echo "usage: $0 [-o 出力ディレクトリ]  (既定: ~/xrdp-clip-snapshots)"; }
log() { printf '== %s\n' "$*"; }

outdir="$HOME/xrdp-clip-snapshots"
while getopts "o:h" opt; do
  case $opt in
    o) outdir=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

: "${DISPLAY:?DISPLAY が未設定です。xrdp セッション内で実行してください}"
mkdir -p "$outdir"
out="$outdir/$(date +%Y%m%d-%H%M%S).txt"
disp=${DISPLAY#:}; disp=${disp%%.*}

owner() {
  python3 - "$1" <<'EOF'
import ctypes, ctypes.util, sys
x = ctypes.cdll.LoadLibrary(ctypes.util.find_library('X11'))
x.XOpenDisplay.restype = ctypes.c_void_p
x.XGetSelectionOwner.restype = ctypes.c_ulong
d = ctypes.c_void_p(x.XOpenDisplay(None))
a = x.XInternAtom(d, sys.argv[1].encode(), 0)
print(hex(x.XGetSelectionOwner(d, ctypes.c_ulong(a))))
EOF
}

{
  log "date"; date --iso-8601=seconds
  log "processes"
  pgrep -a -f 'xrdp|chansrv|clipman|xfsettingsd|parcellite|xclip|xsel' | grep -v -e clip-snapshot -e pgrep || true

  for sel in CLIPBOARD PRIMARY CLIPBOARD_MANAGER; do
    w=$(owner "$sel")
    log "$sel owner $w"
    xwininfo -root -tree 2>/dev/null | grep -F " $w " || true
  done

  for sel in clipboard primary; do
    log "$sel TARGETS"
    timeout 3 xclip -o -selection "$sel" -t TARGETS 2>&1 || echo "(timeout/error rc=$?)"
    # 中身は秘密を含みうるので記録しない。取得できるか(と長さ)だけ見る
    log "$sel UTF8_STRING 取得テスト"
    if n=$(timeout 3 xclip -o -selection "$sel" -t UTF8_STRING 2>/dev/null | wc -c); then
      echo "ok: ${n} bytes"
    else
      echo "(timeout/error)"
    fi
  done

  log "chansrv log (tail)"
  tail -n 40 "$HOME/.local/share/xrdp/xrdp-chansrv.$disp.log" 2>&1 || true

  log "xrdp journal (直近30分)"
  journalctl -u xrdp -u xrdp-sesman --since "-30min" --no-pager 2>&1 | tail -n 60 || true
} > "$out" 2>&1

echo "保存しました: $out"
