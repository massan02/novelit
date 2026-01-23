# TDD（Swift Testing）進め方メモ

このリポジトリは `SwiftUI + SwiftData + Swift Testing` を前提にする。UIは後回しにして、まず「仕様を満たす最小のロジック」をテストから固める（TDD）。

## 参照（公式）
- Apple Developer Documentation（Swift Testing）: https://developer.apple.com/documentation/testing
- Swift Testing（公式リポジトリ）: https://github.com/swiftlang/swift-testing

## Swift Testingの最低限
- テストターゲットで `import Testing`
- テストは `@Test` を付けた関数（`async` / `throws` 可）
- 期待値は `#expect(条件式)`（失敗時に評価値を出してくれる）

例:
```swift
import Testing

@Test func sample() {
  #expect(1 + 1 == 2)
}
```

## このリポジトリでのTDD手順（おすすめ）
1. 仕様を「Given/When/Then」で分解（例: iCloud未サインイン→利用不可）
2. “落ちるテスト” を先に書く（Red）
3. テストが通る最小実装を書く（Green）
4. リファクタ（Refactor）。UIは最後に繋ぐ

ポイント:
- `CloudKit` / `AuthenticationServices` の呼び出しは直接テストしない（遅い/不安定になりがち）。プロトコル越しに注入してFakeでテストする。
- SwiftUIのViewは「描画」が主なので、基本はロジック（UseCase/Session/Repository）に寄せてテストを書く。

## 実行コマンド（例）
- Xcodeで `⌘U`
- CLI: `xcodebuild -project novelit.xcodeproj -scheme novelit -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' test`

