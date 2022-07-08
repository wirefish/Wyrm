//
//  WebSocket.swift
//  Wyrm
//

import Foundation
import Network

protocol WebSocketDelegate: AnyObject {
    // Called just after the websocket handshake has successfully completed.
    func onOpen(_ handler: WebSocketHandler)

    // Called just before the underlying connection is closed.
    func onClose(_ handler: WebSocketHandler)

    // Called when a new text message has been read.
    func onReceiveMessage(_ handler: WebSocketHandler, _ message: String)
}

class WebSocketHandler: TCPHandler {
    var conn: TCPConnection?
    let delegate: WebSocketDelegate
    var buffer: Data
    var awaitingClose = false

    // The maximum allowable size of a single frame.
    static let bufferSize = 1024

    init(delegate: WebSocketDelegate) {
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

    func start(_ conn: TCPConnection) {
        self.conn = conn
        conn.receive(maximumLength: Self.bufferSize, then: onRead)
        delegate.onOpen(self)
    }

    func finish(_ conn: TCPConnection) {
        delegate.onClose(self)
        self.conn = nil
    }

    // Called to close the session due to an error.
    func closeWithError(_ error: CloseReason) {
        if !awaitingClose {
            var payload = Data(repeating: 0, count: 2)
            let value = error.rawValue
            payload[0] = UInt8((value & 0xff) >> 8)
            payload[1] = UInt8(value & 0xff)
            sendMessage(.close, payload)
            awaitingClose = true
        }
    }

    // Called to send a text message.
    func sendTextMessage(_ message: String) {
        sendMessage(.text, message.data(using: .utf8)!)
    }

    private static let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    static func upgrade(_ http: HTTPHandler, _ request: HTTPRequestHead,
                        _ conn: TCPConnection) -> Bool {
        guard let key = request.getHeader("Sec-WebSocket-Key"),
              request.getHeader("Connection") == "Upgrade",
              request.getHeader("Upgrade") == "websocket",
              request.getHeader("Sec-WebSocket-Version") == "13" else {
            http.respondWithStatus(.badRequest, conn)
            return false
        }

        let token = computeSHA1Digest((key + magic).data(using: .ascii)!).base64EncodedString()
        http.respondWithStatus(.switchingProtocols,
                               extraHeaders: [("Upgrade", "websocket"),
                                              ("Connection", "Upgrade"),
                                              ("Sec-WebSocket-Accept", token)],
                               conn)
        return true
    }

    func onRead(_ data: Data, _ conn: TCPConnection) {
        buffer += data
        if let error = readFrame() {
            closeWithError(error)
        } else {
            conn.receive(maximumLength: Self.bufferSize - buffer.count, then: onRead)
        }
    }

    func close() {
        delegate.onClose(self)
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
        for i in 0..<payloadLength {
            buffer[pos + i] ^= mask[mask.startIndex + i % 4]
        }
        let payload = buffer[pos..<(pos + payloadLength)]

        // Make sure the frame will be consumed after it is processed.
        defer { buffer.removeSubrange(0..<(pos + payloadLength)) }

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
            sendMessage(.pong, nil)
            return nil

        default:
            return .unhandledMessageType
        }
    }

    func sendMessage(_ opcode: Opcode, _ payload: Data?) {
        var header = Data(capacity: 10)
        header.append(opcode.rawValue | Self.fin)
        if let payload = payload {
            if payload.count <= 125 {
                header.append(UInt8(payload.count))
            } else if payload.count <= 65535 {
                header.append(contentsOf: [UInt8(126),
                                           UInt8((payload.count >> 8) & 0xff),
                                           UInt8(payload.count & 0xff)])
            } else {
                fatalError("64-bit payload size not implemented")
            }
            conn?.send([header, payload])
        } else {
            header.append(UInt8(0))
            conn?.send(header)
        }
    }
}
