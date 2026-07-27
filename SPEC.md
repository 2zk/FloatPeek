macOSアプリ仕様書：FloatPeek

# 1. 概要

FloatPeek は、登録した複数の画像フォルダをグローバルショートカットで素早く表示する macOS アプリである。

通常の Finder 代替ではなく、よく使う画像フォルダを小さなフローティングウィンドウとして前面表示し、画像の確認・プレビュー・既定アプリでのオープン・外部アプリへのドラッグ＆ドロップを素早く行うための個人利用ユーティリティとして実装する。

# 2. 対象環境

- OS: macOS
- 実装言語: Swift
- UI: SwiftUI
- macOS 固有機能: AppKit / Quick Look / Quick Look Thumbnailing / Carbon
- 想定ビルド環境: Xcode
- 配布形態: ローカル実行・個人利用
- アプリ形態: 通常の Dock アプリ
- App Store 配布対応: 現時点では対象外
- App Sandbox: 現時点では無効前提

# 3. 開発・ビルド運用

## 3.1 Xcode 前提

`xcodebuild` を使うため、Command Line Tools だけではなく Xcode 本体を前提とする。

確認:

```sh
xcodebuild -version
```

Xcode 本体が入っているのに選択されていない場合:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## 3.2 共通ビルド出力パス

開発時の `DerivedData` は、リポジトリ直下の `.build/DerivedData` に統一する。

リポジトリルート:

```text
.
```

共通ビルドコマンド:

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
  -project FloatPeek.xcodeproj \
  -scheme FloatPeek \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData
```

ビルド済みアプリの共通パス:

```text
.build/DerivedData/Build/Products/Debug/FloatPeek.app
```

一時検証目的で `/private/tmp` 配下に `DerivedData` を出すことは可能だが、ユーザーが起動するビルド成果物として共有する場合は上記パスを使う。

# 4. 目的

- よく使う画像保存フォルダをショートカットで即座に表示する
- 画像をサムネイル一覧で確認する
- 必要な画像を既定アプリで素早く開く
- Space キーで Quick Look プレビューする
- Slack や Finder などの外部アプリへ画像・PDFファイルをドラッグ＆ドロップする
- ウィンドウの位置とサイズを維持し、表示・非表示を繰り返しても作業環境を崩さない
- Finder を探したり切り替えたりする手間を減らす

# 5. 現行スコープ

## 5.1 実装済み機能

- グローバルショートカットでアプリ画面を表示・非表示
- 設定画面によるグローバルショートカット変更
- 複数のフォルダと選択中フォルダの保存・読み込み
- 縦方向のフォルダ一覧による表示フォルダ切り替え
- 設定画面でのフォルダ追加・削除・名称・対象設定・ドラッグによる表示順変更・再読み込み
- OSの優先言語を既定値とする英語・日本語表示
- 設定画面での表示言語切り替え
- フォルダ直下の画像・PDFファイル一覧表示
- Quick Look Thumbnailing による非同期サムネイル生成
- サムネイルのメモリキャッシュ
- 単一選択、Command クリックによるトグル選択、Shift クリックによる範囲選択
- ダブルクリックまたは Enter キーによる既定アプリでのオープン
- Space キーによる Quick Look プレビュー
- Quick Look 表示中に選択画像を変更した場合のプレビュー更新
- Escape キーによるアプリ画面の非表示
- 矢印キーによる選択移動
- タイルから外部アプリへのドラッグ＆ドロップ
- 複数選択中のファイル群のドラッグ＆ドロップ
- タイルのコンテキストメニューからのオープン、Quick Look、コピー、パスコピー、Finder表示
- Command + C による選択中ファイルのクリップボードへのコピー
- 選択中ファイルの Finder 表示
- 通常ウィンドウより前面に表示されやすいフローティングウィンドウ
- ウィンドウ位置・サイズの保存と復元
- 表示中の対象フォルダ監視による画像・PDF一覧の自動更新
- Dock に表示する専用アプリアイコン

## 5.2 現時点で対象外

- ファイル削除
- ファイル名変更
- ファイル移動
- タグ管理
- 検索
- サブフォルダ階層表示
- メニューバー常駐
- ログイン時自動起動
- Security-Scoped Bookmark 対応
- App Sandbox 対応
- App Store 配布
- iCloud 同期
- 画像編集機能

# 6. 基本仕様

## 6.1 アプリ起動

アプリ起動後、保存済みタブと選択中タブを復元し、選択中タブにフォルダが設定されていれば、そのフォルダ内の画像・PDFファイル一覧を読み込む。

タブ未登録、選択中タブのフォルダ未設定、または保存済みフォルダにアクセスできない場合は、設定画面でのタブまたはフォルダ設定を促す状態メッセージを表示する。

アプリ起動時とウィンドウ表示時に画像一覧を再読み込みする。

ウィンドウ表示中は FSEvents で対象フォルダを監視する。対象フォルダ直下の対応ファイルが追加・削除・名前変更・上書きされた場合、連続する変更イベントを約0.5秒にまとめて画像一覧を自動更新する。サブフォルダ内、隠しファイル、非対応拡張子の変更は自動更新の対象外とする。

ウィンドウを非表示または最小化した場合は監視を停止する。再表示または最小化解除時に画像一覧を再読み込みしてから監視を再開する。監視開始に失敗した場合も、手動再読み込みは引き続き利用できる。

## 6.2 タブ・フォルダ設定

ユーザーは複数のタブを登録でき、各タブに名称と対象フォルダを1つ設定できる。タブの追加・削除・名称変更・フォルダ選択は設定画面に集約する。

画面上ではタブという表現を使わず、各項目を `Folder` / `フォルダ` と表示する。内部のデータ型と保存キーは互換性維持のためタブ名称を継続する。

設定画面の各フォルダ行にはドラッグハンドルを表示する。ハンドルを別の行へドラッグすると下書き配列を並び替え、`Save` 成功時に表示順として永続化する。`Cancel` の場合は並び替えも破棄する。

設定画面のフォルダ選択ボタンから `NSOpenPanel` を表示し、ディレクトリを1つ選択する。設定画面での変更は下書きとして保持し、`Save` 成功時だけ永続化する。`Cancel` の場合は変更を破棄する。

設定条件:

```swift
panel.canChooseDirectories = true
panel.canChooseFiles = false
panel.allowsMultipleSelection = false
```

タブ配列は JSON エンコードし、選択中タブIDとともに `UserDefaults` に保存する。

保存キー:

```text
folderTabs
selectedFolderTabID
```

旧バージョンの `selectedFolderPath` が保存されている場合は、初回読み込み時にそのフォルダを持つ先頭タブへ移行する。

App Sandbox 無効のローカル利用を前提とし、Security-Scoped Bookmark は現時点では実装しない。

## 6.3 対象ファイル

対象フォルダ直下にある画像・PDFファイルのみを表示する。サブフォルダ内のファイルは表示しない。

対応拡張子:

- jpg
- jpeg
- png
- gif
- heic
- pdf

拡張子の大文字小文字は区別しない。

ヘッダーの `Sort` メニューから表示順を変更できる。

必須ソート条件:

| ソート条件 | 表示順 |
| --- | --- |
| Date Added | ファイル追加日時の新しい順。同じ日時の場合はファイル名昇順 |
| Date Modified | ファイル変更日時の新しい順。同じ日時の場合はファイル名昇順 |
| File Name | ファイル名昇順 |

既定表示は `Date Added` とする。ファイル追加日時が取得できない場合は作成日時を代替値として利用する。

## 6.4 サムネイル表示

画像・PDFファイルは `ScrollView` と `LazyVGrid` を使ってタイル状に表示する。

各タイルには以下を表示する。

- サムネイル
- ファイル名
- 選択状態のハイライト

サムネイル生成には Quick Look Thumbnailing を使う。

使用 API:

- `QLThumbnailGenerator`
- `QLThumbnailGenerator.Request`

サムネイル生成は非同期で行い、生成済みサムネイルは `ThumbnailProvider` が URL をキーにメモリキャッシュする。永続キャッシュは現時点では実装しない。

## 6.5 選択

クリック操作:

| 操作 | 動作 |
| --- | --- |
| 通常クリック | 選択をクリック対象だけに置き換える |
| Command クリック | クリック対象の選択状態をトグルする |
| Shift クリック | 選択アンカーからクリック対象までを範囲選択する |

Shift キーを押しながら矢印キーで主選択を移動した場合も、選択アンカーから移動先までを範囲選択する。アンカー方向へ戻した場合は選択範囲を縮小する。

選択中ファイルは画面下部に表示する。

表示ルール:

- 未選択: `None`
- 1件選択: ファイル名
- 複数選択: `N files`

主選択画像は Quick Look や Enter キー操作の対象になる。

## 6.6 画像を開く

タイルをダブルクリック、またはファイル選択中に Enter キーを押すと、そのファイルを macOS の既定アプリで開く。

使用 API:

```swift
NSWorkspace.shared.open(fileURL)
```

Preview.app などを明示指定せず、ユーザー環境の既定アプリを尊重する。

## 6.7 Quick Look プレビュー

ファイルを選択した状態で Space キーを押すと、選択中の画像または PDF を Quick Look でプレビュー表示する。

使用 API:

- `QLPreviewPanel`
- `QLPreviewPanelDataSource`
- `QLPreviewPanelDelegate`

Quick Look 表示中に選択画像が変わった場合は、表示中のプレビュー対象も更新する。

## 6.8 ファイルをゴミ箱へ移動

ファイル選択中に Delete または Forward Delete キーを押すと、選択中の全ファイルを確認なしでまとめてゴミ箱へ移動する。右クリックメニューの `Move to Trash` は、選択済みタイルから実行した場合は選択中の全ファイル、未選択タイルから実行した場合はその1件を対象にする。

使用 API:

```swift
NSWorkspace.shared.recycle(fileURLs)
```

移動後は元の主選択位置を基準に次の未削除ファイル、末尾の場合は直前の未削除ファイルを単一選択する。残存ファイルがない場合は選択を解除する。Quick Look 表示中は新しい主選択へ表示を更新し、残存ファイルがなければ閉じる。

移動に失敗した場合は一覧と選択を維持し、対象ファイル名または対象件数とシステムエラーを警告表示して一覧を再読み込みする。

## 6.9 ドラッグ＆ドロップ

タイルをドラッグすると、画像・PDFファイル URL を外部アプリへ渡す。

実装方式:

- `NSViewRepresentable` による AppKit ブリッジ
- `NSDraggingItem`
- `NSDraggingSource`
- `NSURL` を pasteboard writer として利用

挙動:

- 未選択タイルをドラッグした場合、その1ファイルをドラッグ対象にする
- 選択済みタイルをドラッグした場合、選択中ファイル群をドラッグ対象にする
- ドラッグ操作のコピー操作を許可する

## 6.10 グローバルショートカット

グローバルショートカットで、アプリ画面を表示・非表示できる。

初期ショートカット:

```text
Command + Shift + 1
```

ショートカットは設定画面から変更できる。保存されたショートカットは次回起動時に読み込む。

保存キー:

```text
shortcutKeyCode
shortcutModifiers
```

実装方式:

- Carbon `RegisterEventHotKey`
- Carbon `UnregisterEventHotKey`

登録に失敗した場合は、設定画面にエラーメッセージを表示し、既存ショートカット登録を維持する。

## 6.11 アプリ画面の表示・非表示

グローバルショートカットを押した場合の動作:

- アプリ画面が非表示の場合: 表示する
- アプリ画面が表示中の場合: 非表示にする

表示時には以下を行う。

- ウィンドウ設定を再適用する
- 保存済みウィンドウフレームがあれば復元する
- 保存済みフレームがなければ初期位置に配置する
- ウィンドウを前面に出す
- `NSApp.activate(ignoringOtherApps: true)` を実行する
- `AppCoordinator` の表示改訂番号を更新する
- 画像一覧を再読み込みし、選択中タブのフォルダ監視を再開する

Escape キー、またはウィンドウのクローズ操作ではアプリを終了せず、ウィンドウを非表示にする。

## 6.12 ウィンドウ表示位置・サイズ

初期サイズ:

- 幅: 160px
- 高さ: 600px
- 最小幅: 160px
- 最小高さ: 480px

未保存状態でショートカット表示する場合は、表示対象ディスプレイの左上寄りに配置する。

表示対象ディスプレイの優先順:

- マウスポインタがあるディスプレイ
- 取得できない場合はメインディスプレイ
- それも取得できない場合は `NSScreen.screens[0]`

初期配置は対象ディスプレイの `visibleFrame` に収める。メニューバーや Dock と重ならないよう、`visibleFrame` を基準にする。

## 6.13 ウィンドウ位置・サイズの永続化

アプリを一度起動した後は、ユーザーが調整したウィンドウ位置とサイズを保存する。

保存タイミング:

- ウィンドウ移動時
- ウィンドウリサイズ時
- ショートカットや Escape による非表示時
- ウィンドウクローズ操作時

保存キー:

```text
windowFrame
```

保存形式:

```swift
NSStringFromRect(window.frame)
```

復元時は `NSRectFromString` で読み込み、幅・高さが正の値であることを確認する。

保存済みフレームが現在接続されているディスプレイの表示可能領域から外れる場合は、以下の補正を行う。

- 保存フレームと交差するディスプレイを優先する
- 見つからない場合は現在のターゲットディスプレイを使う
- 幅・高さは `visibleFrame` を超えないよう縮める
- `x` / `y` は `visibleFrame` 内に収まるよう clamp する

これにより、ショートカットで非表示 → 再表示しても、ウィンドウサイズや位置が毎回初期値に戻らない。

## 6.14 常に前面に表示

アプリ画面は通常のウィンドウより前面に表示されやすいウィンドウとして扱う。

設定:

```swift
window.level = .floating
window.collectionBehavior.insert(.canJoinAllSpaces)
window.collectionBehavior.insert(.fullScreenAuxiliary)
window.isReleasedWhenClosed = false
```

通常のデスクトップ環境で他アプリウィンドウに隠れにくいことを重視する。macOS のフルスクリーンアプリ、Mission Control、複数 Spaces をまたぐ完全な挙動保証は現時点では対象外とする。

## 6.15 表示言語

対応言語は英語と日本語とする。既定値は `System Default` で、OSの優先言語から英語または日本語を選ぶ。対応外の言語環境では英語へフォールバックする。

設定画面では以下から明示的に選択できる。

- System Default
- English
- Japanese

選択値は `language` キーで `UserDefaults` に保存し、メニュー、設定項目、状態メッセージなどアプリ全体へ反映する。

# 7. UI 仕様

## 7.1 メイン画面

メイン画面には以下を表示する。

- 見出しを付けない縦方向のフォルダ一覧
- ソート条件メニュー
- 画像・PDFサムネイル一覧
- 選択中ファイル表示

フォルダの追加・削除・名称変更・対象選択・手動再読み込みはメイン画面に置かず、設定画面に集約する。

画像がない場合、フォルダ未設定の場合、アクセスできない場合は、グリッド部分に状態メッセージを表示する。

## 7.2 状態メッセージ

| 状態 | 表示 |
| --- | --- |
| フォルダ未登録 | `No folders configured` / `Add a folder in Settings.` |
| 選択中フォルダの対象未設定 | `No folder selected` / `Choose the folder in Settings.` |
| フォルダアクセス不可 | `Cannot access folder` / `Choose another folder.` |
| 対応ファイルなし | `No supported files found` / `Supported formats: jpg, jpeg, png, gif, heic, pdf.` |

## 7.3 設定画面

ディスプレイ上部の macOS メニューバーから `Settings…` を選択すると、設定画面を表示する。

ショートカット:

```text
Command + ,
```

メインウィンドウ内には設定ボタンを置かない。設定画面の呼び出しはメニューバーに集約する。

画面要素:

- フォルダ一覧
- フォルダの追加・削除
- ドラッグハンドルによる表示順の変更
- フォルダ名入力欄
- 各項目の対象フォルダ選択
- 選択中フォルダの再読み込み
- 表示言語選択
- 現在のショートカット入力欄
- `Restore Default`
- `Cancel`
- `Save`
- 登録失敗時のエラーメッセージ

ショートカット入力欄は AppKit の `NSViewRepresentable` で実装し、キーイベントから `KeyboardShortcut` を生成する。

# 8. キーボード操作

| 操作 | 動作 |
| --- | --- |
| 設定済みグローバルショートカット | アプリ画面を表示・非表示 |
| `Space` | 選択中画像または PDF を Quick Look 表示 |
| `Escape` | アプリ画面を非表示 |
| `Enter` / テンキー `Enter` | 選択中ファイルを既定アプリで開く |
| `Command + C` | 選択中ファイルをクリップボードへコピー |
| `Delete` / `Forward Delete` | 選択中の全ファイルをまとめてゴミ箱へ移動 |
| `←` | 左方向へ選択移動 |
| `→` | 右方向へ選択移動 |
| `↑` | 上方向へ選択移動 |
| `↓` | 下方向へ選択移動 |
| `Shift` + `←` / `→` / `↑` / `↓` | 選択アンカーから移動先まで範囲選択 |

ローカルキーイベントは `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` で処理する。モーダルウィンドウ表示中はメイン画面側のキー処理を行わない。

# 9. データ構造

## 9.1 ImageFile

画像・PDFファイルを表すモデル。

```swift
struct ImageFile: Identifiable, Hashable {
    let id: URL
    let url: URL
    let fileName: String
    let addedAt: Date?
    let modifiedAt: Date?
}
```

`id` はファイル URL を利用する。再読み込み時の SwiftUI 差分更新や選択状態を安定させるため、毎回 UUID は生成しない。

## 9.2 AppSettings

永続化キーと既定値を管理する。

現行キー:

```text
selectedFolderPath
shortcutKeyCode
shortcutModifiers
windowFrame
language
folderTabs
selectedFolderTabID
```

`selectedFolderPath` は旧バージョンからの移行読み込みにのみ利用する。

## 9.3 KeyboardShortcut

グローバルショートカットのキーコードと修飾キーを保持する。

```swift
struct KeyboardShortcut: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
}
```

責務:

- Carbon 用 modifier の保持
- 表示名生成
- `NSEvent` からのショートカット生成
- `UserDefaults` への保存・読み込み
- 対応キーかどうかの検証

# 10. 実装コンポーネント

## 10.1 FloatPeekApp

- SwiftUI アプリエントリポイント
- `Window` による `ContentView` 表示
- 初期フレーム制約の指定
- `AppDelegate` による起動時ショートカット登録
- `LocalizationManager`、`FolderTabManager`、`AppCoordinator` の環境注入

## 10.2 ContentView

- メイン画面の構成
- ヘッダー、状態表示、画像グリッド、選択中表示の配置
- キーボードイベント処理
- Quick Look 更新
- ウィンドウアクセサ経由の `WindowManager` 設定
- `AppCoordinator` の改訂番号に応じた再読み込み・監視開始・停止
- 設定画面の表示と `SettingsViewModel` の生成

## 10.3 ImageBrowserViewModel

- フォルダ URL と画像一覧の状態管理
- 表示状態の管理
- ソート条件の管理
- `ImageSelection` を使った選択状態の公開
- 選択中ファイルのオープン
- 再読み込み時の選択状態の整合

## 10.4 ImageSelection

- 単一・トグル・範囲選択
- 選択アンカーと主選択IDの管理
- 矢印キーとグリッド列数に基づく選択移動
- 再読み込み・ソート後に存在しない選択IDを除外

## 10.5 WindowManager

- ウィンドウ参照の解決
- 表示・非表示
- `NSWindowDelegate` による close / move / resize 処理
- フローティングウィンドウ設定
- 初期表示位置の決定
- ウィンドウフレームの保存・復元
- 画面外フレームの補正
- `NSApp.activate` 実行
- `AppCoordinator` へのウィンドウ表示・非表示通知

## 10.6 AppCoordinator

- 設定画面の表示状態管理
- ウィンドウ表示・非表示イベントの改訂番号管理
- `WindowManager` と `ContentView` 間の型付き連携

## 10.7 FolderTabManager

- タブ配列と選択中タブIDの管理
- タブと選択状態の永続化
- 旧フォルダ設定から先頭タブへの移行

## 10.8 SettingsViewModel

- 設定画面の下書き状態管理
- タブ追加・削除・フォルダ選択
- 言語とショートカットの検証・保存
- 保存成功時だけ実設定へ反映

## 10.9 FolderManager

- フォルダ選択処理

## 10.10 ImageFileLoader

- 対象フォルダ内のファイル列挙
- 対応拡張子によるフィルタリング
- ファイル追加日時の取得
- 更新日時の取得
- ファイル追加日時、ファイル変更日時、ファイル名によるソート
- `ImageFile` 配列の生成
- アクセス不可時のエラー返却

## 10.11 ThumbnailProvider

- `QLThumbnailGenerator` によるサムネイル生成
- 非同期処理
- URL をキーにしたメモリキャッシュ
- 生成失敗時の `nil` 返却

## 10.12 ImageGridView / ImageFileTile

- `LazyVGrid` によるタイル表示
- グリッド列数の反映
- サムネイル読み込み状態の表示
- 選択状態のハイライト
- ダブルクリックとドラッグ操作の AppKit ブリッジ連携

## 10.13 FileDragInteractionView

- AppKit のマウスイベントを使ったクリック、ダブルクリック、ドラッグ判定
- `NSDraggingSession` の開始
- 外部アプリへファイル URL を渡す
- 右クリック対象または選択中のファイル群をゴミ箱へ移動

## 10.14 HotKeyManager

- Carbon `RegisterEventHotKey` によるグローバルショートカット登録
- Carbon `UnregisterEventHotKey` による登録解除
- ショートカット押下時のコールバック実行
- 登録失敗時の既存ショートカット復元

## 10.15 QuickLookManager

- `QLPreviewPanel` の制御
- 選択中ファイル1件の Quick Look 表示
- Quick Look 表示中の対象ファイル更新

## 10.16 KeyboardEventBridge

- AppKit ローカルイベントモニタの導入
- Enter / Escape / Space / Delete / Forward Delete / 矢印キーの検出
- SwiftUI へのキーイベント通知
- dismantle 時のイベントモニタ解除

## 10.17 WindowAccessor

- SwiftUI から `NSWindow` を取得するための `NSViewRepresentable`
- 取得したウィンドウを `WindowManager` に渡す

# 11. エラー処理

## 11.1 フォルダ未設定

フォルダ未登録の場合はフォルダ追加を、選択中フォルダの対象未設定の場合は設定画面でのフォルダ選択を促す状態メッセージを表示する。

## 11.2 フォルダにアクセスできない

保存済みフォルダにアクセスできない場合は、画像一覧を空にし、再選択を促す。

## 11.3 対応ファイルがない

対象フォルダに対応ファイルがない場合は、その旨と対応拡張子を表示する。

## 11.4 サムネイル生成失敗

サムネイル生成に失敗した場合は、タイル内に失敗アイコンを表示する。アプリ全体は停止させない。

## 11.5 グローバルショートカット登録失敗

ショートカット設定画面で登録失敗を表示する。既存ショートカットがある場合は復元する。

# 12. パフォーマンス要件

- 対応ファイル数が数百件程度でも UI が固まらないこと
- サムネイル生成は非同期で行うこと
- 一覧表示には `LazyVGrid` を使い、必要な範囲だけ描画すること
- サムネイル生成済み画像はメモリキャッシュすること
- 表示時の再読み込みで UI 全体を長時間ブロックしないこと

数千枚規模の大量画像フォルダへの最適化は現時点では必須ではない。

# 13. 権限・セキュリティ

現時点ではローカル個人利用を想定し、App Sandbox は無効で実装する。

この前提により、ユーザーが選択したフォルダパスを `UserDefaults` に保存し、次回起動時に同じパスを読み込む。

App Sandbox を有効にする場合は、ユーザーが選択したフォルダへの継続アクセスのために Security-Scoped Bookmark を追加する必要がある。

# 14. 受け入れ条件

- アプリを起動できる
- 設定画面でフォルダを追加・削除できる
- 設定画面でフォルダをドラッグしてメイン画面の表示順を変更できる
- 各フォルダの名称と対象パスを設定できる
- メイン画面の見出しなし縦フォルダ一覧から表示フォルダを切り替えられる
- タブ、フォルダパス、選択中タブが保存される
- 次回起動時に保存済みタブと選択中フォルダを復元できる
- 旧 `selectedFolderPath` 設定を先頭タブへ移行できる
- 設定画面から選択中フォルダを手動再読み込みできる
- 既定ではファイル追加日時の新しい順で一覧表示される
- Sort メニューでファイル追加日時、ファイル変更日時、ファイル名の順に切り替えられる
- 画像・PDFファイルがサムネイル表示される
- サムネイル生成中や失敗時にアプリが落ちない
- 画像をクリックして選択できる
- Command クリックで選択状態をトグルできる
- Shift クリックで範囲選択できる
- Shift + 矢印キーで選択範囲を拡張・縮小できる
- 画像をダブルクリックすると既定アプリで開く
- ファイル選択中に Enter キーを押すと既定アプリで開く
- 画像または PDF 選択中に Space キーで Quick Look プレビューできる
- Quick Look 表示中に選択を変えるとプレビュー対象が更新される
- 画像・PDFタイルを Slack や Finder などへドラッグするとファイルとして渡せる
- 複数選択状態で選択済みタイルをドラッグすると複数ファイルを渡せる
- タイルを右クリックするとコンテキストメニューを表示できる
- Command + C で選択中ファイルをクリップボードへコピーできる
- コンテキストメニューから選択中ファイルのパスをコピーできる
- コンテキストメニューから選択中ファイルを Finder に表示できる
- Delete または Forward Delete キーで選択中の全ファイルをまとめてゴミ箱へ移動できる
- 選択済みタイルのコンテキストメニューから選択中の全ファイルをまとめてゴミ箱へ移動できる
- 未選択タイルのコンテキストメニューから右クリック対象ファイル1件をゴミ箱へ移動できる
- ゴミ箱への移動後に次または直前のファイルを選択し、Quick Lookを更新できる
- ゴミ箱への移動に失敗した場合、一覧と選択を維持して警告を表示できる
- 設定済みグローバルショートカットでアプリ画面を表示・非表示できる
- 設定画面でショートカットを変更・保存できる
- OSの優先言語に応じて英語または日本語で表示できる
- 設定画面でSystem Default・English・Japaneseを切り替えて保存できる
- アプリ画面が通常ウィンドウより前面に表示される
- Escape キーでアプリ画面を隠せる
- 保存済みフォルダにアクセスできない場合、再選択を促せる
- ショートカットで非表示 → 再表示しても、ウィンドウ位置とサイズが維持される
- 保存済みウィンドウ位置が画面外になる場合、表示可能領域内に補正される
- 共通ビルドコマンドの成果物が `.build/DerivedData/Build/Products/Debug/FloatPeek.app` に生成される
- `SWIFT_STRICT_CONCURRENCY=complete` でビルドとテストが成功する

# 15. 実装方針

- SwiftUI + AppKit 併用で macOS アプリを実装する
- Finder 代替アプリではなく、画像フォルダを素早く確認する専用ビューアとして実装する
- ファイル変更機能はゴミ箱への移動だけを実装し、完全削除、リネーム、通常の移動は実装しない
- サムネイル生成には `QLThumbnailGenerator` を使う
- ファイルを開く処理には `NSWorkspace.shared.open()` を使う
- Quick Look は `QLPreviewPanel` を使う
- ウィンドウ最前面表示には `NSWindow.Level.floating` を使う
- グローバルショートカットは Carbon `RegisterEventHotKey` を使う
- 依存ライブラリは原則追加しない
- エラー時にアプリが落ちないようにする
- 主要な処理はコンポーネントごとに分離する
- モデルに `NSImage` を持たせず、サムネイルは `ThumbnailProvider` で管理する
- ビルド確認時は共通 `DerivedData` パスを使う

# 16. 将来追加候補

- サブフォルダ対応
- サムネイルサイズ変更 UI
- ファイル名検索
- リネーム
- メニューバー常駐
- ログイン時自動起動
- Security-Scoped Bookmark 対応
- App Sandbox 対応
- App Store 配布対応
