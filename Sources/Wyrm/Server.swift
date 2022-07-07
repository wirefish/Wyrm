//
//  Server.swift
//  Wyrm
//
//  Created by Craig Becker on 6/28/22.
//

import Foundation

fileprivate let signingKey = getRandomBytes(32)!

fileprivate let authCookieName = "WyrmAuth"

extension String {
    func withoutPrefix(_ prefix: String) -> String? {
        if starts(with: prefix) {
            return String(suffix(from: index(startIndex, offsetBy: prefix.count)))
        } else {
            return nil
        }
    }
}

struct AuthToken {
    let accountID: Database.AccountID
    let username: String

    init(accountID: Database.AccountID, username: String) {
        self.accountID = accountID
        self.username = username
    }

    init?(base64Encoded string: String) {
        guard let data = Data(base64Encoded: string),
              let token = String(data: data, encoding: .utf8),
              let sep = token.lastIndex(of: "|") else {
            return nil
        }

        let suffix = String(token.suffix(from: token.index(after: sep)))
        guard let signature = Data(base64Encoded: suffix) else {
            return nil
        }

        let prefix = token.prefix(through: sep)
        guard computeSHA1Digest(prefix.data(using: .utf8)! + signingKey) == signature else {
            return nil
        }

        let parts = token.prefix(upTo: sep).split(separator: "|")
        self.accountID = Int64(parts[0])!
        self.username = String(parts[1])
    }

    func base64EncodedString() -> String {
        var token = "\(accountID)|\(username)|"
        token += computeSHA1Digest(token.data(using: .utf8)! + signingKey).base64EncodedString()
        return token.data(using: .utf8)!.base64EncodedString()
    }
}

class GameWebSocketDelegate: WebSocketDelegate {
    func onOpen(_ handler: WebSocketHandler) {
        // TODO:
    }

    func onClose(_ handler: WebSocketHandler) {
        // TODO:
    }

    func onReceiveMessage(_ handler: WebSocketHandler, _ message: String) {
        // TODO:
    }
}

class GameHandler: HTTPHandler {
    func start(_ conn: HTTPConnection) {
    }

    static let endpoints = [
        "/game/createAccout": handleCreateAccountRequest,
        "/game/login": handleLoginRequest,
        "/game/logout": handleLogoutRequest,
        "/game/auth": handleAuthRequest,
        "/game/session": handleSessionRequest,
    ]

    func processRequest(_ request: HTTPRequestHead, _ conn: HTTPConnection) {
        if let fn = Self.endpoints[request.uri] {
            fn(self)(conn, request)
        } else {
            conn.respondWithStatus(.notFound)
        }
    }

    func finish(_ conn: HTTPConnection) {
        // TODO:
    }

    func handleCreateAccountRequest(_ conn: HTTPConnection, _ request: HTTPRequestHead) {
        guard let (username, password) = parseCredentials(request) else {
            conn.respondWithStatus(.badRequest)
            return
        }

        // FIXME:
        guard case let .entity(e) = World.instance.lookup(.relative("avatar"), in: nil) else {
            fatalError("cannot find avatar prototype")
        }
        let avatar = (e as! Avatar).clone()

        guard let accountID = World.instance.db.createAccount(
            username: username, password: password, avatar: avatar) else {
            conn.respondWithStatus(.badRequest)
            return
        }

        let token = AuthToken(accountID: accountID, username: username)
        conn.respondWithStatus(
                .ok,
                extraHeaders: [("Cookie", "\(authCookieName)=\(token.base64EncodedString())")])
    }

    func handleLoginRequest(_ conn: HTTPConnection, _ request: HTTPRequestHead) {
        guard let (username, password) = parseCredentials(request) else {
            conn.respondWithStatus(.badRequest)
            return
        }

        guard let accountID = World.instance.db.authenticate(username: username, password: password) else {
            conn.respondWithStatus(.unauthorized)
            return
        }

        let token = AuthToken(accountID: accountID, username: username)
        conn.respondWithStatus(
            .ok,
            extraHeaders: [("Cookie", "\(authCookieName)=\(token.base64EncodedString())")])
    }

    func handleLogoutRequest(_ conn: HTTPConnection, _ request: HTTPRequestHead) {
        conn.respondWithStatus(
            .ok,
            extraHeaders: [("Set-Cookie", "\(authCookieName)=invalid; Max-Age=0")])
    }

    func handleAuthRequest(_ conn: HTTPConnection, _ request: HTTPRequestHead) {
        if let token = checkAuthToken(request) {
            conn.respondWithStatus(.ok, body: token.username.data(using: .utf8))
        } else {
            conn.respondWithStatus(.unauthorized)
        }
    }

    func handleSessionRequest(_ conn: HTTPConnection, _ request: HTTPRequestHead) {
        guard checkAuthToken(request) != nil else {
            conn.respondWithStatus(.unauthorized)
            return
        }

        if WebSocketHandler.startUpgrade(conn, request) {
            conn.replaceHandler(WebSocketHandler(delegate: GameWebSocketDelegate()))
        } else {
            conn.respondWithStatus(.badRequest)
        }
    }

    func parseCredentials(_ request: HTTPRequestHead) -> (username: String, password: String)? {
        guard let auth = request.getHeader("Authorization") else {
            return nil
        }

        let parts = auth.split(separator: " ")
        guard parts.count == 2 && parts[0] == "Basic",
              let data = Data(base64Encoded: String(parts[1])),
              let credentials = String(data: data, encoding: .utf8) else {
            return nil
        }

        let credParts = credentials.split(separator: ":", maxSplits: 1)
        guard credParts.count == 2 else {
            return nil
        }

        return (String(credParts[0]), String(credParts[1]))
    }

    func checkAuthToken(_ request: HTTPRequestHead) -> AuthToken? {
        guard let cookie = request.getCookie(authCookieName),
              let token = AuthToken(base64Encoded: cookie) else {
            return nil
        }
        return token
    }
}
