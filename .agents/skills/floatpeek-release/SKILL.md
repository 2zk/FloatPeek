---
name: floatpeek-release
description: FloatPeekのリリース前検証、git pushとSemVerタグ作成、GitHub Actions監視、GitHub Release公開、Homebrew Cask更新、失敗したリリースの復旧を一貫して実行する。FloatPeekをリリース・公開・配布するとき、バージョンタグを作るとき、Release WorkflowやHomebrew更新の失敗を解決して公開まで継続するときに使用する。
---

# FloatPeek Release

## 基本方針

- リポジトリルートの `AGENTS.md` にあるリリース許可と安全境界を最初に確認する。
- ユーザーが明示したリリース依頼を受けた後は、検証、公開、Homebrew更新、最終確認まで継続する。
- 秘密情報の値を表示しない。GitHub SecretsはWorkflow内で存在だけを検証する。
- push済みタグを移動・削除しない。失敗後は修正済みmainから未使用の次のpatchバージョンをリリースする。

## 1. リリース状態を確認する

- `git status --short --branch` で作業ツリーとブランチを確認する。
- `git log`、リモートタグ、最新のGitHub Releaseを確認する。
- ユーザー指定のバージョンがなければ、公開済みReleaseとリモートタグの両方より新しい、未使用の次のpatchバージョンを選ぶ。
- `gh auth status` でGitHub CLIが対象アカウントへ接続できることを確認する。認証情報そのものは表示しない。
- 依頼と無関係な変更をステージ、commit、破棄しない。

## 2. タグ作成前に検証する

変更に近いテストから始め、タグ作成前に次をすべて成功させる。

```bash
shellcheck -x Scripts/*.sh
for script_path in Scripts/*.sh; do
  bash -n "$script_path"
done
xcodebuild test \
  -project FloatPeek.xcodeproj \
  -scheme FloatPeek \
  -destination "platform=macOS" \
  -derivedDataPath .build/DerivedData
./Scripts/validate-release-pipeline.sh
```

- 失敗を放置してタグを作らない。
- リリース処理の修正が必要なら、差分を最小化して同じ検証を再実行する。
- 検証用の使い捨て鍵だけをローカル生成する。本番のEdDSA秘密鍵へ触れない。

## 3. mainを確定する

- リリースに必要な変更だけを論理単位でcommitする。
- commitメッセージを日本語で記述する。
- `origin/main`へpushする。
- pushで開始した `CI` Workflowを特定し、全ジョブが成功するまで監視する。
- CIが失敗した場合はタグを作らず、`gh run view <run-id> --log-failed` で原因を確認して修正する。

## 4. バージョンタグを公開する

- CI成功済みのmainコミットへ `vX.Y.Z` 形式の軽量タグを作成する。
- ローカルとリモートに同名タグが存在しないことを確認する。
- タグを `origin` へpushし、`Release` Workflowを開始する。
- `validate`、`publish`、`update-homebrew` の3ジョブを最後まで監視する。

## 5. 失敗から復旧する

- `gh run view <run-id> --log-failed` で失敗ステップだけを取得する。
- 原因がWorkflowやリリーススクリプトにある場合は、mainへ最小修正を行い、手順2から再実行する。
- タグが既にpush済みなら、そのタグを動かさない。未使用の次のpatchバージョンを採用する。
- GitHub Releaseがドラフトで残った場合は、同じタグの再実行で安全に再利用できるかWorkflowの実装を確認する。公開済みReleaseは上書きしない。
- Secrets不足、権限不足、署名鍵不整合など、値や権限の変更が必要な場合だけユーザーへ具体的な対応を依頼する。

## 6. 公開結果を検証する

次を確認してから完了を報告する。

- Release Workflowの3ジョブが成功している。
- GitHub Releaseがドラフトでもprereleaseでもなく公開済みである。
- `FloatPeek-X.Y.Z.zip`、SHA-256、リリースノート、`appcast.xml` の4アセットが存在する。
- Homebrew Tapの `Casks/floatpeek.rb` が対象バージョン、公開ZIPのSHA-256、`depends_on arch: :arm64`、`auto_updates true` を含む。
- `https://github.com/2zk/FloatPeek/releases/latest/download/appcast.xml` が新しいReleaseを指す。
- ローカルmain、`origin/main`、公開タグが同じコミットを指し、作業ツリーに未処理差分がない。

## 完了報告

- 公開バージョン、Release URL、Workflow URL、Homebrew反映結果を示す。
- 実行した主要検証と結果を簡潔に示す。
- 無関係な警告がある場合は、リリースへの影響有無を説明する。
- pushや公開を実施していない場合は、その理由と残作業を明記する。
