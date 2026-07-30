# FloatPeek project instructions

## Release authorization

- ユーザーが現在の依頼で「リリースして」「公開して」または同等の指示を明示した場合、その依頼はFloatPeekのリリース完了までに必要な通常操作を一括で許可するものとして扱う。
- 上記の許可には、リリース関連ファイルの最小修正、テスト、lint、ビルド、git commit、`origin/main`へのgit push、SemVerタグの作成とpush、GitHub Actionsの実行・再実行・監視、GitHub Releaseの作成・公開、既存WorkflowによるHomebrew Tap更新を含む。各操作の直前に同じ確認を繰り返さない。
- ユーザーがバージョンを指定した場合はそのバージョンを使用する。指定がない場合は、公開済みReleaseとリモートタグを確認し、未使用の次のpatchバージョンを採用して、タグ作成前にユーザーへ通知する。
- リリース中に失敗した場合はログを調査し、リリース処理に必要な最小修正を行い、検証、commit、push、再リリースまで継続する。
- push済みタグは移動・上書き・削除しない。失敗したタグがある場合は、修正をmainで検証した後、未使用の次のpatchバージョンを使用する。
- 作業ツリーに依頼と無関係な変更がある場合は保護し、重なる変更を避けられない場合だけユーザーへ確認する。

## Release safety boundaries

- 明示的なリリース依頼がない状態では、タグ作成、push、GitHub Release公開、Homebrew Tap更新を行わない。
- force-push、既存のリモートタグや公開済みRelease／アセットの削除、履歴の書き換えは、個別の明示的な許可なしに行わない。
- GitHub Secrets、署名鍵、トークン、認証情報の値を読み取る、表示する、生成する、変更する操作は行わない。存在確認だけで足りない場合はユーザーへ確認する。
- リリースに不要な製品仕様やユーザーデータへ変更を広げない。通常の不具合修正を伴う場合は、その内容をユーザーへ説明する。
- sandbox、GitHub、macOSなど実行環境が要求する承認や権限は、このファイルでは無効化できない。必要な承認は実行時に要求する。

## Release workflow

- FloatPeekの公開作業では `.agents/skills/floatpeek-release/SKILL.md` を読み、その順序と検証基準に従う。
