#!/usr/bin/env bash
# xrdp から xrdp-chansrv に届く電文を、ヘッダだけ解読して記録する(root で実行)。
# クライアントでコピーしたときに「形式一覧(コピーの知らせ)」が届いているかを確かめるための診断用。
# strace の出力は解読用のパイプにだけ流し、中身(クリップボードのデータ)はファイルにも画面にも残さない。
# 使い方: sudo bash chansrv-trace.sh [-p chansrv の PID] [-t 秒数(既定 600)] [-o 出力先]
set -euo pipefail

usage() { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; }

pid=$(pgrep -x xrdp-chansrv | head -n1 || true)
secs=600
user_home=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
out="$user_home/.cache/chansrv-trace.log"
while getopts "p:t:o:h" opt; do
  case $opt in
    p) pid=$OPTARG ;;
    t) secs=$OPTARG ;;
    o) out=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
[[ $EUID -eq 0 ]] || { echo "root で実行してください (sudo bash $0)" >&2; exit 1; }
[[ -n $pid && -d /proc/$pid ]] || { echo "xrdp-chansrv が見つかりません" >&2; exit 1; }
command -v strace >/dev/null || { echo "strace がありません" >&2; exit 1; }

echo "[$(date +%FT%T)] start pid=$pid secs=$secs" >> "$out"
[[ -n ${SUDO_USER:-} ]] && chown "$SUDO_USER" "$out"

# -s 26: 本体の先頭 26 バイト(内側のヘッダ 18 + クリップボード電文のヘッダ 8)だけを取る
timeout "$secs" strace -f -tt -xx -s 26 -e trace=recvfrom,read -p "$pid" -o /dev/stderr 2>&1 >/dev/null \
  | python3 -I -c '
import re, struct, sys
CLIP = {1: "MONITOR_READY", 2: "FORMAT_LIST(コピーの知らせ)", 3: "FORMAT_LIST_RESPONSE",
        4: "DATA_REQUEST(中身の要求)", 5: "DATA_RESPONSE(中身の応答)", 7: "CAPS",
        8: "TEMP_DIRECTORY", 10: "LOCK", 11: "UNLOCK"}
pat = re.compile(r"(\d\d:\d\d:\d\d\.\d+) (?:recvfrom|read)\((\d+), \"((?:\\x[0-9a-f]{2})*)\".* = (\d+)")
for line in sys.stdin:
    m = pat.search(line)
    if not m:
        continue
    t, fd, hexs, n = m.groups()
    b = bytes(int(h, 16) for h in hexs.split("\\x")[1:])
    if len(b) < 26:
        continue  # 外枠の 8 バイトや X との通信は記録しない
    msg_id, _size, chan, flags, _len, total = struct.unpack_from("<IIHHHI", b)
    if msg_id != 5:
        print(f"{t} fd={fd} id={msg_id} bytes={n}", flush=True)
        continue
    if flags & 1:  # 先頭の断片だけがクリップボード電文のヘッダを持つ
        mtype, mflags, mlen = struct.unpack_from("<HHI", b, 18)
        name = CLIP.get(mtype, f"type={mtype}")
        print(f"{t} fd={fd} chan={chan} {name} status=0x{mflags:x} len={mlen} total={total}", flush=True)
    else:
        print(f"{t} fd={fd} chan={chan} (続きの断片) total={total}", flush=True)
' >> "$out"
echo "[$(date +%FT%T)] end" >> "$out"
