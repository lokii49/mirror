import Foundation
import AuthenticationServices
import CryptoKit
import Supabase

@Observable
final class AuthService {
    static let shared = AuthService()

    private(set) var isAuthenticated = false
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
        } catch {
            isAuthenticated = false
        }
    }

    @MainActor
    func signInWithApple() async throws {
        let coordinator = AppleSignInCoordinator()
        signInCoordinator = coordinator
        defer { signInCoordinator = nil }
        let session = try await coordinator.signIn(using: client)
        KeychainManager.save(token: session.accessToken)
        isAuthenticated = true
    }

    func signOut() async throws {
        try await client.auth.signOut()
        KeychainManager.delete()
        isAuthenticated = false
    }
}

@MainActor
private final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private var continuation: CheckedContinuation<Session, Error>?
    private var nonce = ""
    private weak var client: SupabaseClient?

    func signIn(using client: SupabaseClient) async throws -> Session {
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
                continuation?.resume(returning: session)
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
