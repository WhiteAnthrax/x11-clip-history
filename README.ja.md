# x11-clip-history

[English](README.md)

X11 向けの小さなクリップボード履歴ツールです(テキストと画像に対応)。**xrdp** のように、クリップボードを中継する仕組みに負担をかけない作りにしています。

xrdp で接続していると、クリップボード共有が途中で止まり、再接続するまで直らないことがよくありました。調べてみると、一般的なクリップボードマネージャが xrdp に大量の要求を送っていたので、作りました。

## なぜ作ったか

xrdp は `xrdp-chansrv` を通してクリップボードを中継しています。xrdp v0.10.x の chansrv(`sesman/chansrv/clipboard.c`)には、次の特徴があります。

- 応答待ちの要求を **1 件しか保持できない**(`g_saved_selection_req_event`)。要求が重なると、片方に応答しないことがある。実際に、clipman が同じ画像を要求していたとき、chansrv が別の要求に 30 秒間応答しないことを確認した。
- 画像は `image/bmp`(CF_DIB)でしか提供しない。`image/png` などを要求すると断られる(chansrv のログに `unknown target` と出る)。
- 再接続しても chansrv は作り直されない。作り直されるのは、RDP の通信路と、クライアントから届く形式一覧だけ。

Xvfb 上で chansrv の代わりを置き、1 回のコピーで出る要求を数えた結果です。

| ツール | 画像 | テキスト |
|---|---|---|
| xfce4-clipman 1.7 | png/jpeg/gif を要求して断られたあと、bmp を 2 回 | 1 回 |
| CopyQ 16(画像プラグインを無効にしても同じ) | bmp を 5 回 | 5 回 |
| **clip-history** | **1 回** | **1 回** |

`clip-history` は、まず `TARGETS` で提供されている形式を確かめ、実際にある形式を **1 回だけ** 要求します。応答待ちの間は次の要求を出さず、30 秒たっても応答がなければ待つのをやめます。

今のところ、clipman を clip-history に置き換えることで回避しています。要求が重なることが、xrdp のクリップボード共有が止まる根本原因なのかは、まだ確定していません。

## 機能

- CLIPBOARD にコピーされたテキストと画像を記録する。PRIMARY(選択しただけの文字)は記録しない。
- 画像は PNG に変換して、ピクチャフォルダの下の `clipboard/` に保存する。日本語環境では `~/画像/clipboard/` になる。既定で 300 枚まで残す。
- テキストは `~/.local/share/clip-history/texts.json` に保存する。権限は 600 で、既定で 300 件まで残す。同じテキストをコピーすると先頭に移る。
- `clip-history pick` で履歴を zenity の一覧に表示し、選んだものをクリップボードに戻す。一覧が開いているときにもう一度実行すると閉じるので、Super+V などのキーに割り当てて開閉に使える。
- 画面の文言は、日本語環境なら日本語、それ以外では英語になる。

## 必要なもの

- X11 セッション(Wayland ネイティブのクリップボードには対応していない)
- Python 3、PyGObject(GTK 3)
  - Arch: `python-gobject`
  - Debian/Ubuntu: `python3-gi gir1.2-gtk-3.0`
- `zenity`、`xclip`

## インストール

```sh
git clone https://github.com/WhiteAnthrax/x11-clip-history.git
cd x11-clip-history
./install.sh --dry-run                 # 実行内容を表示するだけ
./install.sh --bind-super-v --start    # Xfce: Super+V を割り当て、すぐに起動する
```

`install.sh` は次の作業を行います。

- `~/.local/bin/clip-history` から `bin/clip-history` へのシンボリックリンクを作る
- `~/.config/autostart/clip-history.desktop` を置く
- `--bind-super-v` を付けると、Super+V に `clip-history pick` を割り当てる(Xfce のみ)
- `--start` を付けると、今のセッションで常駐プロセスを起動する

Xfce 以外のデスクトップでは、`~/.local/bin/clip-history pick` を自分でキーに割り当ててください。

ほかのクリップボードマネージャ(clipman、CopyQ など)は、先に止めておいてください。Xfce の clipman の場合は、終了させたうえで、`~/.config/autostart/xfce4-clipman-plugin-autostart.desktop` に `Hidden=true` を設定します。

アンインストールは `./install.sh --uninstall` で行います。履歴のデータは消さずに残します。

## 使い方

```sh
clip-history            # 記録用の常駐プロセス(普段は自動起動で動く)
clip-history pick       # 履歴の一覧を表示する
clip-history -h         # オプション(保存先、上限、待ち時間、-v で詳細ログ)
```

自動起動で動かしている場合、ログは `~/.cache/clip-history.log` に出ます。

## xrdp のクリップボードが止まったときの調査

`bin/clip-snapshot.sh` は、クリップボードの状態を記録するスクリプトです。記録するのは、所有者、提供されている形式、データを取り出せるかどうか、chansrv と xrdp の直近のログです。共有が止まったら、**再接続する前に**セッション内で実行してください。クリップボードの中身は記録せず、大きさだけを記録します。結果は `~/xrdp-clip-snapshots/` に保存されます。

## 開発

```sh
pre-commit install    # gitleaks、shellcheck、Python の構文チェック
```

## ライセンス

MIT
