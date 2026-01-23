# CloudKit データ設計（案）

## 目的
- 「論理はスナップショット、物理は最適化」をCloudKit上で成立させる
- 作品/ファイル/スナップショット/コンテンツを分離して、重複排除と復元をやりやすくする

## 用語（まずここだけ）
- `Content`: 本文などの“実体データ”（圧縮したテキスト本体）。同じ内容は使い回したいので、ハッシュで一意化する。
- `File`: 作品内にあるファイルの概念（例: 本文/アウトライン/プロット/キャラクター/情報）。「最新の内容」がどの`Content`かを指す。
- `Snapshot`: 確定保存（コミット相当）。その時点での「各ファイルがどの内容だったか」を固定して残す。
- `manifest`: Snapshotの中身を表す“目次/インデックス”。「このスナップショットでは、本文はこのContent、アウトラインはこのContent…」という対応表。

`manifest`の例（イメージ）
```json
{
  "本文": "abc...",
  "アウトライン": "def...",
  "プロット": "123..."
}
```
※ 値は `Content.contentHash`（SHA-256のhex文字列）を入れる。

## CloudKitの基本部品（CKAsset以外も含む）
CloudKitはざっくり「レコード（小さめの構造化データ）」と「アセット（大きめのファイル）」を組み合わせて保存する。

### CKRecord（レコード）
- 例: `Work` / `File` / `Content` / `Snapshot` のような“表”の1行に近いもの。
- レコードには「フィールド」を持てる（文字列や日時など）。

よく使うフィールド型（例）
- `String`（文字列）
- `Int` / `Double` / `Bool`（数値/真偽）
- `Date`（日時）
- `Data`（小さなバイナリ。入れすぎ注意）
- `CKAsset`（大きいデータはこれ）
- `CKReference`（他レコードへの参照。リレーション）
- 配列（上記の配列。使いすぎ注意）

### CKAsset（アセット）
- “ファイル”としてCloudKitに保存するための仕組み。
- 本文などのサイズが大きくなりやすいデータは、レコードのフィールドに直接入れず、`CKAsset`に逃がすのが基本。
- 例: 圧縮した本文をファイル化して `Content.blob` に入れる。

### CKReference（参照）
- レコード同士をつなぐためのリンク。
- 例: `File.latestContentRef` が `Content` を指す、`Snapshot.workRef` が `Work` を指す。

### そのほか（雰囲気だけ）
- `CKDatabase`（保存先DB）: private/public/shared がある（個人データは基本private）。
- `CKQuery`（検索）: 条件でレコードを取得する。
- `CKSubscription`（変更通知）: 更新を購読する（必要になってから検討でOK）。

## CloudKitは「MySQLのカラム型」と何が違う？
- どちらも「型付きのフィールド」に保存する点は同じ。
- 違いは、CloudKitは“レコード中心”で、巨大な本文などは `CKAsset`（ファイル）として分けて持つのが基本、という点。
- もう1つの違いは「データの持ち方がリレーションSQLより緩い」こと。
  - 参照（`CKReference`）はあるが、JOINで複雑に結合して集計する用途には向かない。
  - 作品アプリのような「一覧→詳細→復元」中心のデータには合わせやすい。

## 重要な前提
- CloudKitはレコードにサイズ制限があるため、本文などの大きいデータは `CKAsset`（ファイル）として保存する前提。
- 同期は「入力＋遅延」で頻繁に発生するため、書き込み回数と容量が増えやすい。まずは圧縮＋重複排除を優先する。
- 使うDB: `private`（ユーザーごとの個人データ。public/sharedはMVPでは使わない）

## レコードタイプ（案）

### `Work`（作品）
- `workId`（UUID文字列）
- `title`（作品名）
- `createdAt`
- `updatedAt`

### `File`（作品内ファイルの“最新”）
- `workRef`（`Work`へのReference）
- `name`（例: `本文`, `アウトライン`, `プロット`）
- `latestContentRef`（`Content`へのReference）
- `updatedAt`

### `Content`（実体＝本文などの内容）
- `contentHash`（例: `e3b0...`。SHA-256のlowercase hex（64文字）。重複排除キー）
- `compression`（`gzip`で固定）
- `rawByteCount`
- `compressedByteCount`
- `blob`（`CKAsset`。圧縮済みデータ）
- `createdAt`

補足:
- 「ContentはText型」ではなく、`CKRecord`（`Content`）の中に `CKAsset`（`blob`）として本文を置くイメージ。
- 短いテキストなら `String` フィールドでも保存できるが、本文/履歴は大きくなりやすいので `CKAsset` 前提にする。

### `Snapshot`（確定保存＝コミット相当）
- `workRef`（`Work`へのReference）
- `title`（スナップショット名）
- `memo`
- `createdAt`
- `deviceName`
- `kind`（例: `manual`, `conflict`）
- `manifest`（圧縮JSONの `CKAsset`。`fileName -> contentHash` の対応表）（採用）

補足:
- 「Snapshotはどういう型？」→ `CKRecord`（`Snapshot`）で、各フィールドは `String` / `Date` / `CKReference` / `CKAsset` を組み合わせる。
  - 例: `title`は`String`、`createdAt`は`Date`、`workRef`は`CKReference`、`manifest`は`CKAsset`。

## 保存・復元の考え方（案）
- 「最新状態」＝ `File.latestContentRef` の参照先を読む
- 「スナップショット」＝ `Snapshot.manifest` を読み、必要な `Content` を集めて復元する
- 同じ内容は `Content` を使い回す（重複排除）

## 全体の流れ（どう動くか）
### 1) 編集（入力＋遅延）で「最新」を更新
1. ユーザーが編集する
2. ローカルに即保存（アプリが落ちても復元できる）
3. デバウンス後に同期処理:
   - テキストを圧縮 → `contentHash` を計算
   - その `contentHash` の `Content` が既にあれば再利用、なければ `Content` を作る（`blob`に`CKAsset`）
   - `File.latestContentRef` をその `Content` に更新する（これが「最新」）

### 2) 確定保存（スナップショット）を作る
1. ユーザーが「確定保存」を押す
2. 現時点の各 `File.latestContentRef` を集める
3. `manifest`（`fileName -> contentHash` の対応表）を作り、圧縮して `CKAsset` として保存
4. `Snapshot` レコードを作り、メタ情報（タイトル/メモ/日時/端末名）と `manifest` を紐づける

### 3) 復元する
1. 復元したい `Snapshot` を選ぶ
2. `manifest` を読み、必要な `Content` を集める
3. `File.latestContentRef` を `manifest` の内容に更新する（＝最新がその版になる）

### 4) 競合（LWW＋コピー）時
- 保存時にサーバー側と矛盾が出た場合、LWWで「勝つ内容」を最新にしつつ、
  負けた内容は `Snapshot.kind=conflict` で必ず残す（内容が消えない）。

## 決めたこと（MVP）
- 圧縮: `gzip`
- ハッシュ: `SHA-256`（`contentHash`としてlowercase hex（64文字）で保存）
- `manifest`: 圧縮JSONを `CKAsset` として保存
- DB: `private`

## 競合（LWW＋コピー）との関係
- 競合で負けた内容は `Snapshot.kind=conflict` として `Snapshot` を作る。
- その後、最新状態はLWWで更新し続ける（「内容が消えない」ことが優先）。

## 未決定
- なし（MVPでは `manifest` は圧縮JSON（`CKAsset`）で確定）
