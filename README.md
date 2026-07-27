# FloatPeek

FloatPeek is a lightweight macOS image and PDF browser that opens with a global keyboard shortcut.

[日本語](#日本語) | [English](#english)

## 日本語

スクリーンショット保管フォルダの画像を小さく一覧表示し、手軽にアプリへ共有・コピーするために作成しました。
ショートカットでの表示・非表示切替と、アプリが常に一番手前に表示されるのが特徴。

### 主な機能

- グローバルショートカットによるウィンドウの表示・非表示
- 複数のフォルダタブの登録と切り替え
- 画像と PDF のサムネイル表示
- ファイル名、変更日、追加日による並び替え
- 単一選択、複数選択、範囲選択
- Quick Look プレビュー
- 既定アプリで開く、Finder に表示、ファイルまたはパスのコピー、ゴミ箱への移動
- 外部アプリへのドラッグ＆ドロップ
- 表示中フォルダの変更監視と自動再読み込み
- 日本語・英語表示
- ウィンドウ位置とサイズの保存

### 動作環境

- macOS 14.0 以降
- 対応形式: `jpg`、`jpeg`、`png`、`gif`、`heic`、`pdf`

対象フォルダ直下のファイルのみを表示します。サブフォルダ内のファイルは表示しません。

### インストール

Homebrew でインストールします。

```sh
brew install --cask 2zk/tap/floatpeek
```

FloatPeek は Developer ID で署名されておらず、Apple の公証も受けていません。初回起動時に macOS でブロックされた場合は、次の手順で個別に許可します。

1. `FloatPeek.app` を一度開き、表示された警告を閉じます。
2. `システム設定` の `プライバシーとセキュリティ` を開きます。
3. `セキュリティ` までスクロールし、FloatPeek の `このまま開く` をクリックします。
4. 確認画面でもう一度 `開く` をクリックします。

この操作は、ソースと配布元を確認し、FloatPeek を信頼できる場合にだけ行ってください。一度許可すると、次回からは通常どおり起動できます。

更新とアンインストールは次のコマンドで行えます。

```sh
brew upgrade --cask floatpeek
brew uninstall --cask floatpeek
```

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
| 範囲選択 | `Shift` + 矢印キー |
| Quick Look の表示・非表示 | `Space` |
| 既定アプリで開く | `Return` |
| 選択中ファイルをコピー | `⌘C` |
| 選択中ファイルをゴミ箱へ移動 | `Delete` / `Forward Delete` |
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

### リリース

リリースは `vX.Y.Z` 形式の Git タグを GitHub に push すると、GitHub Actions により自動実行されます。ワークフローは次の処理を行います。

- Apple Silicon と Intel に対応するユニバーサルアプリの Release ビルド
- Developer ID を使わない ad-hoc 署名
- `FloatPeek-X.Y.Z.zip` と SHA-256 チェックサムの GitHub Release への公開
- `2zk/homebrew-tap` の `Casks/floatpeek.rb` の更新

ad-hoc 署名は配布者の身元を証明する署名ではなく、Apple の公証も行いません。そのため、利用者は初回起動時に macOS の `プライバシーとセキュリティ` で個別に許可する必要があります。

#### 1. Homebrew Tap リポジトリを作成する

初回のみ、GitHub の Web 画面で Tap 用リポジトリを作成します。

1. GitHub 右上の `+` から `New repository` を開きます。
2. `Owner` に `2zk`、`Repository name` に `homebrew-tap` を指定します。
3. `Public` を選択します。
4. `Add a README file` を有効にし、空ではないリポジトリとして作成します。
5. `https://github.com/2zk/homebrew-tap` を開けることを確認します。

初回の自動更新を妨げないよう、準備段階では `main` ブランチに push を禁止する Ruleset や Branch protection を設定しないでください。

コマンドで作成する場合は、Homebrew と GitHub CLI を使って次のように作成できます。

```sh
brew tap-new 2zk/homebrew-tap
gh repo create 2zk/homebrew-tap \
  --public \
  --source "$(brew --repository 2zk/homebrew-tap)" \
  --push
```

#### 2. Tap 更新用の fine-grained personal access token を作成する

GitHub のプロフィール画像から `Settings` を開き、次の順に進みます。

```text
Developer settings
→ Personal access tokens
→ Fine-grained tokens
→ Generate new token
```

次のように設定します。

- `Token name`: `FloatPeek Homebrew Tap`
- `Expiration`: 運用に合う有効期限
- `Resource owner`: `2zk`
- `Repository access`: `Only select repositories`
- 選択するリポジトリ: `homebrew-tap` のみ
- `Repository permissions` の `Contents`: `Read and write`

生成後に表示される token を安全な場所へコピーします。token は再表示できません。リポジトリ、README、Issue、ログなどには記載しないでください。

#### 3. FloatPeek リポジトリへ Secret を登録する

GitHub で `2zk/FloatPeek` を開き、次の順に進みます。

```text
Settings
→ Secrets and variables
→ Actions
→ Secrets
→ New repository secret
```

次の Secret を1つだけ登録します。

| Secret | 内容 |
| --- | --- |
| `HOMEBREW_TAP_GITHUB_TOKEN` | `2zk/homebrew-tap` の Contents を読み書きできる fine-grained personal access token |

Apple の証明書、Apple Account、アプリ用パスワードに関する Secret は不要です。

#### 4. GitHub Actions を有効にする

`2zk/FloatPeek` の `Settings` から `Actions`、`General` を開きます。

- Actions が無効なら、リポジトリで Actions を実行できる設定にします。
- `Workflow permissions` で書き込みが組織やリポジトリのポリシーにより禁止されていないことを確認します。
- このワークフロー自身は `contents: write` を要求し、FloatPeek の GitHub Release を作成します。

#### 5. 最初のリリースを実行する

このリリース設定を含む変更を `main` に commit・pushした後、バージョンタグを作成して push します。

```sh
git tag v1.0.0
git push origin v1.0.0
```

コマンドの意味は、現在の commit に `v1.0.0` というバージョンの印を付け、そのタグを GitHub へ送ることです。タグを送ると `Release` ワークフローが起動します。

GitHub の `2zk/FloatPeek` で次を確認します。

1. `Actions` タブの `Release` が緑色で完了すること。
2. `Releases` に `FloatPeek-1.0.0.zip` と `.sha256` が作成されること。
3. `2zk/homebrew-tap` の `Casks/floatpeek.rb` が自動作成されること。
4. `brew install --cask 2zk/tap/floatpeek` でインストールできること。

以後はコードを commit・pushした後、`v1.0.1`、`v1.1.0` のように新しいタグを pushすると同じ処理が実行されます。一度公開したバージョンのタグや配布 ZIP は上書きせず、新しいバージョンを発行してください。

ローカルで配布 ZIP とチェックサムを確認する場合は、次を実行します。GitHub Actions と同じく ad-hoc 署名を使用し、公証は行いません。

```sh
./Scripts/build-release.sh 1.0.0
```

このコマンドは `dist/FloatPeek-1.0.0.zip` と `dist/FloatPeek-1.0.0.zip.sha256` を生成します。

### 現在の制限

- App Sandbox には対応していません。
- App Store での配布には対応していません。
- ファイルの削除、名前変更、移動、検索、画像編集には対応していません。

## English

I created this app to display a thumbnail list of images from the screenshot folder, making it easy to copy or share them with other applications.
Key features include toggling visibility via a keyboard shortcut and keeping the app window always on top.

### Features

- Show or hide the window with a global keyboard shortcut
- Register and switch between multiple folder tabs
- Display thumbnails for images and PDFs
- Sort by file name, date modified, or date added
- Single, multiple, and range selection
- Quick Look previews
- Open with the default app, reveal in Finder, copy files and paths, or move files to Trash
- Drag and drop files into other apps
- Monitor the visible folder and reload automatically when it changes
- English and Japanese interfaces
- Restore the saved window position and size

### Requirements

- macOS 14.0 or later
- Supported formats: `jpg`, `jpeg`, `png`, `gif`, `heic`, `pdf`

FloatPeek displays files directly inside the selected folder. Files in subfolders are not included.

### Installation

Install FloatPeek with Homebrew:

```sh
brew install --cask 2zk/tap/floatpeek
```

FloatPeek is ad-hoc signed and is not notarized by Apple. If macOS blocks the first launch:

1. Try to open `FloatPeek.app` once and close the warning.
2. Open `System Settings` and select `Privacy & Security`.
3. Scroll to `Security` and click `Open Anyway` for FloatPeek.
4. Click `Open` in the confirmation dialog.

Only override this security warning after checking the source and distribution origin and deciding that you trust FloatPeek. Once allowed, the app opens normally on subsequent launches.

Upgrade or uninstall it with:

```sh
brew upgrade --cask floatpeek
brew uninstall --cask floatpeek
```

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
| Extend or contract the selection range | `Shift` + Arrow keys |
| Show or hide Quick Look | `Space` |
| Open with the default app | `Return` |
| Copy selected files | `⌘C` |
| Move selected files to Trash | `Delete` / `Forward Delete` |
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

### Releasing

Pushing a Git tag in the `vX.Y.Z` format starts the release workflow. GitHub Actions builds a universal app for Apple Silicon and Intel, applies an ad-hoc signature without Apple notarization, publishes the ZIP and its SHA-256 checksum to GitHub Releases, and updates `Casks/floatpeek.rb` in `2zk/homebrew-tap`.

An ad-hoc signature does not verify the publisher's identity. Users must explicitly allow the first launch in macOS Privacy & Security.

#### 1. Create the Homebrew tap repository

For the initial setup, create a non-empty public GitHub repository named `2zk/homebrew-tap`:

1. Open `New repository` from the `+` menu on GitHub.
2. Set `Owner` to `2zk` and `Repository name` to `homebrew-tap`.
3. Select `Public`.
4. Enable `Add a README file` and create the repository.
5. Confirm that `https://github.com/2zk/homebrew-tap` is available.

Do not initially add a ruleset or branch protection that prevents the workflow from pushing to `main`.

Alternatively, create it with Homebrew and GitHub CLI:

```sh
brew tap-new 2zk/homebrew-tap
gh repo create 2zk/homebrew-tap \
  --public \
  --source "$(brew --repository 2zk/homebrew-tap)" \
  --push
```

#### 2. Create a fine-grained personal access token

Open your GitHub profile `Settings`, then go to `Developer settings`, `Personal access tokens`, `Fine-grained tokens`, and `Generate new token`.

- Set `Resource owner` to `2zk`.
- Select only the `homebrew-tap` repository.
- Grant `Contents: Read and write` repository permission.
- Copy the generated token and keep it private.

#### 3. Add the repository Secret

In `2zk/FloatPeek`, open `Settings`, `Secrets and variables`, `Actions`, `Secrets`, and `New repository secret`. Add only the following Secret:

| Secret | Value |
| --- | --- |
| `HOMEBREW_TAP_GITHUB_TOKEN` | Fine-grained personal access token with read/write Contents access to `2zk/homebrew-tap` |

No Apple certificate or account Secrets are required.

#### 4. Enable GitHub Actions

In `2zk/FloatPeek`, open `Settings`, `Actions`, and `General`. Ensure Actions are enabled and repository or organization policy does not prevent the workflow's requested `contents: write` permission.

#### 5. Publish the first release

Commit and push the release configuration to `main`, then create and push a version tag:

```sh
git tag v1.0.0
git push origin v1.0.0
```

Check that the `Release` workflow succeeds, the ZIP and checksum appear under FloatPeek Releases, and `Casks/floatpeek.rb` appears in `2zk/homebrew-tap`. For later releases, push a new tag such as `v1.0.1`; do not overwrite an already published tag or ZIP.

To build the same ad-hoc signed, unnotarized release ZIP and checksum locally, run:

```sh
./Scripts/build-release.sh 1.0.0
```

The command creates `dist/FloatPeek-1.0.0.zip` and `dist/FloatPeek-1.0.0.zip.sha256`.

### Current limitations

- App Sandbox is not supported.
- App Store distribution is not supported.
- File deletion, renaming, moving, search, and image editing are not supported.
