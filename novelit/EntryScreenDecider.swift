//
//  EntryScreenDecider.swift
//  novelit
//
//  Created by 村崎聖仁 on 2026/01/25.
//

enum EntryScreen: Equatable {
    case signIn
    case verifyingAppleSignIn
    case home
}

enum AppleSignInVerification: Equatable {
    case unknown
    case authorized
    case unauthorized
}

func decideEntryScreen(
    appleUserId: String?,
    verification: AppleSignInVerification
) -> EntryScreen {
    guard appleUserId != nil else { return .signIn }

    switch verification {
    case .unknown:
        return .verifyingAppleSignIn
    case .authorized:
        return .home
    case .unauthorized:
        return .signIn
    }
}
