//
//  novelitTests.swift
//  novelitTests
//
//  Created by 村崎聖仁 on 2026/01/23.
//

import Testing
@testable import novelit

actor ControlledAppleSignInVerifier: AppleSignInVerifying {
    private(set) var verifyCallCount: Int = 0
    private(set) var lastUserId: String?

    private var continuation: CheckedContinuation<AppleSignInVerification, Never>?

    func verify(appleUserId: String) async -> AppleSignInVerification {
        verifyCallCount += 1
        lastUserId = appleUserId
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resolve(_ result: AppleSignInVerification) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

struct RootViewModelTests {
    @Test("未ログイン（userIdなし）は.signInで、検証も走らない")
    func signedOutShowsSignInAndDoesNotVerify() async {
        let verifier = ControlledAppleSignInVerifier()
        let viewModel = await RootViewModel(verifier: verifier)

        await viewModel.setAppleUserId(nil)

        let screen = await viewModel.entryScreen
        #expect(screen == .signIn)

        let callCount = await verifier.verifyCallCount
        #expect(callCount == 0)
    }

    @Test("ログイン済み（userIdあり）はまず.verifyingAppleSignInになり、authorizedで.homeへ遷移する")
    func signedInBecomesVerifyingThenHomeOnAuthorized() async {
        let verifier = ControlledAppleSignInVerifier()
        let viewModel = await RootViewModel(verifier: verifier)

        await viewModel.setAppleUserId("u1")

        let initialScreen = await viewModel.entryScreen
        #expect(initialScreen == .verifyingAppleSignIn)

        let lastUserId = await verifier.lastUserId
        #expect(lastUserId == "u1")

        await verifier.resolve(.authorized)
        await Task.yield()

        let finalScreen = await viewModel.entryScreen
        #expect(finalScreen == .home)
    }

    @Test("ログイン済み（userIdあり）はunauthorizedで.signInへ戻す（安全側）")
    func signedInBecomesSignInOnUnauthorized() async {
        let verifier = ControlledAppleSignInVerifier()
        let viewModel = await RootViewModel(verifier: verifier)

        await viewModel.setAppleUserId("u1")
        await verifier.resolve(.unauthorized)
        await Task.yield()

        let finalScreen = await viewModel.entryScreen
        #expect(finalScreen == .signIn)
    }
}

struct AppleUserSessionReducerTests {
    @Test("サインイン成功でappleUserIdを保存し、エラー表示をクリアする")
    func signInSuccessStoresAppleUserId() {
        let state = AppleUserSessionState(
            storedAppleUserId: "",
            signInErrorMessage: AppleUserSessionState.signInFailedMessage
        )

        let reduced = reduceAppleUserSession(
            state: state,
            action: .signInSucceeded(appleUserId: "apple-user-1")
        )

        #expect(reduced.storedAppleUserId == "apple-user-1")
        #expect(reduced.signInErrorMessage == nil)
    }

    @Test("サインイン失敗ではappleUserIdを保存しない（既存値を維持）")
    func signInFailureDoesNotSaveAppleUserId() {
        let state = AppleUserSessionState(
            storedAppleUserId: "",
            signInErrorMessage: nil
        )

        let reduced = reduceAppleUserSession(
            state: state,
            action: .signInFailed
        )

        #expect(reduced.storedAppleUserId == "")
        #expect(reduced.signInErrorMessage == AppleUserSessionState.signInFailedMessage)
    }

    @Test("ログアウトでappleUserIdを削除する")
    func signOutClearsAppleUserId() {
        let state = AppleUserSessionState(
            storedAppleUserId: "apple-user-1",
            signInErrorMessage: nil
        )

        let reduced = reduceAppleUserSession(
            state: state,
            action: .signOut
        )

        #expect(reduced.storedAppleUserId == "")
        #expect(reduced.signInErrorMessage == nil)
    }

    @Test("同一appleUserIdで再サインインしたとき再検証用revisionを進める")
    func signInSuccessWithSameUserIdIncrementsRevision() {
        let state = AppleUserSessionState(
            storedAppleUserId: "apple-user-1",
            signInErrorMessage: nil,
            verificationRevision: 3
        )

        let reduced = reduceAppleUserSession(
            state: state,
            action: .signInSucceeded(appleUserId: "apple-user-1")
        )

        #expect(reduced.storedAppleUserId == "apple-user-1")
        #expect(reduced.verificationRevision == 4)
    }
}

struct RootViewTaskIDTests {
    @Test("同一appleUserIdでもrevisionが変わればtask idが変わる")
    func taskIDChangesWhenRevisionChanges() {
        let first = makeRootTaskID(storedAppleUserId: "apple-user-1", verificationRevision: 1)
        let second = makeRootTaskID(storedAppleUserId: "apple-user-1", verificationRevision: 2)

        #expect(first != second)
    }
}

struct ICloudGateDeciderTests {
    @Test("iCloud accountStatusがavailableなら同期有効でホーム表示")
    func availableEnablesSyncOnHome() {
        let state = decideHomeSyncState(accountStatus: .available)
        #expect(state == .syncEnabled)
    }

    @Test("iCloud accountStatusがnoAccountならiCloud必須導線を表示")
    func noAccountRequiresICloudSignIn() {
        let state = decideHomeSyncState(accountStatus: .noAccount)
        #expect(state == .requiresICloudSignIn)
    }

    @Test("iCloud accountStatusがrestrictedならホーム表示は許可しつつローカル限定バナー")
    func restrictedShowsLocalOnlyBanner() {
        let state = decideHomeSyncState(accountStatus: .restricted)
        #expect(state == .localOnlyBanner)
    }

    @Test("iCloud accountStatusがcanNotDetermineならホーム表示は許可しつつローカル限定バナー")
    func canNotDetermineShowsLocalOnlyBanner() {
        let state = decideHomeSyncState(accountStatus: .canNotDetermine)
        #expect(state == .localOnlyBanner)
    }

    @Test("iCloud accountStatusがtemporarilyUnavailableならホーム表示は許可しつつローカル限定バナー")
    func temporarilyUnavailableShowsLocalOnlyBanner() {
        let state = decideHomeSyncState(accountStatus: .temporarilyUnavailable)
        #expect(state == .localOnlyBanner)
    }
}

struct HomeDestinationDeciderTests {
    @Test("syncEnabledならホームを表示する")
    func syncEnabledGoesHome() {
        let destination = decideHomeDestination(syncState: .syncEnabled)
        #expect(destination == .home)
    }

    @Test("localOnlyBannerならホームを表示する")
    func localOnlyBannerGoesHome() {
        let destination = decideHomeDestination(syncState: .localOnlyBanner)
        #expect(destination == .home)
    }

    @Test("requiresICloudSignInならホームへ遷移せず、iCloudサインイン必須画面を表示する")
    func requiresICloudSignInGoesBlockedScreen() {
        let destination = decideHomeDestination(syncState: .requiresICloudSignIn)
        #expect(destination == .blockedByICloudSignIn)
    }
}

struct HomeSyncStatusRowStateTests {
    @Test("iCloud確認中はホームを触れるように、ローカル限定 + 進捗行を表示する")
    func checkingAlwaysShowsCheckingLocalOnly() {
        let state = decideHomeSyncStatusRowState(
            syncState: .syncEnabled,
            isCheckingICloudStatus: true
        )
        #expect(state == .checkingLocalOnly)
    }

    @Test("同期有効かつ確認完了なら進捗行もローカル限定行も非表示")
    func syncEnabledHidesStatusRow() {
        let state = decideHomeSyncStatusRowState(
            syncState: .syncEnabled,
            isCheckingICloudStatus: false
        )
        #expect(state == .hidden)
    }

    @Test("ローカル限定かつ確認完了ならローカル限定行を表示")
    func localOnlyShowsLocalOnlyRow() {
        let state = decideHomeSyncStatusRowState(
            syncState: .localOnlyBanner,
            isCheckingICloudStatus: false
        )
        #expect(state == .localOnly)
    }
}

struct novelitTests {

    @Test("ダミーテスト（雛形）")
    func example() async throws {
        #expect(true)
    }

}
