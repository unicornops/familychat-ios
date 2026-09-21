//
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

private let homeserverURL: URL = "https://smith.safechat.family"
private let token = "syl_secret_login_token"

struct LoginTokenExchangerTests {
    @Test
    func postsTheTokenToTheHomeserverAndMapsTheCredentials() async throws {
        // Given a homeserver that accepts the code.
        let recorder = StubbedLoginEndpoint.install(statusCode: 200, body: """
        {"user_id":"@ana:smith.safechat.family","access_token":"syt_access","device_id":"DEVICE1","refresh_token":"syr_refresh"}
        """)
        let exchanger = LoginTokenExchanger(session: StubbedLoginEndpoint.session)
        
        // When redeeming it.
        let credentials = try await exchanger.exchange(token: token, homeserverURL: homeserverURL, initialDeviceName: "Family Chat iOS")
        
        // Then exactly one m.login.token request went to the homeserver's login endpoint.
        let request = try #require(recorder.requests.first)
        #expect(recorder.requests.count == 1)
        #expect(request.url == URL(string: "https://smith.safechat.family/_matrix/client/v3/login"))
        #expect(request.httpMethod == "POST")
        let body = try #require(recorder.bodies.first.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["type"] as? String == "m.login.token")
        #expect(body["token"] as? String == token)
        #expect(body["initial_device_display_name"] as? String == "Family Chat iOS")
        
        // And the credentials are mapped.
        #expect(credentials == LoginTokenCredentials(userID: "@ana:smith.safechat.family",
                                                     accessToken: "syt_access",
                                                     deviceID: "DEVICE1",
                                                     refreshToken: "syr_refresh"))
    }
    
    @Test
    func usedOrExpiredCodeIsRejected() async {
        // Given a homeserver that refuses the code.
        _ = StubbedLoginEndpoint.install(statusCode: 403, body: #"{"errcode":"M_FORBIDDEN","error":"Invalid login token"}"#)
        let exchanger = LoginTokenExchanger(session: StubbedLoginEndpoint.session)
        
        // Then the exchange reports the refusal, without the token.
        await #expect(throws: LoginTokenExchangeError.self) {
            try await exchanger.exchange(token: token, homeserverURL: homeserverURL, initialDeviceName: nil)
        }
        do {
            _ = try await exchanger.exchange(token: token, homeserverURL: homeserverURL, initialDeviceName: nil)
            Issue.record("The exchange should have failed.")
        } catch LoginTokenExchangeError.rejected(let errcode) {
            #expect(errcode == "M_FORBIDDEN")
            #expect(!String(describing: errcode).contains(token))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    @Test
    func unreadableAnswerIsUnexpected() async {
        // Given a homeserver that answers with something else.
        _ = StubbedLoginEndpoint.install(statusCode: 200, body: "<html>not json</html>")
        let exchanger = LoginTokenExchanger(session: StubbedLoginEndpoint.session)
        
        do {
            _ = try await exchanger.exchange(token: token, homeserverURL: homeserverURL, initialDeviceName: nil)
            Issue.record("The exchange should have failed.")
        } catch LoginTokenExchangeError.unexpectedResponse(let statusCode) {
            #expect(statusCode == 200)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

// MARK: - Stubbed endpoint

/// Records every request the exchanger makes and answers with a fixed response.
private final nonisolated class LoginRequestRecorder: @unchecked Sendable {
    var requests: [URLRequest] = []
    var bodies: [Data] = []
}

private final nonisolated class StubbedLoginEndpoint: URLProtocol {
    nonisolated(unsafe) static var recorder = LoginRequestRecorder()
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var body = Data()
    
    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubbedLoginEndpoint.self]
        return URLSession(configuration: configuration)
    }
    
    @discardableResult
    static func install(statusCode: Int, body: String) -> LoginRequestRecorder {
        let recorder = LoginRequestRecorder()
        self.recorder = recorder
        self.statusCode = statusCode
        self.body = Data(body.utf8)
        return recorder
    }
    
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }
    
    override func startLoading() {
        Self.recorder.requests.append(request)
        Self.recorder.bodies.append(request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data())
        
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: Self.statusCode, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    
    override func stopLoading() {
        // Nothing to cancel: the stubbed answer is delivered synchronously.
    }
    
    /// URLSession hands a POST body to a `URLProtocol` as a stream, not as `httpBody`.
    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
