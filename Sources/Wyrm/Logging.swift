//
// Logging.swift
// Wyrm
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import GLibc
#else
#error("unsupported runtime")
#endif

class Logger {
  enum Level: Int, Comparable {
    case debug = 0, info, warning, error, fatal

    static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  private static let levelChars: [Character] = ["D", "I", "W", "E", "F"]

  private let minLevel: Level

  init(level: Level = .info) {
    minLevel = level
  }

  func log(_ level: Level, _ message: @autoclosure () -> String,
           file: String = #fileID, line: Int = #line) {
    if level >= minLevel {
      print("\(Logger.levelChars[level.rawValue]) \(timestamp()) (\(file):\(line)) \(message())")
    }
  }

  func debug(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
    log(.debug, message(), file: file, line: line)
  }

  func info(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
    log(.info, message(), file: file, line: line)
  }

  func warning(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
    log(.warning, message(), file: file, line: line)
  }

  func error(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
    log(.error, message(), file: file, line: line)
  }

  func fatal(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
    log(.fatal, message(), file: file, line: line)
    exit(1)
  }

  private func timestamp() -> String {
    var now = timeval()
    gettimeofday(&now, nil)
    var tm = tm()
    localtime_r(&now.tv_sec, &tm)
    var buffer = [CChar](repeating: 0, count: 64)
    strftime(&buffer, buffer.count, "%m-%d %T.xxx", &tm)

    let msec = now.tv_usec / 1000;
    buffer[15] = CChar(48 + ((msec / 100) % 10))
    buffer[16] = CChar(48 + ((msec / 10) % 10))
    buffer[17] = CChar(48 + (msec % 10))

    return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
  }
}
