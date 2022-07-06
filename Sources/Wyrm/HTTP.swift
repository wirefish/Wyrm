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

class HTTPConnection {
    weak var server: HTTPServer!
    var conn: NWConnection

    init(_ server: HTTPServer, _ conn: NWConnection) {
        self.server = server
        self.conn = conn
        self.conn.stateUpdateHandler = onStateChange
        self.conn.start(queue: DispatchQueue.main)
    }

    deinit {
        print("bye")
    }

    func onStateChange(_ state: NWConnection.State) {
        switch state {
        case let .failed(error):
            logger.warning("connection failed: \(error)")
            self.conn.stateUpdateHandler = nil
            self.conn.forceCancel()
        default:
            logger.debug("connection state changed to \(state)")
      }
    }

    func readHeaders() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 2048, completion: onReadHeaders)
    }

    func onReadHeaders(_ data: Data?, _ contentContext: NWConnection.ContentContext?,
                       _ isComplete: Bool, _ error: NWError?) {
        guard let data = data, let head = HTTPRequestHead(from: data) else {
            return
        }
        if let handler = server.endpoints[head.uri] {
            handler(self, head)
        } else {
            respondWithStatus(.notFound)
        }
    }

    func writeResponse(head: HTTPResponseHead, body: Data?) {
    }

    func respondWithStatus(_ status: HTTPStatus, extraHeaders: [HTTPHeader] = [],
                           body: Data? = nil) {
        let length = body?.count ?? 0
        let head = HTTPResponseHead(status: status,
                                    headers: [("Content-Length", String(length))] + extraHeaders)

        var data = Data(capacity: 1024 + length)
        head.encode(into: &data)
        if let body = body {
            data += body
        }
        
        conn.send(content: data, completion: .contentProcessed(onSendComplete))
    }

    func onSendComplete(error: NWError?) {
        if error != nil {
            // Anything?
        } else {
            readHeaders()
        }
    }
}

class HTTPServer {
    typealias EndpointHandler = (HTTPConnection, HTTPRequestHead) -> Void

    let listener: NWListener
    var endpoints = [String: EndpointHandler]()

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

    func run() {
        listener.start(queue: DispatchQueue.main)
        dispatchMain()
    }

    func onListenerStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            logger.info("listening")
        case let .failed(error):
            fatalError("listener failed: \(error)")
        default:
            break
        }
    }

    func onNewConnection(_ connection: NWConnection) {
        print("connection from \(connection.endpoint)")
        HTTPConnection(self, connection).readHeaders()
    }
}
