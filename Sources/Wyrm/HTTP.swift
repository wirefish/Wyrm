//
//  HTTP.swift
//  Wyrm
//

import Foundation
import Network
import Dispatch

let HTTP1_1 = "HTTP/1.1"

enum HTTPStatus: Int {
    case `continue` = 100
    case switchingProtocols = 101
    case ok = 200
    case notModified = 304
    case badRequest = 400
    case unauthorized = 401
    case notFound = 404
    case methodNotAllowed = 405
    case internalServerError = 500
}

enum HTTPMethod: String {
    case HEAD, GET
}

typealias HTTPHeader = (name: String, value: String)

struct HTTPRequestHead {
    let method: HTTPMethod
    let uri: String
    let headers: [HTTPHeader]

    init?(from data: Data) {
        guard let head = String(data: data, encoding: .ascii),
              head.hasSuffix("\r\n\r\n") else {
            return nil
        }

        let lines = head.split(whereSeparator: \.isNewline)

        // The first line should look like "<method> <uri> <version>".
        let parts = lines[0].split(separator: " ", maxSplits: 2)
        guard parts.count == 3,
              let method = HTTPMethod(rawValue: String(parts[0])),
              parts[2] == HTTP1_1 else {
            return nil
        }
        self.method = method
        self.uri = String(parts[1])

        // Subsequent lines look like "<name>: <value>".
        var headers = [HTTPHeader]()
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else {
                return nil
            }
            headers.append(HTTPHeader(name: parts[0].lowercased(),
                                      value: String(parts[1].trimmed(\.isWhitespace))))
        }
        self.headers = headers
    }

    func getHeader(_ name: String) -> String? {
        let name = name.lowercased()
        return headers.first(where: { $0.name == name })?.value
    }

    func getCookie(_ name: String) -> String? {
        guard let cookies = getHeader("Cookie")?.split(separator: ";") else {
            return nil
        }
        for cookie in cookies {
            if let sep = cookie.firstIndex(of: "=") {
                if cookie[..<sep] == name {
                    return String(cookie.suffix(from: cookie.index(after: sep))
                        .trimmed(\.isWhitespace))
                }
            }
        }
        return nil
    }
}

struct HTTPResponseHead {
    let status: HTTPStatus
    var headers: [HTTPHeader]

    static let statusNames: [HTTPStatus:String] = [
        .continue: "Continue",
        .switchingProtocols: "Switching Protocols",
        .ok: "OK",
        .notModified: "Not Modified",
        .badRequest: "Bad Request",
        .unauthorized: "Unauthorized",
        .notFound: "Not Found",
        .methodNotAllowed: "Method Not Allowed",
        .internalServerError: "Internal Server Error",
    ]

    func encode(into data: inout Data) {
        data += "\(HTTP1_1) \(status.rawValue) \(Self.statusNames[status] ?? "?")\r\n"
            .data(using: .ascii)!

        for header in headers {
            data += "\(header.name): \(header.value)\r\n".data(using: .ascii)!
        }
        data += "\r\n".data(using: .ascii)!
    }
}

protocol HTTPHandler: TCPHandler {
    func processRequest(_ request: HTTPRequestHead, _ conn: TCPConnection)
}

extension HTTPHandler {
    func start(_ conn: TCPConnection) {
        readRequestHead(conn)
    }

    func readRequestHead(_ conn: TCPConnection) {
        conn.receive(maximumLength: 2048) { data, conn in
            if let request = HTTPRequestHead(from: data) {
                self.processRequest(request, conn)
            } else {
                conn.finish()
            }
        }
    }

    func respondWithStatus(_ status: HTTPStatus, extraHeaders: [HTTPHeader] = [],
                           body: Data? = nil, _ conn: TCPConnection) {
        let length = body?.count ?? 0
        let head = HTTPResponseHead(status: status,
                                    headers: [("Content-Length", String(length))] + extraHeaders)

        var data = Data(capacity: 1024 + length)
        head.encode(into: &data)
        if let body = body {
            data += body
        }
        conn.send(data)

        if status != .switchingProtocols {
            readRequestHead(conn)
        }
    }
}

protocol TCPHandler {
    func start(_ conn: TCPConnection)
    func finish(_ conn: TCPConnection)
}

class TCPConnection {
    private var conn: NWConnection
    private var handler: TCPHandler

    init(_ conn: NWConnection, _ handler: TCPHandler) {
        self.conn = conn
        self.handler = handler
        self.conn.stateUpdateHandler = onStateChange
        self.conn.start(queue: DispatchQueue.main)
    }

    deinit {
        logger.debug("TCPConnection destroyed")
    }

    private func onStateChange(_ state: NWConnection.State) {
        logger.debug("connection state changed to \(state)")
        switch state {
        case let .failed(error):
            logger.warning("connection failed: \(error)")
            finish()
        case .ready:
            self.handler.start(self)
        default:
            break
      }
    }

    func finish() {
        self.conn.stateUpdateHandler = nil
        self.conn.cancel()
        self.handler.finish(self)
    }

    func replaceHandler(_ newHandler: TCPHandler) {
        handler.finish(self)
        handler = newHandler
        handler.start(self)
    }

    func receive(maximumLength: Int, then cb: @escaping (Data, TCPConnection) -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: maximumLength) {
            data, context, isComplete, error in
            if let data = data {
                cb(data, self)
            } else {
                self.finish()
            }
        }
    }

    func send(_ data: Data) {
        conn.send(content: data, completion: .contentProcessed({ error in
            if error != nil {
                self.finish()
            }
        }))
    }

    func send(_ datagrams: [Data]) {
        conn.batch {
            for data in datagrams {
                conn.send(content: data, completion: .contentProcessed({ error in
                    if error != nil {
                        self.finish()
                    }
                }))
            }
        }
    }
}

class TCPServer {
    let listener: NWListener
    var handlerFactory: (() -> HTTPHandler)!

    init?(port: UInt16) {
        do {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port(integerLiteral: port))
        } catch {
            logger.error("cannot create listener: \(error)")
            return nil
        }
        listener.stateUpdateHandler = onListenerStateChange
        listener.newConnectionHandler = onNewConnection
    }

    func run(_ factory: @escaping () -> HTTPHandler) {
        self.handlerFactory = factory
        listener.start(queue: DispatchQueue.main)
        dispatchMain()
    }

    func onListenerStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            logger.info("listening on port \(listener.port!)")
        case let .failed(error):
            fatalError("listener failed: \(error)")
        default:
            break
        }
    }

    func onNewConnection(_ connection: NWConnection) {
        logger.info("new connection from \(connection.endpoint)")
        _ = TCPConnection(connection, handlerFactory())
    }
}
