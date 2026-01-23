# Repository Guidelines

## プロジェクト概要
- Repo: `novelit`（小説執筆アプリ）
- 目的: スマホで「Gitっぽい試行錯誤」を可能にする（確定保存＝スナップショット、履歴、復元。ブランチ/マージは後）
- ターゲット: iOS（SwiftUI + SwiftData + Swift Testing）

## プロジェクト構成
- `novelit/`: アプリ本体（SwiftUIビュー、ドメイン/ユースケース、データ層）
- `novelitTests/`: Swift Testing のユニットテスト
- `novelitUITests/`: UIテスト（最小限のスモーク）
- `novelit.xcodeproj/`: Xcodeプロジェクト設定（Xcodeで管理）

## ビルド・テスト・開発コマンド
- `open novelit.xcodeproj`: Xcodeで起動して実行/デバッグ
- `xcodebuild -project novelit.xcodeproj -scheme novelit -destination 'platform=iOS Simulator,name=iPhone 17' build`: CLIビルド（端末名は環境に合わせて変更）
- `xcodebuild -project novelit.xcodeproj -scheme novelit -destination 'platform=iOS Simulator,name=iPhone 17' test`: テスト実行

## コーディングスタイルと命名
- インデントは4スペース、Swift API Design Guidelinesに準拠
- 型名は`UpperCamelCase`、関数/変数は`lowerCamelCase`
- SwiftUIビューは`struct` + `View`準拠、`body`を定義

## テスト指針（TDD）
- 開発は原則TDD（Red→Green→Refactor）。仕様は先にテストで固定してから実装する
- テストはSwift Testingを使用（`import Testing` / `@Test` / `#expect(...)`）
- UIテストは最低1本の起動スモークを維持

## コミット/PRガイド
- `main`は常にビルドが通る状態を維持し、小さな変更単位でコミット
- AIは作業終了時に勝手にコミットしない（コミット直前で停止して指示を仰ぐ）
- PRには概要、テスト結果、UI変更時のスクリーンショットを添付

## Xcode運用ルール
- AIが編集してよい: `.swift` / `.md` / 画像やJSON等のテキスト資産
- AIが編集しない: `.xcodeproj`（特に`project.pbxproj`）、署名/Capability/Build Settings関連
- 新規ファイル追加・ターゲット設定・Signing変更はXcode上で手動（AIは手順提案とパッチ作成まで）

## コミュニケーション
- 本リポジトリに関する回答・説明は日本語で行う
