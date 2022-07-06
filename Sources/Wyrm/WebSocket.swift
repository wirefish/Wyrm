//
//  WebSocket.swift
//  Wyrm
//

import Foundation
import Network

protocol WebSocketDelegate: AnyObject {
    // Called just after the websocket handshake has successfully completed.
    func onOpen(_ conn: WebSocketConnection)

    // Called just before the underlying connection is closed.
    func onClose(_ conn: WebSocketConnection)

    // Called when a new text message has been read.
    func onReceiveMessage(_ conn: WebSocketConnection, _ message: String)
}

class WebSocketConnection {
    let conn: NWConnection
    let delegate: WebSocketDelegate
    var buffer: Data
    var awaitingClose = false

    // The maximum allowable size of a single frame.
    static let bufferSize = 1024

    init(_ conn: NWConnection, delegate: WebSocketDelegate) {
        self.conn = conn
        self.delegate = delegate
        self.buffer = Data(capacity: Self.bufferSize)
    }

    enum CloseReason: UInt16 {
        case normal = 1000
        case goingAway = 1001
        case protocolError = 1002
        case unhandledMessageType = 1003
        case invalidData = 1007
        case policyViolation = 1008
        case messageTooBig = 1009
        case internalError = 1011
    }

    // Called to close the session due to an error.
    func closeWithError(_ error: CloseReason) {

    }

    // Called to send a text message.
    func sendTextMessage(_ message: String) {
        sendMessage(.text, message.data(using: .utf8)!)
    }

    private static let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    static func startUpgrade(_ conn: HTTPConnection, _ request: HTTPRequestHead) {
        // If the upgrade header is present, start the handshake and eventually make
        // a WebSocket that takes over the underlying connection object.

        guard let key = request.getHeader("Sec-WebSocket-Key"),
              request.getHeader("Connection") == "Upgrade",
              request.getHeader("Upgrade") == "websocket",
              request.getHeader("Sec-WebSocket-Version") == "13" else {
            conn.respondWithStatus(.badRequest)
            // FIXME: need completion handler to close the connection
            return
        }

        let token = computeSHA1Digest((key + magic).data(using: .ascii)!).base64EncodedString()
        conn.respondWithStatus(.switchingProtocols,
                               extraHeaders: [("Upgrade", "websocket"),
                                              ("Connection", "Upgrade"),
                                              ("Sec-WebSocket-Accept", token)])
    }

    func read() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: Self.bufferSize - buffer.count,
                     completion: onRead)
    }

    func onRead(_ data: Data?, _ contentContext: NWConnection.ContentContext?,
                _ isComplete: Bool, _ error: NWError?) {
        guard let data = data else {
            return
        }
        buffer += data

        if let error = readFrame() {
            closeWithError(error)
        } else {
            read()
        }
    }

    func close() {
        delegate.onClose(self)
        conn.stateUpdateHandler = nil  // to release its ref to self
        conn.forceCancel()
    }

    func onStateChange(_ state: NWConnection.State) {
        if case let .failed(error) = state {
            logger.warning("connection failed: \(error)")
            self.close()
        }
    }

    enum Opcode: UInt8 {
        case text = 0x01
        case binary = 0x02
        case close = 0x08
        case ping = 0x09
        case pong = 0x0a
    }

    // Parts of the first byte of a message.
    static let fin: UInt8 = 0x80
    static let opBits: UInt8 = 0x7f

    // Parts of the second byte of a message.
    static let masked: UInt8 = 0x80
    static let lengthBits: UInt8 = 0x7f

    func readFrame() -> CloseReason? {
        guard buffer.count >= 6 else {
            // The buffer is too small to include the minimal opcode, payload
            // size, and mask.
            return nil
        }

        guard (buffer[0] & Self.fin) == Self.fin else {
            // Multi-frame messages are not supported.
            return .policyViolation
        }

        guard let opcode = Opcode(rawValue: buffer[0] & Self.opBits) else {
            return .unhandledMessageType
        }

        if (buffer[1] & Self.masked) != Self.masked {
            // The mask bit must be set in a message from the client.
            return .protocolError
        }

        var pos = 2
        var payloadLength = Int(buffer[1] & Self.lengthBits)
        if payloadLength == 126 {
            // The message contains a 16-bit extended length, which requires a total of
            // at least eight bytes.
            guard buffer.count >= 8 else {
                return nil
            }

            // Parse the extended length, which is encoded in network byte order.
            payloadLength = Int((UInt16(buffer[2]) << 8) | UInt16(buffer[3]))
            pos = 4
        } else if payloadLength == 127 {
            // A 64-bit extended length is not supported.
            return .messageTooBig
        }

        let frameSize = pos + payloadLength + 4
        guard buffer.count >= frameSize else {
            // The buffer does not yet contain the complete mask and payload.
            return frameSize <= Self.bufferSize ? nil : .messageTooBig
        }

        // Grab the mask.
        let mask = buffer[pos..<(pos + 4)]
        pos += 4

        // Apply the mask to the payload.
        var payload = buffer[pos..<(pos + payloadLength)]
        for i in 0..<payloadLength {
            payload[i] ^= mask[i % 4]
        }

        // Make sure the frame will be consumed after it is processed.
        defer { buffer.removeSubrange(0..<pos) }

        switch opcode {
        case .text:
            guard let message = String(data: payload, encoding: .utf8) else {
                return .invalidData
            }
            delegate.onReceiveMessage(self, message)
            return nil

        case .close:
            if awaitingClose {
                // This is a response to a close request sent by this side.
                close()
                return nil
            } else {
                var reason = CloseReason.normal
                if payload.count >= 2,
                   let r = CloseReason(rawValue: (UInt16(payload[0]) << 8) | UInt16(payload[1])) {
                    reason = r
                }
                return reason
            }

        case .ping:
            sendMessage(.pong, Data())
            return nil

        default:
            return .unhandledMessageType
        }
    }

    func sendMessage(_ opcode: Opcode, _ payload: Data) {
        var header = Data(capacity: 10)
        header.append(opcode.rawValue | Self.fin)
        if payload.count <= 125 {
            header.append(UInt8(payload.count))
        } else if payload.count <= 65535 {
            header.append(contentsOf: [UInt8(126),
                                       UInt8((payload.count >> 8) & 0xff),
                                       UInt8(payload.count & 0xff)])
        } else {
            fatalError("64-bit payload size not implemented")
        }

        conn.batch {
            conn.send(content: header, completion: .contentProcessed({ _ in }))
            conn.send(content: payload, completion: .contentProcessed({ _ in }))
        }
    }
}
