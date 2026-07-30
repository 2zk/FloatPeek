# FloatPeek 開発仕様書

本書は FloatPeek の実装、保守、テスト、配布に関する開発者向け仕様をまとめた基準文書である。利用者向けの導入方法と操作方法は [README.md](README.md) を参照する。

# 1. プロダクト定義

## 1.1 概要

FloatPeek は、登録した画像フォルダを小さなフローティングウィンドウで表示する macOS アプリである。グローバルショートカットで素早く表示・非表示を切り替え、画像や PDF の確認、プレビュー、コピー、外部アプリへの受け渡しを行う。

Finder の代替ではなく、スクリーンショットなど頻繁に参照するファイルへ素早くアクセスするための専用ビューアとして実装する。

## 1.2 設計目標

- グローバルショートカットから即座に表示できる
- 複数の画像フォルダを少ない操作で切り替えられる
- 数百件程度のファイルを UI をブロックせず表示できる
- キーボードだけでも選択、プレビュー、コピー、整理を行える
- ウィンドウの位置とサイズを維持できる
- macOS 標準 API を優先し、外部依存を増やさない

## 1.3 現行スコープ

実装済みの主要機能:

- 複数フォルダの登録、並び替え、選択、永続化
- 画像・PDF のサムネイル一覧
- 表示対象拡張子の選択と永続化
- ファイル名、追加日、変更日によるソート
- 単一選択、トグル選択、範囲選択
- 既定アプリで開く、Quick Look、コピー、パスコピー、Finder 表示
- ゴミ箱への移動
- 外部アプリへの単一・複数ファイルのドラッグ
- 表示中フォルダの変更監視と自動再読み込み
- グローバルショートカット
- フローティングウィンドウとフレーム復元
- 英語・日本語表示

現行スコープ外:

- サブフォルダの再帰表示
- ファイル検索、名前変更、通常の移動、タグ管理
- 画像編集
- メニューバー常駐、ログイン時自動起動
- iCloud 同期
- App Sandbox、Security-Scoped Bookmark
- App Store 配布

# 2. 対象環境と技術

| 項目 | 内容 |
| --- | --- |
| OS | macOS 14.0 以降 |
| 言語 | Swift |
| UI | SwiftUI + AppKit |
| サムネイル | Quick Look Thumbnailing |
| プレビュー | Quick Look |
| ショートカット | Carbon Hot Key API |
| フォルダ監視 | FSEvents + DispatchSource |
| 永続化 | UserDefaults |
| ビルド | Xcode / xcodebuild |
| Bundle ID | `com.floatpeek.FloatPeek` |
| Swift Concurrency | `SWIFT_STRICT_CONCURRENCY = complete` |
| 外部依存 | なし |

アプリは Dock に表示する通常アプリとして動作する。App Sandbox は無効前提で、ユーザーが選択したフォルダパスを直接保存する。

# 3. 機能仕様

## 3.1 起動と終了

起動時に次の処理を行う。

1. 言語、フォルダ一覧、選択中フォルダ、表示設定、ショートカット、ウィンドウフレームを読み込む。
2. 保存済みフォルダがあれば対象ファイルを非同期で読み込む。
3. 保存済みグローバルショートカットを Carbon API へ登録する。
4. ウィンドウ表示中は選択中フォルダの監視を開始する。

最後のウィンドウを閉じてもアプリは終了しない。クローズ操作と `Escape` はウィンドウを非表示にし、グローバルショートカットから再表示できる状態を維持する。

アプリを非表示にした場合は Quick Look を閉じ、フォルダ監視を停止する。

## 3.2 フォルダ管理

利用者向け UI では内部の `Tab` という名称を表示せず、`Folder` / `フォルダ` と表記する。型名と保存キーは互換性のため `FolderTab` / `folderTabs` を維持する。

各 `FolderTab` は次の情報を持つ。

- 永続的な UUID
- 表示名
- 対象フォルダの絶対パス

設定画面で次の操作を行える。

- フォルダの追加・削除
- 表示名の編集
- `NSOpenPanel` による対象ディレクトリの選択
- ドラッグハンドルによる表示順変更
- 起動中に表示するフォルダの選択
- 現在のフォルダの手動再読み込み

フォルダ選択パネルの条件:

```swift
panel.canChooseDirectories = true
panel.canChooseFiles = false
panel.allowsMultipleSelection = false
```

保存済みフォルダがない初回起動時は、対象パスを持たないフォルダ項目を1件作る。利用者がすべて削除した状態は許容する。

設定画面の編集内容は下書きとして保持する。`Save` 成功時だけ実設定へ反映し、`Cancel` では破棄する。

旧キー `selectedFolderPath` が存在し、現行のフォルダ配列がない場合は、そのパスを持つ先頭フォルダへ移行する。

## 3.3 対象ファイルと拡張子

対象フォルダ直下の通常ファイルだけを表示する。次の項目は除外する。

- 隠しファイル
- ディレクトリ
- サブフォルダ内のファイル
- 選択されていない拡張子のファイル

対応拡張子:

```text
jpg
jpeg
png
gif
heic
pdf
```

拡張子の大文字小文字は区別しない。

設定画面では各拡張子をチェックボックスで選択する。初期値は全選択とする。空の選択も有効な設定として保存し、対象ファイルなしの状態を表示する。

保存成功時に新しい拡張子集合を次の両方へ反映する。

- `ImageFileLoader` の列挙条件
- `FolderMonitor` の監視条件

反映後は現在のフォルダを再読み込みし、表示中であれば監視を再開する。

## 3.4 ソート

ヘッダーの `Sort` メニューで次の表示順を選択できる。

| 選択値 | 動作 |
| --- | --- |
| Date Added | 追加日時の降順。同値または取得不可の場合はファイル名昇順 |
| Date Modified | 変更日時の降順。同値または取得不可の場合はファイル名昇順 |
| File Name | `localizedStandardCompare` による昇順 |

既定値は `Date Added`。追加日時が取得できない場合は作成日時を代替値にする。ソート条件は起動中だけ保持し、UserDefaults には保存しない。

ソート変更時は再列挙せず、現在の一覧を並び替える。読み込み中にソートが変わった場合は、読込結果へ最新のソート条件を再適用する。

## 3.5 サムネイル一覧

一覧は `ScrollView` と `LazyVGrid` で構成する。各タイルには次を表示する。

- サムネイル
- ファイル名
- 選択状態のハイライト
- 読み込み中または生成失敗を示す状態

`Scale images with window width` が有効な場合:

- 1列表示
- ウィンドウ幅に追従
- サムネイル領域は 4:3
- 元画像の縦横比は維持
- 生成要求サイズは 32pt 単位で切り上げ

無効な場合:

- 140pt 幅の固定列
- ウィンドウ幅に応じた複数列
- サムネイル要求サイズは 120 × 96pt

`ThumbnailProvider` は `QLThumbnailGenerator` を使用する。生成に失敗した場合は `NSImage(contentsOf:)` によるフォールバックを試み、それでも読み込めない場合は失敗表示とする。

キャッシュ仕様:

- `NSCache` によるメモリキャッシュ
- キーは標準化パス、変更日時、要求サイズ、画面スケール
- 件数上限 512
- コスト上限 64 MiB
- フォルダ変更時に全消去
- 永続キャッシュなし

## 3.6 選択

クリック操作:

| 操作 | 選択モード |
| --- | --- |
| 通常クリック | 対象1件へ置換 |
| Command クリック | 対象の選択状態をトグル |
| Shift クリック | アンカーから対象まで範囲選択 |

キーボード操作:

- 矢印キーで主選択を移動する
- 上下移動量には現在のグリッド列数を使う
- `Shift` + 矢印キーでアンカーから移動先までを範囲選択する
- 範囲をアンカー方向へ戻すと選択を縮小する
- 一覧端を越える入力は無視する
- 未選択状態で矢印キーを押すと先頭を選択する

選択状態は URL を ID として保持する。再読み込みやソート後は存在しない ID を除外し、主選択とアンカーを整合させる。主選択の変更時は該当タイルを中央付近へスクロールする。

画面下部の表示:

| 状態 | 表示 |
| --- | --- |
| 未選択 | `None` / `なし` |
| 1件 | ファイル名 |
| 複数 | `N files` / `N個のファイル` |

## 3.7 ファイルを開く

タイルのダブルクリック、`Return`、またはコンテキストメニューの `Open` で macOS の既定アプリを開く。

```swift
NSWorkspace.shared.open(fileURL)
```

特定アプリを指定せず、利用者の既定アプリ設定を尊重する。

## 3.8 Quick Look

`Space` またはコンテキストメニューの `Quick Look` で主選択ファイルを表示する。

使用 API:

- `QLPreviewPanel`
- `QLPreviewPanelDataSource`
- `QLPreviewPanelDelegate`

Quick Look 表示中に主選択が変わった場合はプレビュー対象を更新する。ウィンドウまたはアプリを非表示にした場合、対象がなくなった場合は閉じる。
スクリーンショット内のウィンドウと混同しないよう、タイトルバーを常に表示し、項目タイトルを `FloatPeek Quick Look — ファイル名` とする。
さらに、Quick Look ウィンドウ自身へ背景色を設定し、透明なタイトルバーを通して表示する。背景色はmacOS標準のウィンドウ形状でクリップされ、外周へはみ出さない。

設定画面では背景色だけを変更できる。色は不透明なsRGBとし、初期値はオレンジ（`#FF9500`）とする。変更は `Save` 成功時に保存し、表示中のQuick Lookにも反映する。

## 3.9 コピーと Finder 表示

`FileActionManager` は次の操作を提供する。

| 操作 | 実装 |
| --- | --- |
| ファイルをコピー | `NSPasteboard` へ `NSURL` を書き込む |
| パスをコピー | 改行区切りの絶対パスを文字列として書き込む |
| Finder に表示 | `NSWorkspace.shared.activateFileViewerSelecting` |

`Command+C` は選択中の全ファイルをコピーする。

コンテキストメニューの対象規則:

- 選択済みタイルから実行: 選択中の全ファイル
- 未選択タイルから実行: 右クリックした1件だけ

## 3.10 ゴミ箱への移動

`Delete`、`Forward Delete`、またはコンテキストメニューの `Move to Trash` で対象を macOS のゴミ箱へ移動する。

```swift
NSWorkspace.shared.recycle(fileURLs)
```

確認ダイアログは表示しない。完全削除は行わない。

処理中の重複要求は無視する。成功後は元の主選択位置を基準に次の未削除ファイルを選ぶ。末尾を削除した場合は直前のファイルを選び、残存ファイルがない場合は選択を解除する。

削除要求後に利用者が別の選択へ移動した場合は、その新しい選択を上書きしない。Quick Look 表示中は新しい主選択へ更新し、対象がなくなれば閉じる。

失敗時は一覧と選択を維持し、対象ファイル名または件数とシステムエラーを警告表示して再読み込みする。

## 3.11 ドラッグ＆ドロップ

`FileDragInteractionView` が SwiftUI と AppKit を橋渡しし、`NSDraggingSession` を開始する。

- 未選択タイルのドラッグ: その1件を選択し、1ファイルを渡す
- 選択済みタイルのドラッグ: 選択中の全ファイルを渡す
- Pasteboard writer: `NSURL`
- 許可する操作: `.copy`
- ドラッグ中の修飾キーは無視

Finder、Slack などファイル URL のドロップを受け付ける外部アプリを対象とする。

## 3.12 フォルダ監視

ウィンドウ表示中だけ、選択中フォルダを `FolderMonitor` で監視する。

監視対象:

- 選択済み拡張子の通常ファイル
- 対象フォルダ直下
- 追加、削除、名前変更、上書き
- 監視ルート自体の削除、名前変更、失効

監視対象外:

- 隠しファイル
- サブフォルダとその配下
- 選択されていない拡張子

実装:

- FSEvents の file events
- `kFSEventStreamCreateFlagWatchRoot`
- `DispatchSourceFileSystemObject` によるルート変更の補完
- 専用シリアルキュー
- 既定 latency 0.1秒
- 変更通知の debounce 0.5秒

ウィンドウ非表示・最小化時に監視を停止する。再表示・最小化解除時は一覧を再読み込みして監視を再開する。フォルダ切替または拡張子変更時は旧監視を停止してから新条件で開始する。

監視開始に失敗してもアプリは継続し、手動再読み込みは利用可能とする。

## 3.13 グローバルショートカット

初期値:

```text
Command + Shift + 1
```

実装 API:

- `RegisterEventHotKey`
- `UnregisterEventHotKey`
- `InstallEventHandler`

記録可能なキーは英字、数字、Space、Return、Tab、Escape、F1〜F12。少なくとも1つの修飾キーを必要とする。

設定保存時は、まず新しいショートカットの登録を試す。登録に失敗した場合は既存登録を復元し、下書き中の他設定も保存しない。起動時の登録失敗は警告ダイアログを表示する。

`Restore Default` はショートカットだけを初期値へ戻す。

## 3.14 ウィンドウ

初期値:

| 項目 | 値 |
| --- | --- |
| 幅 | 160pt |
| 高さ | 600pt |
| 最小幅 | 160pt |
| 最小高さ | 480pt |
| レベル | `.floating` |

設定:

```swift
window.tabbingMode = .disallowed
window.level = .floating
window.collectionBehavior.insert(.canJoinAllSpaces)
window.collectionBehavior.insert(.fullScreenAuxiliary)
window.isReleasedWhenClosed = false
```

初回表示位置は、マウスポインタのあるディスプレイの `visibleFrame` 左上とする。該当画面を取得できない場合はメイン画面、さらに取得できない場合は `NSScreen.screens[0]` を使う。

ウィンドウ移動、リサイズ、非表示、クローズ時に `NSStringFromRect` でフレームを保存する。復元時は現在のディスプレイ構成を確認し、表示領域外の位置と過大なサイズを `visibleFrame` 内へ補正する。

表示時は次の処理を行う。

1. ウィンドウ設定を再適用
2. 保存フレームまたは初期位置を適用
3. `makeKeyAndOrderFront`
4. `NSApp.activate(ignoringOtherApps: true)`
5. 一覧再読み込み
6. フォルダ監視開始

フルスクリーンアプリ、Mission Control、複数 Spaces をまたぐ完全な最前面動作は保証しない。

## 3.15 表示言語

対応言語:

- System Default
- English
- Japanese

System Default では macOS の優先言語から英語または日本語を選び、対応外の言語では英語へフォールバックする。

`LocalizationManager` が言語別 bundle を明示的に読み込み、SwiftUI の locale とアプリ内文字列を更新する。選択値は即時に UserDefaults へ保存されるが、設定画面では `Save` 成功時に下書き値を `LocalizationManager` へ適用する。

# 4. UI 仕様

## 4.1 メイン画面

上から次の領域で構成する。

1. フォルダ一覧
2. ソートメニュー
3. サムネイルグリッドまたは状態表示
4. 選択中ファイル表示

フォルダ一覧:

- 縦スクロール
- 各行にフォルダアイコンと表示名
- 選択中の行をアクセントカラーで強調
- 最大高さ 160pt
- フォルダ操作ボタンは配置しない

フォルダ追加、削除、名称変更、対象選択、並び替え、手動再読み込みは設定画面に集約する。

## 4.2 状態表示

`ImageBrowserViewModel.DisplayState`:

| 状態 | 表示 |
| --- | --- |
| `loading` | `Loading…` |
| `noFolderSelected` かつ項目なし | `No folders configured` / `Add a folder in Settings.` |
| `noFolderSelected` | `No folder selected` / `Choose the folder in Settings.` |
| `cannotAccessFolder` | `Cannot access folder` / `Choose another folder.` |
| `noImages` | `No supported files found` / 対応形式一覧 |
| `loaded` | サムネイルグリッド |

## 4.3 設定画面

メニューバーの `Settings…` または `Command+,` で表示する。幅は 560pt。

セクション:

1. Folders
2. Display
3. Language
4. Global Shortcut
5. Actions

Folders:

- 追加ボタン
- ドラッグハンドル
- 表示対象を示す選択ボタン
- 名前入力
- フォルダ選択
- 削除
- パス表示
- 現在のフォルダの再読み込み

Display:

- `Scale images with window width`
- `.jpg`、`.jpeg`、`.png`、`.gif`、`.heic`、`.pdf` のチェックボックス

Actions:

- `Restore Default`
- `Cancel`
- `Save`

`Save` は default action とする。ショートカット検証または登録に失敗した場合は画面を閉じず、エラーメッセージを表示する。

## 4.4 コンテキストメニュー

表示順:

1. Open
2. Quick Look
3. 区切り
4. Copy
5. Copy File Path
6. 区切り
7. Reveal in Finder
8. 区切り
9. Move to Trash

## 4.5 キーボード

| 入力 | 動作 |
| --- | --- |
| 設定済みグローバルショートカット | ウィンドウ表示・非表示 |
| `Command+,` | 設定画面 |
| `Control+Tab` | 次のフォルダ |
| `Control+Shift+Tab` | 前のフォルダ |
| `Space` | Quick Look 表示・非表示 |
| `Escape` | ウィンドウを非表示 |
| `Return` / テンキー `Enter` | 主選択を既定アプリで開く |
| `Command+C` | 選択中ファイルをコピー |
| `Delete` / `Forward Delete` | 選択中ファイルをゴミ箱へ移動 |
| 矢印キー | 主選択を移動 |
| `Shift` + 矢印キー | 範囲選択を拡張・縮小 |

ローカルキーイベントは `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` で処理する。設定などのモーダル画面表示中はメイン画面側のキー処理を行わない。

削除キーは修飾キーなし、かつキーリピートではない場合だけ処理する。フォルダ切替は表に記載した修飾キーの完全一致だけを処理する。

# 5. データモデルと永続化

## 5.1 ImageFile

```swift
struct ImageFile: Identifiable, Hashable {
    let url: URL
    let addedAt: Date?
    let modifiedAt: Date?
}
```

`id` は URL、`fileName` は `url.lastPathComponent` から算出する。再読み込みで ID を安定させるため UUID は生成しない。

## 5.2 FolderTab

```swift
struct FolderTab: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var folderPath: String
}
```

表示名の優先順位:

1. 空白を除いた設定名
2. フォルダの最終パス要素
3. `Untitled Folder` / `名称未設定のフォルダ`

## 5.3 ImageSelection

保持状態:

- `focusedID`: 主選択
- `selectedIDs`: 選択集合
- `anchorID`: 範囲選択の基準

選択操作は `replace`、`toggle`、`range` の3モードとする。

## 5.4 KeyboardShortcut

```swift
struct KeyboardShortcut: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
}
```

Carbon 用キーコードと修飾キーを保持し、表示名生成、`NSEvent` からの変換、妥当性検証、保存・読込を担当する。

## 5.5 UserDefaults

| キー | 型 | 既定値・用途 |
| --- | --- | --- |
| `folderTabs` | JSON Data | 未保存時は空パスの項目1件 |
| `selectedFolderTabID` | UUID String | 有効な保存値、なければ先頭 |
| `selectedFolderPath` | String | 旧バージョンからの移行読込専用 |
| `displayedFileExtensions` | String Array | 未保存時は全対応拡張子 |
| `scaleImagesWithWindow` | Bool | `true` |
| `shortcutKeyCode` | Int | `1` キー |
| `shortcutModifiers` | Int | Command + Shift |
| `language` | String | `system` |
| `windowFrame` | Rect String | 未保存時は初期フレーム |

`displayedFileExtensions` の空配列は未保存と区別し、「すべて非選択」として復元する。未知の拡張子は読込時に対応集合との積集合から除外する。

テスト実行中は `AppEnvironment` が `InMemoryPreferences` を選択し、標準 UserDefaults を汚染しない。判定には `XCTestConfigurationFilePath` を使う。

# 6. アーキテクチャ

## 6.1 状態所有

| 状態 | 所有者 |
| --- | --- |
| フォルダ一覧・選択中フォルダ | `FolderTabManager` |
| ファイル一覧・ソート・選択・操作状態 | `ImageBrowserViewModel` |
| 設定画面の下書き | `SettingsViewModel` |
| 表示言語 | `LocalizationManager` |
| 設定画面とウィンドウ可視性イベント | `AppCoordinator` |
| ウィンドウ参照・フレーム | `WindowManager` |
| Quick Look 対象 | `QuickLookManager` |

## 6.2 コンポーネント責務

### アプリ・画面

| コンポーネント | 責務 |
| --- | --- |
| `FloatPeekApp` | Scene、環境オブジェクト、設定コマンド、起動時ショートカット登録 |
| `ContentView` | メイン画面構成、キー操作、Quick Look 連携、設定画面生成 |
| `HeaderView` | フォルダ切替、ソート選択 |
| `ImageGridView` | 列構成、タイル配置、主選択へのスクロール |
| `ImageFileTile` | サムネイル状態、ファイル名、選択表示 |
| `SettingsView` | 設定下書きの編集と保存・破棄 |
| `StateMessageView` | 空・エラー状態表示 |

### ViewModel・モデル

| コンポーネント | 責務 |
| --- | --- |
| `ImageBrowserViewModel` | 非同期読込、表示状態、ソート、選択、ファイル操作、監視制御 |
| `SettingsViewModel` | 設定下書き、フォルダ編集、検証、保存時反映 |
| `FolderTabManager` | フォルダ配列と選択の永続化、旧設定移行 |
| `ImageSelection` | 主選択、集合、アンカー、移動と整合 |
| `AppSettings` | 保存キー、既定値、表示設定の保存・読込 |
| `LocalizationManager` | 言語解決、文字列取得、locale 提供 |

### サービス・AppKit ブリッジ

| コンポーネント | 責務 |
| --- | --- |
| `ImageFileLoader` | 直下ファイル列挙、拡張子フィルタ、日付取得、ソート |
| `FolderMonitor` | FSEvents、ルート監視、debounce |
| `ThumbnailProvider` | 非同期サムネイル生成とメモリキャッシュ |
| `FileOpener` | 既定アプリで開く |
| `FileActionManager` | コピー、パスコピー、Finder 表示、ゴミ箱 |
| `HotKeyManager` | Carbon ショートカット登録・復元 |
| `QuickLookManager` | `QLPreviewPanel` の表示・更新・終了 |
| `WindowManager` | 表示・非表示、floating 設定、フレーム保存・補正 |
| `FolderManager` | `NSOpenPanel` によるフォルダ選択 |
| `AppCoordinator` | ウィンドウ可視性と設定表示のイベント連携 |
| `KeyboardEventBridge` | ローカルキーイベントの分類と通知 |
| `FileDragInteractionView` | クリック、ダブルクリック、右クリック、ドラッグ |
| `ShortcutRecorderView` | ショートカット入力の AppKit ブリッジ |
| `WindowAccessor` | SwiftUI から `NSWindow` を取得 |

# 7. 状態遷移と非同期処理

## 7.1 フォルダ切替

```text
FolderTabManager.selectTab
  → ContentView が selectedTabID の変更を監視
  → ImageBrowserViewModel.setFolderURL
  → 現在の読込をキャンセル
  → 新フォルダを非同期読込
  → 旧監視を停止
  → 新フォルダの監視を開始
  → サムネイルキャッシュを消去
```

## 7.2 ファイル読込

`ImageBrowserViewModel` は `@MainActor` で UI 状態を管理する。ファイル列挙は `ImageFileLoader.loadImagesAsync` が detached task で実行する。

読込ごとに generation を増やし、完了時に次を検証する。

- Task がキャンセルされていない
- generation が最新
- 対象フォルダが現在値と一致

古い読込結果は UI へ反映しない。キャンセル、フォルダ切替、連続再読み込みによる競合を防ぐ。

## 7.3 設定保存

```text
SettingsView の下書き
  → ショートカット妥当性検証
  → 新ショートカット登録
  → 成功時だけ各設定を永続化
  → FolderTabManager / LocalizationManager へ反映
  → 画像拡大設定を ContentView へ反映
  → 拡張子集合を ImageBrowserViewModel へ反映
  → 必要に応じて再読込・監視再開
```

ショートカット登録失敗時は、それ以降の保存処理を行わない。

## 7.4 ウィンドウ可視性

`WindowManager` は `AppCoordinator` の revision を更新する。`ContentView` が revision の変化を監視し、表示時に再読込・監視開始、非表示時に監視停止を行う。

## 7.5 Concurrency 方針

- UI 状態と AppKit 操作は `@MainActor`
- ファイル列挙はキャンセル可能な detached task
- フォルダ監視の内部状態は専用シリアル DispatchQueue
- FSEvents callback から UI へは `Task { @MainActor in ... }`
- サムネイル生成は continuation で async 化
- Task cancellation 時は Quick Look Thumbnail request もキャンセル
- `FolderMonitor` と `ImageFileLoader` は Sendable 境界を明示

# 8. エラー処理

| 条件 | 動作 |
| --- | --- |
| フォルダ未設定 | 設定画面での選択を促す |
| フォルダアクセス不可 | 一覧と選択を空にし、再選択を促す |
| 対象ファイルなし | 対応ファイルなしを表示 |
| サムネイル生成失敗 | タイル内で失敗表示し、アプリは継続 |
| ショートカットが無効 | 設定画面にエラーを表示 |
| ショートカット登録失敗 | 旧登録を復元し、下書きを保存しない |
| 起動時ショートカット登録失敗 | `NSAlert` で設定変更を促す |
| ゴミ箱移動失敗 | 一覧・選択を維持し、システムエラーを表示 |
| フォルダ監視開始失敗 | 自動監視なしで継続し、手動再読込を維持 |

エラーを理由にアプリ全体を終了させない。

# 9. パフォーマンス要件

- 数百件程度のファイルでメインスレッドを長時間ブロックしない
- 一覧は `LazyVGrid` で必要範囲だけ描画する
- サムネイルは非同期生成し、メモリキャッシュを利用する
- 連続 FSEvents は約0.5秒にまとめる
- 不要になったファイル読込とサムネイル要求をキャンセルする
- 監視はウィンドウ表示中だけ有効にする

数千件規模のフォルダに対する仮想化や永続インデックスは現時点で必須としない。

# 10. 権限・セキュリティ・制約

## 10.1 ファイルアクセス

App Sandbox は無効。ユーザーが選択した絶対パスを UserDefaults に保存し、次回起動時に直接参照する。

Sandbox を有効化する場合は Security-Scoped Bookmark の設計と移行が必要になる。

## 10.2 ファイル変更

実装する変更操作は macOS のゴミ箱への移動だけとする。完全削除、上書き、名前変更、通常移動は行わない。

ゴミ箱移動には確認ダイアログがないため、UI と README に明記する。

## 10.3 配布署名

Apple Developer Programには加入せず、v2.0.0以降の標準配布はXcodeのad-hoc署名を使用してApple公証を行わない。配布者の身元を証明する署名ではないため、初回起動時にmacOSの許可操作が必要になる。

Hardened Runtimeは有効に保つ。ad-hoc署名ではアプリ本体とSparkle frameworkに共通のTeam IDを付与できないため、Release構成には`com.apple.security.cs.disable-library-validation` entitlementを付与し、Sparkleの動的読み込みを許可する。

Sparkleの更新ZIP、appcast、リリースノートにはEdDSA署名を付け、展開・表示前に検証する。更新の真正性はSparkle EdDSAで担保し、秘密鍵はリポジトリへ保存せず安全にバックアップする。Developer IDによる鍵変更の代替経路がないため、EdDSA秘密鍵は原則として変更しない。

# 11. 開発・ビルド・テスト

## 11.1 必要環境

- macOS
- Apple Silicon
- Xcode 本体
- Xcode Command Line Tools

確認:

```sh
xcodebuild -version
```

Xcode 本体を明示してビルドするため、コマンドでは `DEVELOPER_DIR` を指定する。

## 11.2 Debug ビルド

リポジトリルートで実行する。

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild build \
  -project FloatPeek.xcodeproj \
  -scheme FloatPeek \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData
```

成果物:

```text
.build/DerivedData/Build/Products/Debug/FloatPeek.app
```

## 11.3 全テスト

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
  -project FloatPeek.xcodeproj \
  -scheme FloatPeek \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData
```

変更箇所に近いテストから実行し、最後に全テストを実行する。

## 11.4 テスト構成

| テスト | 主な対象 |
| --- | --- |
| `AppLifecycleTests` | 環境、言語、フォルダ永続化・移行、ウィンドウ |
| `AppCoordinatorTests` | 設定表示、可視性 revision |
| `ImageFileLoaderTests` | 拡張子フィルタ、ソート、アクセスエラー |
| `FolderMonitorTests` | 変更通知、debounce、除外条件、停止・切替 |
| `ImageSelectionTests` | 単一・複数・範囲選択、移動、整合 |
| `ImageBrowserFileActionTests` | コピー、ゴミ箱、コンテキスト、キー操作 |
| `QuickLookManagerTests` | 表示終了条件 |
| `ThumbnailProviderTests` | aspect fit |
| `SettingsViewModelTests` | 下書き、保存、失敗時非反映、拡張子設定 |
| `UpdateManagerTests` | 更新確認の可否、手動確認の呼び出し |

テスト環境では `InMemoryPreferences` を使用し、ユーザーの設定を変更しない。

# 12. リリースと配布

FloatPeekはApple Developer Programへ加入せずに開発・配布する。リリース工程はDeveloper ID証明書、Apple ID、Team ID、App用パスワードを要求せず、Apple公証も行わない。

## 12.1 リリース成果物

バージョン `X.Y.Z` に対して次を生成する。

```text
dist/FloatPeek-X.Y.Z.zip
dist/FloatPeek-X.Y.Z.zip.sha256
dist/FloatPeek-X.Y.Z.md
dist/appcast.xml
```

v2.0.0以降の配布アプリに含まれるすべてのMach-Oバイナリはarm64専用とする。Intel Mac向け最終版はv1.3.0とし、以後は更新対象外とする。

## 12.2 ローカルリリースビルド

```sh
./Scripts/build-release.sh 2.0.0
```

スクリプトの処理:

1. `X.Y.Z` 形式の検証
2. `xcodebuild archive`によるarm64・ad-hoc署名のReleaseアーカイブ生成
3. Sparkle内部を含むすべてのMach-Oバイナリをarm64へthin
4. Sparkle内部コンポーネントとアプリを内側からad-hoc再署名
5. Bundle version、全Mach-Oのarm64、Sparkle内包、ad-hoc署名の確認
6. アプリへ埋め込んだSparkle EdDSA公開鍵の確認
7. ZIPと、アーカイブのファイル名だけを含むポータブルなSHA-256ファイルの生成

既存の同名 ZIP または checksum は上書きしない。

Sparkle EdDSA公開鍵は秘密情報ではないため、Xcodeプロジェクトのbuild settingとしてリポジトリ管理する。テスト用の使い捨て鍵などへ一時的に差し替える場合だけ、環境変数で指定する。

```sh
SPARKLE_PUBLIC_ED_KEY="<公開鍵>" ./Scripts/build-release.sh 2.0.0
```

続いて`SPARKLE_ED_PRIVATE_KEY`を標準入力経由でSparkleの`generate_appcast`へ渡し、`Scripts/generate-appcast.sh`で署名済みappcastを生成する。`Scripts/validate-appcast.sh`はXML構造をXPathで検証し、Sparkleの`sign_update --verify`でappcast、ZIP、リリースノートのEdDSA署名を検証する。

## 12.3 GitHub Actions

`.github/workflows/ci.yml`はPull Requestと`main`へのpushで起動し、シェルスクリプト、全テスト、使い捨てEdDSA鍵によるリリースパイプライン、Homebrew Cask styleを検証する。

`.github/workflows/release.yml`は`v*`タグpushで起動する。正式なタグ形式は`vX.Y.Z`。`validate`、`publish`、`update-homebrew`の3ジョブを順番に実行し、検証が完了するまで外部公開処理を行わない。

ワークフロー:

1. `validate`: タグ形式とSecret、シェルスクリプト、全テスト、使い捨て鍵によるリリースパイプラインを検証
2. `publish`: arm64・ad-hoc署名のアプリ、ZIP、EdDSA署名済みappcast、リリースノートを生成
3. `publish`: GitHub Releaseをドラフトで作り、全アセット確認後に公開
4. `update-homebrew`: 公開済みchecksumからHomebrew Caskを生成・検証
5. `update-homebrew`: `2zk/homebrew-tap`の`Casks/floatpeek.rb`を更新

`update-homebrew`が失敗した場合は、公開済みReleaseを変更せず、そのジョブだけを再実行できる。

必要な Repository Secret:

| Secret | 用途 |
| --- | --- |
| `HOMEBREW_TAP_GITHUB_TOKEN` | `2zk/homebrew-tap` の Contents 読み書き |
| `SPARKLE_ED_PRIVATE_KEY` | 更新署名用EdDSA秘密鍵 |

token は fine-grained personal access token とし、対象リポジトリを `homebrew-tap` のみに限定する。

ワークフロー自身は FloatPeek の GitHub Release 作成に `contents: write` を使用する。

## 12.4 Homebrew Tap

配布先:

```text
2zk/homebrew-tap
```

初期準備:

1. 空でない public repository `2zk/homebrew-tap` を作成
2. `Contents: Read and write` を持つ fine-grained token を作成
3. FloatPeek リポジトリへ `HOMEBREW_TAP_GITHUB_TOKEN` を登録
4. GitHub Actions と必要な workflow permission を有効化

`Homebrew/floatpeek.rb.template` にはバージョンと SHA-256 のプレースホルダを持たせる。`Scripts/render-homebrew-cask.sh` が値を検証して Cask を生成する。

Cask は次を定義する。

- GitHub Release の ZIP
- Apple Silicon必須
- macOS Sonoma 以降
- アプリ内自動更新
- `FloatPeek.app`
- アンインストール時に削除する preferences と saved state
- ad-hoc署名・未公証に関するcaveat

## 12.5 リリース手順

1. 対象変更を `main` に反映する。
2. 全テストを成功させる。
3. 未公開のバージョンタグを作成する。
4. タグを push する。

```sh
git tag v2.0.0
git push origin v2.0.0
```

確認項目:

- `Release` workflow が成功
- GitHub Release に ZIP、checksum、appcast、リリースノートが存在
- Homebrew Tap の Cask が更新
- `brew install --cask 2zk/tap/floatpeek` が成功

公開済みタグや ZIP は上書きせず、新しいバージョンを発行する。

# 13. 受け入れ条件

## 13.1 フォルダと表示

- フォルダを追加、削除、名称変更、並び替えできる
- 選択中フォルダと表示順を再起動後に復元できる
- 旧 `selectedFolderPath` を現行形式へ移行できる
- 直下の対応ファイルだけを表示できる
- 表示対象拡張子を選択・保存でき、未保存時は全選択になる
- 拡張子変更が一覧と監視へ反映される
- 3種類のソートが仕様どおり動作する

## 13.2 選択とファイル操作

- マウスとキーボードで単一・複数・範囲選択できる
- ソート、再読込、ファイル削除後も選択状態が整合する
- 既定アプリ、Quick Look、コピー、パスコピー、Finder 表示が動作する
- 単一・複数ファイルを外部アプリへドラッグできる
- 対象ファイルをゴミ箱へ移動できる
- ゴミ箱移動失敗時に一覧と選択を維持できる

## 13.3 ウィンドウと設定

- グローバルショートカットで表示・非表示を切り替えられる
- ショートカットを変更・保存できる
- 登録失敗時に旧ショートカットと他設定を維持できる
- ウィンドウ位置・サイズを保存し、画面内へ補正して復元できる
- 英語・日本語を切り替え、再起動後に復元できる
- 設定の `Cancel` で下書きを破棄できる

## 13.4 品質

- フォルダ変更を監視して自動再読み込みできる
- 非対応・隠し・サブフォルダ内の変更を無視できる
- サムネイル失敗やアクセスエラーでアプリが終了しない
- 古い非同期読込結果が新しいフォルダへ混入しない
- `SWIFT_STRICT_CONCURRENCY=complete` でビルド・テストが成功する
- Debug 成果物が共通 DerivedData パスへ生成される

## 13.5 自動アップデート

- 初期設定で毎週更新を自動確認でき、設定画面から毎日・毎週・毎月を選択できる
- アプリメニューから手動確認できる
- 利用者が承認した場合だけ更新をインストールして再起動する
- 改ざんされたZIP、appcast、リリースノートを拒否できる
- オフラインや更新確認失敗時も通常機能を継続利用できる
- v2.0.0から、より大きいbuild numberを持つarm64版へ更新できる

# 14. 将来候補

- サブフォルダ対応
- ファイル名検索
- サムネイルサイズ調整 UI
- ファイル名変更、通常移動
- メニューバー常駐
- ログイン時自動起動
- Security-Scoped Bookmark
- App Sandbox
- Developer ID署名とApple公証
- Sparkle差分更新
- App Store 配布
