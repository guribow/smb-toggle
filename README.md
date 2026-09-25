# SMBToggle

SMB 共有（NAS やほかの Mac の共有フォルダ）を、メニューバーからマウントしたり取り外したりするアプリ。コマンドライン版の `smbctl` も付いている。

Finder の「サーバへ接続」（⌘K）で毎回 URL を選んだり、取り外すたびにサイドバーの取り出しボタンを探したりする手間を省く。

- 作成：2026-09-25
- 動作確認：Mac mini（Apple Silicon）、macOS 27.2。LAN 内の別の Mac（Apple ID 認証の SMB 共有）で、マウント・取り外し・切り替えを確認

## 使い方

### メニューバー

アイコン：どれかをマウント中は塗りつぶしのドライブ `externaldrive.fill.badge.wifi`、何もマウントしていないときは線だけのドライブ `externaldrive.badge.wifi`

```
✓ share             ← クリックでマウント／取り外し（✓ はマウント中）
  photos
  backup（未登録）   ← Finder などでマウントした未登録の共有。取り外せる
──────────
  すべてマウント
  すべて取り外す
──────────
  共有を追加…
  マウント中の共有を登録   ← 未登録の共有があるときだけ出る
  登録から外す        ▸
──────────
  ログイン時に起動
  終了                ⌘Q
```

いちばん簡単な登録方法：Finder の「サーバへ接続」で一度マウントし、メニューの「マウント中の共有を登録」を選ぶ。

### コマンドライン

```bash
smbctl list                          # 一覧（登録済み＋マウント中）
smbctl add smb://nas.local/share     # 登録（表示名を続けて書ける）
smbctl on                            # 登録済みの共有をすべてマウント
smbctl on share                      # 指定した共有だけマウント（名前の一部で指定）
smbctl off                           # マウント中の SMB 共有をすべて取り外す
smbctl off -f share                  # 使用中でも強制的に取り外す
smbctl toggle share                  # マウント ⇄ 取り外し
smbctl remove share                  # 登録から外す
```

メニューバーアプリとコマンドは同じ登録ファイルを使う。

## パスワードについて

このアプリはパスワードを保存しない。マウントには macOS 標準の NetFS を使う。

- キーチェーンにパスワードがあれば、それを使って黙ってマウントする
- なければ macOS のログイン画面が出る。「このパスワードをキーチェーンに保存」にチェックすると、次からは画面が出ない

ユーザー名を指定したいときは `smb://ユーザー名@ホスト/共有名` の形で登録する。

## 安全のための仕様

- 取り外しは、使用中（ファイルを開いている）なら失敗させる。強制するのは `smbctl off -f` だけで、メニューからは強制しない
- マウントはバックグラウンドで行う。サーバーの応答待ちやログイン画面のあいだもメニューは固まらない
- アプリを終了しても、マウント中の共有はそのまま残す

## ファイル構成

| ファイル | 内容 |
|---|---|
| `SMBCore.swift` | マウント・取り外し・登録の共通処理（アプリとコマンドの両方から使う） |
| `app/main.swift` | メニューバーアプリ（`NSStatusItem`、Dock には出ない） |
| `app/Info.plist` | アプリの設定（`LSUIElement`、Bundle ID `com.guribow.smbtoggle`） |
| `cli/main.swift` | `smbctl` コマンド |
| `build.sh` | ビルドとインストール |
| `build/` | ビルド結果（生成物） |

インストール先：

- アプリ：`~/Applications/SMBToggle.app`
- コマンド：`/opt/homebrew/bin/smbctl`（`build/smbctl` へのシンボリックリンク）
- 登録ファイル：`~/Library/Application Support/smbctl/shares.json`（表示名と URL。手で編集してもよい）

## ビルド

Xcode（`swiftc`）が必要。

```bash
cd ~/ClaudWork/smb-toggle && ./build.sh
open ~/Applications/SMBToggle.app
```

## 仕組み

すべて公開 API を使っている（DisplayToggle と違い、非公開 API は使っていない）。

- マウント：`NetFSMountURLSync`（NetFS.framework）。`UIOption = AllowUI` を指定して、必要なときに macOS のログイン画面を出す。マウント先は macOS に任せる（`/Volumes/共有名`）
- 取り外し：`unmount(2)`。`-f` のときだけ `MNT_FORCE`
- マウント中かどうか：`getmntinfo` で種類が `smbfs` のものを探す。マウント元 `//user@host/share` と登録 URL を、ホスト名と共有名で照合する。大文字小文字、ユーザー名、`%20` などのエンコード、Bonjour 名（`NAS._smb._tcp.local` と `nas.local`）の違いは無視する
- アイコンの更新：`NSWorkspace` のマウント・取り外しの通知を受ける。Finder でマウントしたものにも反応する

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| 「サーバーに接続できません（エラー 65）」 | ホスト名を確認する。`.local` 名で見つからなければ IP アドレスで登録し直す |
| 「使用中のため取り外せません」 | そのボリュームのファイルを開いているアプリを閉じる。急ぐなら `smbctl off -f 名前` |
| 登録した共有がマウント中なのに ✓ が付かない | 登録 URL とマウント元のホスト名が違う（IP と名前など）。`smbctl list` で未登録として出ていれば、登録を外して「マウント中の共有を登録」で登録し直す |
| 毎回パスワードを聞かれる | ログイン画面で「キーチェーンに保存」にチェックする |
| 「ログイン時に起動」でエラーが出る | アドホック署名のアプリは `SMAppService` に登録できないことがある。システム設定 › 一般 › ログイン項目 に手動で追加する |
