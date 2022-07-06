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

class Server {

    let http: HTTPServer

    init?(config: Config) {
        guard let http = HTTPServer(port: config.server.port) else {
            return nil
        }
        self.http = http

        self.http.endpoints = [
            "/game/createAccount": handleCreateAccountRequest,
            "/game/login": handleLoginRequest,
            "/game/logout": handleLogoutRequest,
        ]
    }

    func run() {
        http.run()
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

    private func checkAuthToken(_ request: HTTPRequestHead) -> AuthToken? {
        guard let cookie = request.getCookie(authCookieName),
              let token = AuthToken(base64Encoded: cookie) else {
            return nil
        }
        return token
    }
}

/*
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
*/
