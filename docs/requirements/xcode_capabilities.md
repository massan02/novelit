# Xcode設定（手動）: Sign in with Apple / iCloud(CloudKit)

このリポジトリでは `.xcodeproj` を手編集しない方針のため、Capabilityの有効化はXcode上で行う。

## 1) Sign in with Apple を有効化
1. Xcodeで `novelit.xcodeproj` を開く
2. `TARGETS` → `novelit` → `Signing & Capabilities`
3. `+ Capability` → `Sign In with Apple` を追加

## 2) iCloud / CloudKit を有効化
1. `TARGETS` → `novelit` → `Signing & Capabilities`
2. `+ Capability` → `iCloud` を追加
3. `Services` で `CloudKit` をON
4. `Containers` でコンテナを作成/選択

## 3) 想定する挙動（MVP）
- 端末がiCloud未サインイン: アプリ利用不可（設定へ誘導）
- iCloud/CloudKitが無効（端末はiCloudサインイン済み）: ローカル限定で動作
