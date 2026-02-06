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
}

struct novelitTests {

    @Test("ダミーテスト（雛形）")
    func example() async throws {
        #expect(true)
    }

}
