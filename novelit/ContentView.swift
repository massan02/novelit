//
//  ContentView.swift
//  novelit
//
//  Created by 村崎聖仁 on 2026/01/23.
//

import AuthenticationServices
import Combine
import SwiftUI
import SwiftData

protocol AppleSignInVerifying {
    func verify(appleUserId: String) async -> AppleSignInVerification
}

struct AppleIDCredentialStateVerifier: AppleSignInVerifying {
    func verify(appleUserId: String) async -> AppleSignInVerification {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: appleUserId) { credentialState, _ in
                switch credentialState {
                case .authorized:
                    continuation.resume(returning: .authorized)
                case .revoked, .notFound, .transferred:
                    continuation.resume(returning: .unauthorized)
                @unknown default:
                    continuation.resume(returning: .unauthorized)
                }
            }
        }
    }
}

enum AppleUserSessionAction: Equatable {
    case signInSucceeded(appleUserId: String)
    case signInFailed
    case signOut
}

struct AppleUserSessionState: Equatable {
    static let signInFailedMessage = "サインインに失敗しました"

    var storedAppleUserId: String
    var signInErrorMessage: String?
    var verificationRevision: Int = 0
}

func reduceAppleUserSession(
    state: AppleUserSessionState,
    action: AppleUserSessionAction
) -> AppleUserSessionState {
    switch action {
    case .signInSucceeded(let appleUserId):
        return AppleUserSessionState(
            storedAppleUserId: appleUserId,
            signInErrorMessage: nil,
            verificationRevision: state.verificationRevision + 1
        )
    case .signInFailed:
        return AppleUserSessionState(
            storedAppleUserId: state.storedAppleUserId,
            signInErrorMessage: AppleUserSessionState.signInFailedMessage,
            verificationRevision: state.verificationRevision
        )
    case .signOut:
        return AppleUserSessionState(
            storedAppleUserId: "",
            signInErrorMessage: nil,
            verificationRevision: state.verificationRevision
        )
    }
}

struct RootTaskID: Equatable, Hashable {
    let storedAppleUserId: String
    let verificationRevision: Int
}

func makeRootTaskID(storedAppleUserId: String, verificationRevision: Int) -> RootTaskID {
    RootTaskID(
        storedAppleUserId: storedAppleUserId,
        verificationRevision: verificationRevision
    )
}

@MainActor
final class RootViewModel: ObservableObject {
    nonisolated let objectWillChange = ObservableObjectPublisher()

    @Published private(set) var appleUserId: String?
    @Published private(set) var verification: AppleSignInVerification = .unknown

    private let verifier: AppleSignInVerifying
    private var verificationTask: Task<Void, Never>?

    init(verifier: AppleSignInVerifying) {
        self.verifier = verifier
    }

    var entryScreen: EntryScreen {
        decideEntryScreen(appleUserId: appleUserId, verification: verification)
    }

    func setAppleUserId(_ appleUserId: String?) {
        guard self.appleUserId != appleUserId else { return }

        self.appleUserId = appleUserId
        verificationTask?.cancel()

        guard let appleUserId else {
            verification = .unknown
            return
        }

        verification = .unknown
        verificationTask = Task { [weak self, verifier] in
            let result = await verifier.verify(appleUserId: appleUserId)
            guard let self, !Task.isCancelled else { return }
            self.verification = result
        }
    }
}

struct RootView: View {
    @AppStorage("appleUserId") private var storedAppleUserId: String = ""
    @AppStorage("appleUserIdVerificationRevision") private var verificationRevision: Int = 0
    @StateObject private var viewModel: RootViewModel

    init(verifier: AppleSignInVerifying = AppleIDCredentialStateVerifier()) {
        _viewModel = StateObject(wrappedValue: RootViewModel(verifier: verifier))
    }

    var body: some View {
        Group {
            switch viewModel.entryScreen {
            case .signIn:
                SignInView(
                    storedAppleUserId: $storedAppleUserId,
                    verificationRevision: $verificationRevision
                )
            case .verifyingAppleSignIn:
                VerifyingAppleSignInView()
            case .home:
                ContentView(storedAppleUserId: $storedAppleUserId)
            }
        }
        .task(id: makeRootTaskID(
            storedAppleUserId: storedAppleUserId,
            verificationRevision: verificationRevision
        )) {
            let appleUserIdOrNil: String? = storedAppleUserId.isEmpty ? nil : storedAppleUserId
            await viewModel.setAppleUserId(appleUserIdOrNil)
        }
    }
}

struct SignInView: View {
    @Binding var storedAppleUserId: String
    @Binding var verificationRevision: Int
    @State private var signInErrorMessage: String?

    #if DEBUG
    @State private var debugUserId: String = ""
    #endif

    var body: some View {
        VStack(spacing: 16) {
            Text("Sign In")
                .font(.title)

            SignInWithAppleButton(.signIn) { _ in
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                        apply(.signInFailed)
                        return
                    }
                    apply(.signInSucceeded(appleUserId: credential.user))
                case .failure:
                    apply(.signInFailed)
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 44)
            .padding(.horizontal)

            if let signInErrorMessage {
                Text(signInErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            #if DEBUG
            TextField("Debug Apple User ID", text: $debugUserId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            Button("Debug: Save User ID") {
                apply(.signInSucceeded(appleUserId: debugUserId))
            }

            Button("Debug: Clear User ID") {
                apply(.signOut)
            }
            #endif
        }
        .padding()
    }

    private func apply(_ action: AppleUserSessionAction) {
        let reduced = reduceAppleUserSession(
            state: AppleUserSessionState(
                storedAppleUserId: storedAppleUserId,
                signInErrorMessage: signInErrorMessage,
                verificationRevision: verificationRevision
            ),
            action: action
        )
        storedAppleUserId = reduced.storedAppleUserId
        signInErrorMessage = reduced.signInErrorMessage
        verificationRevision = reduced.verificationRevision
    }
}

struct VerifyingAppleSignInView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Verifying Apple Sign-In…")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct ContentView: View {
    @Binding var storedAppleUserId: String

    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]

    init(storedAppleUserId: Binding<String> = .constant("")) {
        _storedAppleUserId = storedAppleUserId
    }

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                    } label: {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("ログアウト") {
                        apply(.signOut)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            Text("Select an item")
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }

    private func apply(_ action: AppleUserSessionAction) {
        let reduced = reduceAppleUserSession(
            state: AppleUserSessionState(
                storedAppleUserId: storedAppleUserId,
                signInErrorMessage: nil
            ),
            action: action
        )
        storedAppleUserId = reduced.storedAppleUserId
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
