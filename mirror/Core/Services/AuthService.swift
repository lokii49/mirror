import Foundation
import AuthenticationServices
import CryptoKit
import Supabase
import RevenueCat

@Observable
final class AuthService {
    static let shared = AuthService()

    private(set) var isAuthenticated = false
    private(set) var userName: String? = nil
    private(set) var userEmail: String? = nil
    var supabaseToken: String? { KeychainManager.load() }

    let client = SupabaseClient(
        supabaseURL: URL(string: "https://apaslxvndvuqlxlbgemi.supabase.co")!,
        supabaseKey: "sb_publishable_B0REbsQ_d37N9ASebsITTw_54gYZKmH",
        options: SupabaseClientOptions(
            auth: SupabaseClientOptions.AuthOptions(
                emitLocalSessionAsInitialSession: true
            )
        )
    )

    private var signInCoordinator: AppleSignInCoordinator?

    private init() {
        Task { await checkSession() }
    }

    func checkSession() async {
        do {
            let session = try await client.auth.session
            KeychainManager.save(token: session.accessToken)
            isAuthenticated = true
            await fetchUserInfo()
        } catch {
            isAuthenticated = false
            userName = nil
            userEmail = nil
        }
    }

    private func fetchUserInfo() async {
        guard let user = try? await client.auth.user() else {
            // Fall back to local cache when offline
            userName = UserDefaults.standard.string(forKey: "mirror.userName")
            return
        }
        userEmail = user.email

        // Try Supabase userMetadata first (populated on first sign-in below)
        let meta = user.userMetadata
        if let json = meta["full_name"], case .string(let name) = json, !name.isEmpty {
            userName = name
            UserDefaults.standard.set(name, forKey: "mirror.userName")
        } else if let cached = UserDefaults.standard.string(forKey: "mirror.userName"), !cached.isEmpty {
            // Local cache — covers cases where metadata isn't set yet
            userName = cached
        }
    }

    @MainActor
    func signInWithApple() async throws {
        let coordinator = AppleSignInCoordinator()
        signInCoordinator = coordinator
        defer { signInCoordinator = nil }

        let result = try await coordinator.signIn(using: client)
        KeychainManager.save(token: result.session.accessToken)
        isAuthenticated = true

        // Apple only provides fullName on the very first sign-in.
        // Persist it to Supabase metadata so it survives future sessions.
        if let components = result.fullName {
            let name = [components.givenName, components.familyName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !name.isEmpty {
                try? await client.auth.update(
                    user: UserAttributes(data: ["full_name": .string(name)])
                )
                userName = name
                UserDefaults.standard.set(name, forKey: "mirror.userName")
            }
        }

        if userName == nil { await fetchUserInfo() }

        _ = try? await Purchases.shared.logIn(result.session.user.id.uuidString)
    }

    func setUserName(_ name: String) {
        userName = name
    }

    func updateDisplayName(_ name: String) async {
        guard !name.isEmpty else { return }
        UserDefaults.standard.set(name, forKey: "mirror.userName")
        userName = name
        try? await client.auth.update(
            user: UserAttributes(data: ["full_name": .string(name)])
        )
    }

    func signOut() async throws {
        try await client.auth.signOut()
        KeychainManager.delete()
        UserDefaults.standard.removeObject(forKey: "mirror.userName")
        isAuthenticated = false
        userName = nil
        userEmail = nil
        try? await Purchases.shared.logOut()
    }
}

// MARK: - Apple Sign In Coordinator

private struct AppleSignInResult {
    let session: Session
    let fullName: PersonNameComponents?
}

@MainActor
private final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private var continuation: CheckedContinuation<AppleSignInResult, Error>?
    private var nonce = ""
    private weak var client: SupabaseClient?

    func signIn(using client: SupabaseClient) async throws -> AppleSignInResult {
        self.client = client
        nonce = randomNonce()

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task {
            do {
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let idToken = String(data: tokenData, encoding: .utf8),
                      let client else {
                    continuation?.resume(throwing: AuthError.invalidCredential)
                    continuation = nil
                    return
                }
                let session = try await client.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
                )
                // fullName is non-nil only on the very first Apple Sign In
                continuation?.resume(returning: AppleSignInResult(
                    session: session,
                    fullName: credential.fullName
                ))
            } catch {
                continuation?.resume(throwing: error)
            }
            continuation = nil
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func sha256(_ input: String) -> String {
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

enum AuthError: LocalizedError {
    case invalidCredential

    var errorDescription: String? {
        "Apple Sign In returned an invalid credential."
    }
}
