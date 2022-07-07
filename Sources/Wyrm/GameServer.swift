//
//  GameServer.swift
//  Wyrm
//

import Foundation

fileprivate let signingKey = getRandomBytes(32)!

fileprivate let authCookieName = "WyrmAuth"

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
        let call = ClientCall(fn: "showNotice", args: [.string(message)])
        let encoder = JSONEncoder()
        let data = try! encoder.encode(call)
        handler.sendTextMessage(String(data: data, encoding: .utf8)!)
    }
}

class GameHandler: HTTPHandler {

    static let endpoints = [
        "/game/createAccout": handleCreateAccountRequest,
        "/game/login": handleLoginRequest,
        "/game/logout": handleLogoutRequest,
        "/game/auth": handleAuthRequest,
        "/game/session": handleSessionRequest,
    ]

    func processRequest(_ request: HTTPRequestHead, _ conn: TCPConnection) {
        if let fn = Self.endpoints[request.uri] {
            fn(self)(conn, request)
        } else if request.uri == "/" {
            handleStaticFileRequest(conn, "/index.html")
        } else {
            handleStaticFileRequest(conn, request.uri)
        }
    }

    func finish(_ conn: TCPConnection) {
        // TODO:
    }

    func handleCreateAccountRequest(_ conn: TCPConnection, _ request: HTTPRequestHead) {
        guard let (username, password) = parseCredentials(request) else {
            respondWithStatus(.badRequest, conn)
            return
        }

        // FIXME:
        guard case let .entity(e) = World.instance.lookup(.relative("avatar"), in: nil) else {
            fatalError("cannot find avatar prototype")
        }
        let avatar = (e as! Avatar).clone()

        guard let accountID = World.instance.db.createAccount(
            username: username, password: password, avatar: avatar) else {
            respondWithStatus(.badRequest, conn)
            return
        }

        let token = AuthToken(accountID: accountID, username: username)
        respondWithStatus(
                .ok,
                extraHeaders: [("Cookie", "\(authCookieName)=\(token.base64EncodedString())")],
                conn)
    }

    func handleLoginRequest(_ conn: TCPConnection, _ request: HTTPRequestHead) {
        guard let (username, password) = parseCredentials(request) else {
            respondWithStatus(.badRequest, conn)
            return
        }

        guard let accountID = World.instance.db.authenticate(username: username, password: password) else {
            respondWithStatus(.unauthorized, conn)
            return
        }

        let encoder = JSONEncoder()
        let body = try! encoder.encode(["username": username])

        let token = AuthToken(accountID: accountID, username: username)
        respondWithStatus(
            .ok,
            extraHeaders: [("Set-Cookie", "\(authCookieName)=\(token.base64EncodedString())")],
            body: body,
            conn)
    }

    func handleLogoutRequest(_ conn: TCPConnection, _ request: HTTPRequestHead) {
        respondWithStatus(
            .ok,
            extraHeaders: [("Set-Cookie", "\(authCookieName)=invalid; Max-Age=0")],
            conn)
    }

    func handleAuthRequest(_ conn: TCPConnection, _ request: HTTPRequestHead) {
        if let token = checkAuthToken(request) {
            let encoder = JSONEncoder()
            let body = try! encoder.encode(["username": token.username])
           respondWithStatus(.ok, body: body, conn)
        } else {
           respondWithStatus(.unauthorized, conn)
        }
    }

    func handleSessionRequest(_ conn: TCPConnection, _ request: HTTPRequestHead) {
        guard checkAuthToken(request) != nil else {
            respondWithStatus(.unauthorized, conn)
            return
        }

        if WebSocketHandler.startUpgrade(self, request, conn) {
            logger.debug("upgraded to websocket")
            conn.replaceHandler(WebSocketHandler(delegate: GameWebSocketDelegate()))
        } else {
            respondWithStatus(.badRequest, conn)
        }
    }

    static let contentTypes = [
        "css": "text/css",
        "js": "application/javascript",
        "html": "text/html",
        "jpg": "image/jpeg",
        "png": "image/png",
        "woff": "font/woff",
    ]

    // FIXME:
    static let base = "/Users/craig/Projects/Wyrm/.build/client"

    func handleStaticFileRequest(_ conn: TCPConnection, _ uri: String) {
        let url = URL(fileURLWithPath: Self.base + uri, isDirectory: false)
        guard !url.pathComponents.contains("..") else {
            respondWithStatus(.badRequest, conn)
            return
        }

        let contentType = Self.contentTypes[url.pathExtension] ?? "text/plain"
        if let data = try? Data(contentsOf: url, options: []) {
            respondWithStatus(.ok,
                              extraHeaders: [("Content-Type", contentType)],
                              body: data,
                              conn)
        } else {
            respondWithStatus(.notFound, conn)
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

class GameServer {
    let tcpServer: TCPServer

    init?(_ config: Config) {
        guard let tcpServer = TCPServer(port: config.server.port,
                                        handlerFactory: { GameHandler() }) else {
            return nil
        }
        self.tcpServer = tcpServer
    }

    func run() {
        tcpServer.run()
    }
}
