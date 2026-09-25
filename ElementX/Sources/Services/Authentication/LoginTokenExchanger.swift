//
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// The credentials a homeserver hands back for a redeemed `m.login.token`.
struct LoginTokenCredentials: Equatable {
    let userID: String
    let accessToken: String
    let deviceID: String
    let refreshToken: String?
}

enum LoginTokenExchangeError: Error {
    /// The homeserver refused the code: already used, expired, or not one of its own (401/403).
    case rejected(errcode: String?)
    /// The homeserver answered with something other than credentials.
    case unexpectedResponse(statusCode: Int?)
    /// The homeserver could not be reached.
    case network(Error)
}

/// Redeems a control panel sign-in code (`m.login.token`) with the family's homeserver.
///
/// The Rust SDK exposes password, OAuth and QR logins but no `m.login.token` entry point, so the exchange is a plain
/// `POST /_matrix/client/v3/login` done here; the resulting credentials are then handed to the SDK as a restored session.
protocol LoginTokenExchangerProtocol {
    /// - Parameters:
    ///   - token: the single-use login token. It is sent to `homeserverURL` and nowhere else, and never logged.
    ///   - homeserverURL: the `https://<hs>` base URL of the homeserver named by the link.
    ///   - initialDeviceName: the device name shown in the user's session list.
    func exchange(token: String, homeserverURL: URL, initialDeviceName: String?) async throws -> LoginTokenCredentials
    
    /// Best effort `POST /_matrix/client/v3/logout` for a session from `exchange` that is not going to be used, so it
    /// doesn't linger as a signed-in device. Never throws; failures are only logged.
    func logout(accessToken: String, homeserverURL: URL) async
}

struct LoginTokenExchanger: LoginTokenExchangerProtocol {
    private let session: URLSession
    
    /// - Parameter session: an ephemeral session by default, so nothing about the exchange is cached on disk.
    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }
    
    func exchange(token: String, homeserverURL: URL, initialDeviceName: String?) async throws -> LoginTokenCredentials {
        var request = URLRequest(url: homeserverURL.appending(path: "_matrix/client/v3/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(LoginRequest(token: token, initialDeviceDisplayName: initialDeviceName))
        
        let (data, response): (Data, URLResponse)
        do {
            // Never follow a redirect: a 307/308 would re-POST the token to wherever the answer points.
            (data, response) = try await session.data(for: request, delegate: RedirectRefusingTaskDelegate.shared)
        } catch {
            MXLog.warning("Sign-in code exchange: homeserver unreachable.")
            throw LoginTokenExchangeError.network(error)
        }
        
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        guard let statusCode, (200..<300).contains(statusCode) else {
            let errorBody = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            MXLog.warning("Sign-in code exchange refused: HTTP \(statusCode.map(String.init) ?? "?") \(errorBody?.errcode ?? "")")
            if statusCode == 401 || statusCode == 403 {
                throw LoginTokenExchangeError.rejected(errcode: errorBody?.errcode)
            }
            throw LoginTokenExchangeError.unexpectedResponse(statusCode: statusCode)
        }
        
        guard let loginResponse = try? JSONDecoder().decode(LoginResponse.self, from: data) else {
            MXLog.warning("Sign-in code exchange: unreadable login response.")
            throw LoginTokenExchangeError.unexpectedResponse(statusCode: statusCode)
        }
        
        return LoginTokenCredentials(userID: loginResponse.userID,
                                     accessToken: loginResponse.accessToken,
                                     deviceID: loginResponse.deviceID,
                                     refreshToken: loginResponse.refreshToken)
    }
    
    func logout(accessToken: String, homeserverURL: URL) async {
        var request = URLRequest(url: homeserverURL.appending(path: "_matrix/client/v3/logout"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)
        
        do {
            let (_, response) = try await session.data(for: request, delegate: RedirectRefusingTaskDelegate.shared)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            MXLog.info("Discarded the sign-in code's session: HTTP \(statusCode.map(String.init) ?? "?")")
        } catch {
            MXLog.warning("Could not discard the sign-in code's session, the homeserver is unreachable.")
        }
    }
    
    // MARK: - Wire format
    
    private struct LoginRequest: Encodable {
        let type = "m.login.token"
        let token: String
        let initialDeviceDisplayName: String?
        
        enum CodingKeys: String, CodingKey {
            case type
            case token
            case initialDeviceDisplayName = "initial_device_display_name"
        }
    }
    
    private struct LoginResponse: Decodable {
        let userID: String
        let accessToken: String
        let deviceID: String
        let refreshToken: String?
        
        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case accessToken = "access_token"
            case deviceID = "device_id"
            case refreshToken = "refresh_token"
        }
    }
    
    private struct ErrorResponse: Decodable {
        let errcode: String?
        let error: String?
    }
}

/// Refuses every HTTP redirect, so a request carrying a credential is only ever sent to the URL it was made for. The
/// redirect response itself is then delivered as the answer, which the caller treats as a failure.
final nonisolated class RedirectRefusingTaskDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = RedirectRefusingTaskDelegate()
    
    // The completion handler variant: Swift 6.3 crashes emitting the Objective-C thunk for the async one.
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        MXLog.warning("Refusing an HTTP \(response.statusCode) redirect for a sign-in request.")
        completionHandler(nil)
    }
}
