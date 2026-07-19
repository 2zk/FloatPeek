# FloatPeek

FloatPeek is a lightweight macOS image and PDF browser that opens with a global keyboard shortcut.

[日本語](#日本語) | [English](#english)

## 日本語

FloatPeek は、よく使う画像フォルダをグローバルショートカットですばやく表示する macOS アプリです。複数のフォルダをタブとして登録し、画像や PDF の確認、Quick Look、コピー、ドラッグ＆ドロップなどを小さなフローティングウィンドウから行えます。

### 主な機能

- グローバルショートカットによるウィンドウの表示・非表示
- 複数のフォルダタブの登録と切り替え
- 画像と PDF のサムネイル表示
- ファイル名、変更日、追加日による並び替え
- 単一選択、複数選択、範囲選択
- Quick Look プレビュー
- 既定アプリで開く、Finder に表示、ファイルまたはパスのコピー
- 外部アプリへのドラッグ＆ドロップ
- 表示中フォルダの変更監視と自動再読み込み
- 日本語・英語表示
- ウィンドウ位置とサイズの保存

### 動作環境

- macOS 14.0 以降
- 対応形式: `jpg`、`jpeg`、`png`、`gif`、`heic`、`pdf`

対象フォルダ直下のファイルのみを表示します。サブフォルダ内のファイルは表示しません。

### インストール

Homebrew Tap での配布を準備中です。公開後、このセクションにインストールコマンドを追加します。

ソースからビルドする場合は Xcode が必要です。リポジトリのルートで次のコマンドを実行します。

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild build \
  -project FloatPeek.xcodeproj \
  -scheme FloatPeek \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData
```

ビルドしたアプリは次の場所に生成されます。

```text
.build/DerivedData/Build/Products/Debug/FloatPeek.app
```

### 使い方

1. FloatPeek を起動します。
2. `Settings…` を開き、`Add Tab` でタブを追加します。
3. タブ名を入力し、表示するフォルダを選択します。
4. 必要に応じてグローバルショートカットと言語を変更し、設定を保存します。
5. グローバルショートカットで FloatPeek を表示または非表示にします。

既定のグローバルショートカットは `⌘⇧1` です。

### キーボード操作

| 操作 | キー |
| --- | --- |
| FloatPeek の表示・非表示 | `⌘⇧1`（変更可能） |
| 選択の移動 | 矢印キー |
| Quick Look の表示・非表示 | `Space` |
| 既定アプリで開く | `Return` |
| 選択中ファイルをコピー | `⌘C` |
| ウィンドウを非表示 | `Escape` |

マウス操作では、`⌘` を押しながらクリックすると選択を追加・解除でき、`Shift` を押しながらクリックすると範囲選択できます。

### テスト

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
  -project FloatPeek.xcodeproj \
  -scheme FloatPeek \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData
```

### 現在の制限

- App Sandbox には対応していません。
- App Store での配布には対応していません。
- ファイルの削除、名前変更、移動、検索、画像編集には対応していません。

## English

FloatPeek is a macOS app for quickly opening frequently used image folders with a global keyboard shortcut. Register multiple folders as tabs, then browse images and PDFs, use Quick Look, copy files, or drag them into other apps from a compact floating window.

### Features

- Show or hide the window with a global keyboard shortcut
- Register and switch between multiple folder tabs
- Display thumbnails for images and PDFs
- Sort by file name, date modified, or date added
- Single, multiple, and range selection
- Quick Look previews
- Open with the default app, reveal in Finder, or copy files and paths
- Drag and drop files into other apps
- Monitor the visible folder and reload automatically when it changes
- English and Japanese interfaces
- Restore the saved window position and size

### Requirements

- macOS 14.0 or later
- Supported formats: `jpg`, `jpeg`, `png`, `gif`, `heic`, `pdf`

FloatPeek displays files directly inside the selected folder. Files in subfolders are not included.

### Installation

Distribution through a Homebrew tap is in preparation. The installation command will be added here when the tap is published.

Building from source requires Xcode. Run the following command from the repository root:

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild build \
  -project FloatPeek.xcodeproj \
  -scheme FloatPeek \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData
```

The built app is generated at:

```text
.build/DerivedData/Build/Products/Debug/FloatPeek.app
```

### Usage

1. Launch FloatPeek.
2. Open `Settings…` and select `Add Tab`.
3. Enter a tab name and choose the folder to display.
4. Optionally change the global shortcut and language, then save the settings.
5. Use the global shortcut to show or hide FloatPeek.

The default global shortcut is `⌘⇧1`.

### Keyboard controls

| Action | Key |
| --- | --- |
| Show or hide FloatPeek | `⌘⇧1` (customizable) |
| Move the selection | Arrow keys |
| Show or hide Quick Look | `Space` |
| Open with the default app | `Return` |
| Copy selected files | `⌘C` |
| Hide the window | `Escape` |

With the mouse, Command-click toggles individual items and Shift-click selects a range.

### Tests

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
  -project FloatPeek.xcodeproj \
  -scheme FloatPeek \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData
```

### Current limitations

- App Sandbox is not supported.
- App Store distribution is not supported.
- File deletion, renaming, moving, search, and image editing are not supported.
