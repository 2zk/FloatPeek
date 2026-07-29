# FloatPeek

FloatPeek is a lightweight macOS image and PDF browser that opens with a global keyboard shortcut.

[日本語](#日本語) | [English](#english)

## 日本語

FloatPeek は、よく使う画像フォルダを小さなフローティングウィンドウで素早く確認するための macOS アプリです。グローバルショートカットで表示・非表示を切り替え、ファイルのプレビュー、コピー、共有、整理を手軽に行えます。

### 主な機能

- グローバルショートカットによるウィンドウの表示・非表示
- 複数フォルダの登録、並び替え、切り替え
- 画像と PDF のサムネイル表示
- 表示するファイル拡張子の選択
- ファイル名、変更日、追加日による並び替え
- 単一選択、複数選択、範囲選択
- Quick Look プレビュー
- 既定アプリで開く
- ファイルまたはファイルパスのコピー
- Finder での表示、ゴミ箱への移動
- 外部アプリへのドラッグ＆ドロップ
- フォルダ変更の監視と自動再読み込み
- 日本語・英語表示
- ウィンドウ位置とサイズの保存

### 動作環境

- macOS 14 Sonoma 以降
- 対応形式: `jpg`、`jpeg`、`png`、`gif`、`heic`、`pdf`

選択したフォルダ直下のファイルだけを表示します。隠しファイルとサブフォルダ内のファイルは表示しません。

### インストール

Homebrew でインストールします。

```sh
brew install --cask 2zk/tap/floatpeek
```

更新またはアンインストールする場合:

```sh
brew upgrade --cask floatpeek
brew uninstall --cask floatpeek
```

### 初回起動

配布版は ad-hoc 署名されており、Apple の公証を受けていません。macOS に起動をブロックされた場合は、ソースと配布元を確認し、FloatPeek を信頼できる場合に限り次の操作を行ってください。

1. `FloatPeek.app` を一度開き、警告を閉じます。
2. `システム設定` の `プライバシーとセキュリティ` を開きます。
3. `セキュリティ` までスクロールします。
4. FloatPeek の `このまま開く` をクリックします。
5. 確認画面でもう一度 `開く` をクリックします。

一度許可すると、次回からは通常どおり起動できます。

### はじめに

1. FloatPeek を起動します。
2. メニューバーから `設定…` を開きます。`⌘,` でも開けます。
3. `フォルダを追加` をクリックします。
4. フォルダ名を入力し、`フォルダを選択…` から対象フォルダを選びます。
5. 必要に応じて表示設定、言語、グローバルショートカットを変更します。
6. `保存` をクリックします。
7. グローバルショートカットで FloatPeek を表示または非表示にします。

既定のグローバルショートカットは `⌘⇧1` です。

### 設定

設定画面では次の項目を変更できます。

- フォルダの追加、削除、名前変更、表示順
- 起動時に選択するフォルダ
- 現在のフォルダの手動再読み込み
- ウィンドウ幅に合わせた画像拡大の有効・無効
- 表示対象の拡張子
- 表示言語（システム設定、英語、日本語）
- グローバルショートカット

表示対象の拡張子は初期状態ですべて選択されています。設定変更は `保存` をクリックしたときだけ反映され、`キャンセル` すると破棄されます。

### ファイルの選択と操作

| 操作 | 結果 |
| --- | --- |
| クリック | クリックしたファイルだけを選択 |
| `⌘` + クリック | ファイルの選択状態を追加・解除 |
| `Shift` + クリック | 基準位置からクリック位置まで範囲選択 |
| ダブルクリック | 既定アプリで開く |
| 右クリック | 操作メニューを表示 |
| ドラッグ | Finder や対応アプリへファイルをコピー |

右クリックメニューから、開く、Quick Look、コピー、ファイルパスのコピー、Finder に表示、ゴミ箱へ移動を実行できます。選択済みファイルを操作すると複数ファイルが対象になり、未選択ファイルを右クリックするとそのファイルだけが対象になります。

`ゴミ箱へ移動` は確認画面を表示せず実行されます。ファイルは完全削除されず、macOS のゴミ箱へ移動します。

### キーボード操作

| 操作 | キー |
| --- | --- |
| FloatPeek の表示・非表示 | `⌘⇧1`（変更可能） |
| 設定を開く | `⌘,` |
| 次のフォルダへ切り替え | `Control` + `Tab` |
| 前のフォルダへ切り替え | `Control` + `Shift` + `Tab` |
| 選択を移動 | 矢印キー |
| 選択範囲を拡張・縮小 | `Shift` + 矢印キー |
| Quick Look の表示・非表示 | `Space` |
| 既定アプリで開く | `Return` |
| 選択中ファイルをコピー | `⌘C` |
| 選択中ファイルをゴミ箱へ移動 | `Delete` / `Forward Delete` |
| ウィンドウを非表示 | `Escape` |

### 現在の制限

- サブフォルダ内のファイルは表示しません。
- ファイル検索、名前変更、通常のフォルダへの移動、画像編集には対応していません。
- App Sandbox と App Store 配布には対応していません。
- macOS のフルスクリーン、Mission Control、複数 Spaces で常に最前面になることは保証しません。

## English

FloatPeek is a macOS app for quickly browsing frequently used image folders in a small floating window. Show or hide it with a global shortcut, then preview, copy, share, or organize files without switching to Finder.

### Features

- Show or hide the window with a global keyboard shortcut
- Register, reorder, and switch between multiple folders
- Display thumbnails for images and PDFs
- Choose which file extensions to display
- Sort by file name, date modified, or date added
- Single, multiple, and range selection
- Quick Look previews
- Open files with their default apps
- Copy files or file paths
- Reveal files in Finder or move them to Trash
- Drag files into other apps
- Monitor the visible folder and reload automatically
- English and Japanese interfaces
- Restore the saved window position and size

### Requirements

- macOS 14 Sonoma or later
- Supported formats: `jpg`, `jpeg`, `png`, `gif`, `heic`, `pdf`

FloatPeek displays files directly inside the selected folder. Hidden files and files in subfolders are not included.

### Installation

Install FloatPeek with Homebrew:

```sh
brew install --cask 2zk/tap/floatpeek
```

To upgrade or uninstall:

```sh
brew upgrade --cask floatpeek
brew uninstall --cask floatpeek
```

### First launch

The distributed app is ad-hoc signed and is not notarized by Apple. If macOS blocks the first launch, only override the warning after checking the source and distribution origin and deciding that you trust FloatPeek.

1. Try to open `FloatPeek.app` once and close the warning.
2. Open `System Settings` and select `Privacy & Security`.
3. Scroll to `Security`.
4. Click `Open Anyway` for FloatPeek.
5. Click `Open` in the confirmation dialog.

Once allowed, the app opens normally on subsequent launches.

### Getting started

1. Launch FloatPeek.
2. Open `Settings…` from the menu bar, or press `⌘,`.
3. Click `Add Folder`.
4. Enter a folder name and choose its directory with `Choose Folder…`.
5. Optionally change the display, language, and global shortcut settings.
6. Click `Save`.
7. Use the global shortcut to show or hide FloatPeek.

The default global shortcut is `⌘⇧1`.

### Settings

The Settings window provides:

- Folder creation, removal, naming, and reordering
- Selection of the folder shown at launch
- Manual reload of the current folder
- Image scaling with the window width
- Displayed file extensions
- Language selection: System Default, English, or Japanese
- Global shortcut recording

All supported extensions are selected initially. Changes take effect only after clicking `Save`; clicking `Cancel` discards them.

### File selection and actions

| Action | Result |
| --- | --- |
| Click | Select only the clicked file |
| Command-click | Add or remove one file from the selection |
| Shift-click | Select a range from the anchor to the clicked file |
| Double-click | Open with the default app |
| Right-click | Show the action menu |
| Drag | Copy files to Finder or another compatible app |

The context menu can open or preview files, copy files or paths, reveal files in Finder, and move files to Trash. Actions on a selected file apply to the current selection; right-clicking an unselected file targets only that file.

`Move to Trash` runs without a confirmation dialog. Files are moved to the macOS Trash and are not permanently deleted.

### Keyboard controls

| Action | Key |
| --- | --- |
| Show or hide FloatPeek | `⌘⇧1` (customizable) |
| Open Settings | `⌘,` |
| Select the next folder | `Control` + `Tab` |
| Select the previous folder | `Control` + `Shift` + `Tab` |
| Move the selection | Arrow keys |
| Extend or contract the selection range | `Shift` + Arrow keys |
| Show or hide Quick Look | `Space` |
| Open with the default app | `Return` |
| Copy selected files | `⌘C` |
| Move selected files to Trash | `Delete` / `Forward Delete` |
| Hide the window | `Escape` |

### Current limitations

- Files in subfolders are not displayed.
- Search, rename, regular file moves, and image editing are not supported.
- App Sandbox and App Store distribution are not supported.
- Always-on-top behavior is not guaranteed across macOS full-screen apps, Mission Control, or multiple Spaces.
