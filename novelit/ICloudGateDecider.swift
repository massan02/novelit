//
//  ICloudGateDecider.swift
//  novelit
//
//  Created by Codex on 2026/02/07.
//

import CloudKit

enum ICloudAccountStatus: Equatable {
    case available
    case noAccount
    case restricted
    case canNotDetermine
    case temporarilyUnavailable
}

protocol ICloudAccountStatusProviding: Sendable {
    func currentStatus() async -> ICloudAccountStatus
}

struct CloudKitICloudAccountStatusProvider: ICloudAccountStatusProviding {
    func currentStatus() async -> ICloudAccountStatus {
        await withCheckedContinuation { continuation in
            CKContainer.default().accountStatus { status, _ in
                continuation.resume(returning: mapCloudKitStatus(status))
            }
        }
    }
}

enum HomeSyncState: Equatable {
    case syncEnabled
    case requiresICloudSignIn
    case localOnlyBanner
}

enum HomeDestination: Equatable {
    case blockedByICloudSignIn
    case home
}

enum HomeSyncStatusRowState: Equatable {
    case hidden
    case checkingLocalOnly
    case localOnly
}

func decideHomeSyncState(accountStatus: ICloudAccountStatus) -> HomeSyncState {
    switch accountStatus {
    case .available:
        return .syncEnabled
    case .noAccount:
        return .requiresICloudSignIn
    case .restricted, .canNotDetermine, .temporarilyUnavailable:
        return .localOnlyBanner
    }
}

func decideHomeDestination(syncState: HomeSyncState) -> HomeDestination {
    switch syncState {
    case .syncEnabled:
        return .home
    case .requiresICloudSignIn:
        return .blockedByICloudSignIn
    case .localOnlyBanner:
        return .home
    }
}

func decideHomeSyncStatusRowState(
    syncState: HomeSyncState,
    isCheckingICloudStatus: Bool
) -> HomeSyncStatusRowState {
    if isCheckingICloudStatus {
        return .checkingLocalOnly
    }

    switch syncState {
    case .syncEnabled, .requiresICloudSignIn:
        return .hidden
    case .localOnlyBanner:
        return .localOnly
    }
}

private func mapCloudKitStatus(_ status: CKAccountStatus) -> ICloudAccountStatus {
    switch status {
    case .available:
        return .available
    case .noAccount:
        return .noAccount
    case .restricted:
        return .restricted
    case .couldNotDetermine:
        return .canNotDetermine
    case .temporarilyUnavailable:
        return .temporarilyUnavailable
    @unknown default:
        return .canNotDetermine
    }
}
