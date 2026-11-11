import Foundation
import Security

/// Microsoft Graph client for OneDrive/SharePoint edit links (FR-11b).
///
/// Authentication uses the OAuth 2.0 **device code** flow so the app needs no
/// redirect URI or embedded browser: the user visits the Microsoft page, types
/// the shown code, and MotStar polls for the token. Tokens are kept in the
/// Keychain. Requires an Entra ID (Azure AD) app registration:
///   - public client ("Allow public client flows" = Yes)
///   - delegated permission `Files.ReadWrite` (admin consent may be required)
/// The client id and tenant are set in Settings → OneDrive sharing.
enum GraphConfig {
    static let clientIDKey = "motstar.graphClientID"
    static let tenantKey = "motstar.graphTenant"

    static var clientID: String {
        (UserDefaults.standard.string(forKey: clientIDKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var tenant: String {
        let t = (UserDefaults.standard.string(forKey: tenantKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "common" : t
    }

    static var isConfigured: Bool { !clientID.isEmpty }
}

/// A file that lives inside a cloud-synced root on disk.
struct OneDriveLocation {
    let root: URL
    /// Path inside the sync root, no leading slash (e.g. `OD-OW/notes.md`).
    let relativePath: String
    /// The sync-root folder name, e.g. `OneDrive-Personal(2)`.
    let displayName: String
}

enum OneDriveShareError: LocalizedError {
    case notOneDrive
    case notConfigured
    case authRequired
    case cancelled
    case http(Int, String)
    case noLink

    var errorDescription: String? {
        switch self {
        case .notOneDrive:
            return "This file is not inside a OneDrive or SharePoint folder."
        case .notConfigured:
            return """
            OneDrive sharing isn't set up yet.

            Add your Entra ID app registration's Application (client) ID in \
            Settings → OneDrive sharing. The app needs the delegated \
            Microsoft Graph permission Files.ReadWrite.
            """
        case .authRequired:
            return "Sign in to Microsoft to create OneDrive links."
        case .cancelled:
            return "Sign-in cancelled."
        case .http(let code, let body):
            return "Microsoft Graph returned HTTP \(code).\n\n\(body)"
        case .noLink:
            return "Microsoft Graph did not return a share link."
        }
    }
}

struct DeviceCodeInfo {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let expiresIn: Int
    let interval: Int
}

struct GraphTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
}

enum GraphKeychain {
    private static let service = "com.motstar.mac.graph"
    private static let account = "tokens"

    static func save(_ tokens: GraphTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> GraphTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(GraphTokens.self, from: data)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class OneDriveShareService {
    static let shared = OneDriveShareService()

    private let graph = "https://graph.microsoft.com/v1.0"
    private let session = URLSession(configuration: .ephemeral)

    private init() {}

    // MARK: - Detection

    /// Recognises files inside a macOS CloudStorage OneDrive/SharePoint sync
    /// root (and the legacy `~/OneDrive` layout).
    static func locate(_ url: URL) -> OneDriveLocation? {
        let path = url.standardizedFileURL.path
        let marker = "/Library/CloudStorage/"
        if let r = path.range(of: marker) {
            let rest = path[r.upperBound...]
            guard let first = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first else {
                return nil
            }
            let name = String(first)
            guard name.hasPrefix("OneDrive") || name.hasPrefix("SharePoint") else { return nil }
            let rootPath = String(path[..<r.upperBound]) + name
            let rel = String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return OneDriveLocation(root: URL(fileURLWithPath: rootPath), relativePath: rel, displayName: name)
        }

        // Legacy layout: ~/OneDrive or ~/OneDrive - Org/…
        let home = NSHomeDirectory() + "/"
        guard path.hasPrefix(home) else { return nil }
        let firstComponent = path.dropFirst(home.count)
            .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        guard firstComponent.hasPrefix("OneDrive") else { return nil }
        let rootPath = home + firstComponent
        let rel = String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return OneDriveLocation(root: URL(fileURLWithPath: rootPath), relativePath: rel, displayName: firstComponent)
    }

    // MARK: - Public API

    /// Returns a Microsoft Graph edit link for the file, refreshing or asking
    /// for a device-code sign-in as needed. Completion is on the main queue.
    func createEditLink(for url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let location = Self.locate(url) else {
            finish(completion, .failure(OneDriveShareError.notOneDrive)); return
        }
        guard GraphConfig.isConfigured else {
            finish(completion, .failure(OneDriveShareError.notConfigured)); return
        }
        withToken { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.finish(completion, .failure(error))
            case .success(let token):
                self.resolveItem(location: location, token: token) { itemResult in
                    switch itemResult {
                    case .failure(let error):
                        self.finish(completion, .failure(error))
                    case .success(let itemID):
                        self.makeLink(itemID: itemID, token: token, completion: completion)
                    }
                }
            }
        }
    }

    /// Starts the device-code flow. The caller shows `userCode`/`verificationURL`
    /// to the user, then calls `pollForToken`.
    func startDeviceCode(completion: @escaping (Result<DeviceCodeInfo, Error>) -> Void) {
        guard GraphConfig.isConfigured else {
            finish(completion, .failure(OneDriveShareError.notConfigured)); return
        }
        var request = URLRequest(url: URL(string: "https://login.microsoftonline.com/\(GraphConfig.tenant)/oauth2/v2.0/devicecode")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "client_id=\(formEncode(GraphConfig.clientID))&scope=\(formEncode("Files.ReadWrite offline_access"))"
        request.httpBody = body.data(using: .utf8)

        session.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            if let error { self.finish(completion, .failure(error)); return }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let deviceCode = json["device_code"] as? String,
                  let userCode = json["user_code"] as? String,
                  let verification = (json["verification_uri"] as? String) ?? (json["verification_url"] as? String),
                  let url = URL(string: verification) else {
                self.finish(completion, .failure(OneDriveShareError.http(0, String(data: data ?? Data(), encoding: .utf8) ?? "")))
                return
            }
            let info = DeviceCodeInfo(
                deviceCode: deviceCode,
                userCode: userCode,
                verificationURL: url,
                expiresIn: json["expires_in"] as? Int ?? 900,
                interval: json["interval"] as? Int ?? 5
            )
            self.finish(completion, .success(info))
        }.resume()
    }

    /// Polls the token endpoint until the user completes sign-in or it expires.
    func pollForToken(_ info: DeviceCodeInfo, completion: @escaping (Result<Void, Error>) -> Void) {
        let deadline = Date().addingTimeInterval(TimeInterval(info.expiresIn))
        poll(info, deadline: deadline, completion: completion)
    }

    func signOut() {
        GraphKeychain.clear()
    }

    // MARK: - Token handling

    private func withToken(completion: @escaping (Result<String, Error>) -> Void) {
        if let tokens = GraphKeychain.load() {
            if tokens.expiresAt > Date().addingTimeInterval(60) {
                finish(completion, .success(tokens.accessToken)); return
            }
            if let refresh = tokens.refreshToken {
                refreshToken(refresh) { result in
                    switch result {
                    case .success(let new): completion(.success(new.accessToken))
                    case .failure: completion(.failure(OneDriveShareError.authRequired))
                    }
                }
                return
            }
        }
        completion(.failure(OneDriveShareError.authRequired))
    }

    private func refreshToken(_ refresh: String, completion: @escaping (Result<GraphTokens, Error>) -> Void) {
        var request = tokenRequest()
        request.httpBody = [
            "client_id=\(formEncode(GraphConfig.clientID))",
            "grant_type=refresh_token",
            "refresh_token=\(formEncode(refresh))",
            "scope=\(formEncode("Files.ReadWrite offline_access"))"
        ].joined(separator: "&").data(using: .utf8)

        session.dataTask(with: request) { data, _, error in
            if let error { self.finish(completion, .failure(error)); return }
            guard let tokens = self.tokens(from: data) else {
                self.finish(completion, .failure(OneDriveShareError.authRequired)); return
            }
            GraphKeychain.save(tokens)
            self.finish(completion, .success(tokens))
        }.resume()
    }

    private func poll(_ info: DeviceCodeInfo, deadline: Date, completion: @escaping (Result<Void, Error>) -> Void) {
        guard Date() < deadline else {
            finish(completion, .failure(OneDriveShareError.cancelled)); return
        }
        var request = tokenRequest()
        request.httpBody = [
            "client_id=\(formEncode(GraphConfig.clientID))",
            "grant_type=urn:ietf:params:oauth:grant-type:device_code",
            "device_code=\(formEncode(info.deviceCode))"
        ].joined(separator: "&").data(using: .utf8)

        session.dataTask(with: request) { data, _, error in
            if let error { self.finish(completion, .failure(error)); return }
            if let tokens = self.tokens(from: data) {
                GraphKeychain.save(tokens)
                self.finish(completion, .success(())); return
            }
            // pending / slow_down / expired_token — inspect the error code
            let json = (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any]
            let code = json?["error"] as? String
            if code == "authorization_pending" || code == "slow_down" {
                let delay = TimeInterval(info.interval + (code == "slow_down" ? 5 : 0))
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self.poll(info, deadline: deadline, completion: completion)
                }
                return
            }
            self.finish(completion, .failure(OneDriveShareError.authRequired))
        }.resume()
    }

    private func tokenRequest() -> URLRequest {
        var request = URLRequest(url: URL(string: "https://login.microsoftonline.com/\(GraphConfig.tenant)/oauth2/v2.0/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func tokens(from data: Data?) -> GraphTokens? {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else { return nil }
        let expires = json["expires_in"] as? Int ?? 3600
        return GraphTokens(
            accessToken: access,
            refreshToken: json["refresh_token"] as? String,
            expiresAt: Date().addingTimeInterval(TimeInterval(expires))
        )
    }

    // MARK: - Graph calls

    private func resolveItem(location: OneDriveLocation, token: String, completion: @escaping (Result<String, Error>) -> Void) {
        let encodedPath = location.relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        guard let url = URL(string: "\(graph)/me/drive/root:/\(encodedPath)") else {
            finish(completion, .failure(OneDriveShareError.notOneDrive)); return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let error { self.finish(completion, .failure(error)); return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200,
                  let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any],
                  let id = json["id"] as? String else {
                self.finish(completion, .failure(OneDriveShareError.http(status, String(data: data ?? Data(), encoding: .utf8) ?? "")))
                return
            }
            self.finish(completion, .success(id))
        }.resume()
    }

    private func makeLink(itemID: String, token: String, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let url = URL(string: "\(graph)/me/drive/items/\(itemID)/createLink") else {
            finish(completion, .failure(OneDriveShareError.noLink)); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["type": "edit", "scope": "organization"])

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let error { self.finish(completion, .failure(error)); return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...201).contains(status),
                  let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any],
                  let link = json["link"] as? [String: Any],
                  let web = link["webUrl"] as? String,
                  let webURL = URL(string: web) else {
                self.finish(completion, .failure(OneDriveShareError.http(status, String(data: data ?? Data(), encoding: .utf8) ?? "")))
                return
            }
            self.finish(completion, .success(webURL))
        }.resume()
    }

    // MARK: - Helpers

    private func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    private func finish<T>(_ completion: @escaping (Result<T, Error>) -> Void, _ result: Result<T, Error>) {
        DispatchQueue.main.async { completion(result) }
    }
}
