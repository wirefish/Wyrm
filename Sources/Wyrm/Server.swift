//
//  Server.swift
//  Wyrm
//
//  Created by Craig Becker on 6/28/22.
//

import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket

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
        guard computeDigest(prefix.data(using: .utf8)! + signingKey) == signature else {
            return nil
        }

        let parts = token.prefix(upTo: sep).split(separator: "|")
        self.accountID = Int64(parts[0])!
        self.username = String(parts[1])
    }

    func base64EncodedString() -> String {
        var token = "\(accountID)|\(username)|"
        token += computeDigest(token.data(using: .utf8)! + signingKey).base64EncodedString()
        return token.data(using: .utf8)!.base64EncodedString()
    }
}

private final class HTTPHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    func handlerAdded(context: ChannelHandlerContext) {
    }

    func handlerRemoved(context: ChannelHandlerContext) {
    }

    static let endpoints = [
        "/game/createAccount": handleCreateAccountRequest,
        "/game/login": handleLoginRequest,
        "/game/logout": handleLogoutRequest,
        "/game/auth": handleAuthRequest,
    ]

    func handleCreateAccountRequest(_ context: ChannelHandlerContext, _ request: HTTPRequestHead) {
        guard let (username, password) = parseCredentials(request) else {
            respondWithStatus(.badRequest, context: context)
            return
        }

        // FIXME:
        guard case let .entity(e) = World.instance.lookup(.relative("avatar"), in: nil) else {
            fatalError("cannot find avatar prototype")
        }
        let avatar = (e as! Avatar).clone()

        guard let accountID = World.instance.db.createAccount(
            username: username, password: password, avatar: avatar) else {
            respondWithStatus(.badRequest, context: context)
            return
        }

        let token = AuthToken(accountID: accountID, username: username)
        respondWithStatus(
            .ok,
            extraHeaders: [("Cookie", "\(authCookieName)=\(token.base64EncodedString())")],
            context: context)
    }

    func handleLoginRequest(_ context: ChannelHandlerContext, _ request: HTTPRequestHead) {
        guard let (username, password) = parseCredentials(request) else {
            respondWithStatus(.badRequest, context: context)
            return
        }

        guard let accountID = World.instance.db.authenticate(username: username, password: password) else {
            respondWithStatus(.unauthorized, context: context)
            return
        }

        let token = AuthToken(accountID: accountID, username: username)
        respondWithStatus(
            .ok,
            extraHeaders: [("Cookie", "\(authCookieName)=\(token.base64EncodedString())")],
            context: context)
    }

    func handleLogoutRequest(_ context: ChannelHandlerContext, _ request: HTTPRequestHead) {
        respondWithStatus(
            .ok,
            extraHeaders: [("Set-Cookie", "\(authCookieName)=invalid; Max-Age=0")],
            context: context)
    }

    func handleAuthRequest(_ context: ChannelHandlerContext, _ request: HTTPRequestHead) {
        if let token = checkAuthToken(request) {
            respondWithStatus(.ok, body: token.username, context: context)
        } else {
            respondWithStatus(.unauthorized, context: context)
        }
    }

    func parseCredentials(_ request: HTTPRequestHead) -> (username: String, password: String)? {
        let auth = request.headers[canonicalForm: "Authorization"]
        guard auth.count == 1 else {
            return nil
        }

        let parts = auth[0].split(separator: " ")
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

    private func checkAuthToken(_ request: HTTPRequestHead) -> AuthToken? {
        let cookies = request.headers[canonicalForm: "Cookie"]
        guard let cookieValue = cookies.firstMap({ cookie -> String? in
            let parts = cookie.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 && parts[0] == authCookieName else {
                return nil
            }
            return String(parts[1])
        }) else {
            return nil
        }
        guard let authToken = AuthToken(base64Encoded: cookieValue) else {
            return nil
        }
        return authToken
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let requestPart = unwrapInboundIn(data)

        guard case let .head(head) = requestPart else {
            return
        }

        guard case .GET = head.method else {
            self.respondWithStatus(.methodNotAllowed, context: context)
            return
        }

        if let endpointHandler = Self.endpoints[head.uri] {
            endpointHandler(self)(context, head)
        } else {
            // TODO: handle static files
            self.respondWithStatus(.notFound, context: context)
        }
    }

    private func respondWithStatus(_ status: HTTPResponseStatus, context: ChannelHandlerContext) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Length", value: "0")
        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        context.write(self.wrapOutboundOut(.end(nil))).whenComplete { (_: Result<Void, Error>) in
            context.close(promise: nil)
        }
        context.flush()
    }

    private func respondWithStatus(_ status: HTTPResponseStatus, extraHeaders: [(String, String)],
                                   context: ChannelHandlerContext) {
        var headers = HTTPHeaders()
        for (name, value) in extraHeaders {
            headers.add(name: name, value: value)
        }
        headers.add(name: "Content-Length", value: "0")
        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        context.write(self.wrapOutboundOut(.end(nil))).whenComplete { (_: Result<Void, Error>) in
            context.close(promise: nil)
        }
        context.flush()
    }

    private func respondWithStatus(_ status: HTTPResponseStatus, body: String,
                                   context: ChannelHandlerContext) {
        let responseBody = ByteBuffer(string: body)
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/plain")
        headers.add(name: "Content-Length", value: String(responseBody.readableBytes))
        headers.add(name: "Connection", value: "close")
        let responseHead = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
        context.write(self.wrapOutboundOut(.body(.byteBuffer(responseBody))), promise: nil)
        context.write(self.wrapOutboundOut(.end(nil))).whenComplete { (_: Result<Void, Error>) in
            context.close(promise: nil)
        }
        context.flush()
    }
}

private final class WebSocketTimeHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private var awaitingClose: Bool = false

    public func handlerAdded(context: ChannelHandlerContext) {
        self.sendTime(context: context)
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = self.unwrapInboundIn(data)

        switch frame.opcode {
        case .connectionClose:
            self.receivedClose(context: context, frame: frame)
        case .ping:
            self.pong(context: context, frame: frame)
        case .text:
            var data = frame.unmaskedData
            let text = data.readString(length: data.readableBytes) ?? ""
            print(text)
        case .binary, .continuation, .pong:
            // We ignore these frames.
            break
        default:
            // Unknown frames are errors.
            self.closeOnError(context: context)
        }
    }

    public func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }

    private func sendTime(context: ChannelHandlerContext) {
        guard context.channel.isActive else { return }

        // We can't send if we sent a close message.
        guard !self.awaitingClose else { return }

        // We can't really check for error here, but it's also not the purpose of the
        // example so let's not worry about it.
        let theTime = NIODeadline.now().uptimeNanoseconds
        var buffer = context.channel.allocator.buffer(capacity: 12)
        buffer.writeString("\(theTime)")

        let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
        context.writeAndFlush(self.wrapOutboundOut(frame)).map {
            context.eventLoop.scheduleTask(in: .seconds(1), { self.sendTime(context: context) })
        }.whenFailure { (_: Error) in
            context.close(promise: nil)
        }
    }

    private func receivedClose(context: ChannelHandlerContext, frame: WebSocketFrame) {
        // Handle a received close frame. In websockets, we're just going to
        // send the close frame and then close, unless we already sent our own
        // close frame.
        if awaitingClose {
            // Cool, we started the close and were waiting for the user. We're done.
            context.close(promise: nil)
        } else {
            // This is an unsolicited close. We're going to send a response
            // frame and then, when we've sent it, close up shop. We should send
            // back the close code the remote peer sent us, unless they didn't
            // send one at all.
            var data = frame.unmaskedData
            let closeDataCode = data.readSlice(length: 2) ?? ByteBuffer()
            let closeFrame = WebSocketFrame(fin: true, opcode: .connectionClose, data: closeDataCode)
            _ = context.write(self.wrapOutboundOut(closeFrame)).map { () in
                context.close(promise: nil)
            }
        }
    }

    private func pong(context: ChannelHandlerContext, frame: WebSocketFrame) {
        var frameData = frame.data
        let maskingKey = frame.maskKey

        if let maskingKey = maskingKey {
            frameData.webSocketUnmask(maskingKey)
        }

        let responseFrame = WebSocketFrame(fin: true, opcode: .pong, data: frameData)
        context.write(self.wrapOutboundOut(responseFrame), promise: nil)
    }

    private func closeOnError(context: ChannelHandlerContext) {
        // We have hit an error, we want to close. We do that by sending a close
        // frame and then shutting down the write side of the connection.
        var data = context.channel.allocator.buffer(capacity: 2)
        data.write(webSocketErrorCode: .protocolError)
        let frame = WebSocketFrame(fin: true, opcode: .connectionClose, data: data)
        context.write(self.wrapOutboundOut(frame)).whenComplete { (_: Result<Void, Error>) in
            context.close(mode: .output, promise: nil)
        }
        awaitingClose = true
    }
}

class Server {
    let host: String
    let port: Int
    var channel: Channel!
    var group: EventLoopGroup!

    init(config: Config) {
        host = config.server.host
        port = config.server.port
    }

    func run() {
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let upgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { (channel: Channel, head: HTTPRequestHead) in
                channel.eventLoop.makeSucceededFuture(HTTPHeaders())
            },
            upgradePipelineHandler: { (channel: Channel, _: HTTPRequestHead) in
                channel.pipeline.addHandler(WebSocketTimeHandler())
            })

        let bootstrap = ServerBootstrap(group: group)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

            // Set the handlers that are applied to the accepted Channels
            .childChannelInitializer { channel in
                let httpHandler = HTTPHandler()
                let config: NIOHTTPServerUpgradeConfiguration = (
                    upgraders: [upgrader],
                    completionHandler: { _ in
                        channel.pipeline.removeHandler(httpHandler, promise: nil)
                    })
                return channel.pipeline.configureHTTPServerPipeline(withServerUpgrade: config)
                    .flatMap { channel.pipeline.addHandler(httpHandler) }
            }

            // Enable SO_REUSEADDR for the accepted Channels
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

        defer {
            try! group.syncShutdownGracefully()
        }

        channel = try! bootstrap.bind(host: self.host, port: self.port).wait()

        guard let localAddress = channel.localAddress else {
            fatalError("could not bind to address")
        }
        logger.info("server listening on \(localAddress)")

        // group.next().scheduleTask(in: .seconds(3), { logger.fatal("oopsie") })

        World.instance.start()

        try! channel.closeFuture.wait()

        World.instance.stop()

        logger.info("server stopped")
    }

    func stop() {
        let _ = channel.close(mode: .all)
    }
}
