//
//  Untitled.swift
//  novelit
//
//  Created by 村崎聖仁 on 2026/01/24.
//

import Testing
@testable import novelit

struct EntryScreenDeciderTests {
    @Test("未ログイン（userIdなし）は常に.signIn")
    func signedOutAlwaysGoesToSignIn() {
        #expect(decideEntryScreen(appleUserId: nil, verification: .unknown) == .signIn)
        #expect(decideEntryScreen(appleUserId: nil, verification: .authorized) == .signIn)
        #expect(decideEntryScreen(appleUserId: nil, verification: .unauthorized) == .signIn)
    }
    
    @Test("ログイン済み（userIdあり） + 未確認は.verifyingAppleSignIn")
    func signedInUnknownGoesToVerifyingAppleSignIn() {
        #expect(decideEntryScreen(appleUserId: "u1", verification: .unknown) == .verifyingAppleSignIn)
    }
    
    @Test("ログイン済み（userIdあり） + authorizedは.home")
    func signedInAuthorizedGoesToHome() {
        #expect(decideEntryScreen(appleUserId: "u1", verification: .authorized) == .home)
    }
    
    @Test("ログイン済み（userIdあり） + unauthorizedは安全側で.signIn")
    func signedInUnauthorizedGoesToSignIn() {
        #expect(decideEntryScreen(appleUserId: "u1", verification: .unauthorized) == .signIn)
    }
}
