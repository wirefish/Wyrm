//
//  File.swift
//
//

import TOMLDecoder

struct Config: Codable {
  struct Server: Codable {
    let port: UInt16
  }

  struct World: Codable {
    let rootPath: String
    let databasePath: String
    let avatarPrototype: Ref
    let startLocation: Ref
  }

  let server: Server
  let world: World

  init(contentsOfFile path: String) throws {
    let decoder = TOMLDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    self = try decoder.decode(
      Config.self,
      from: try String(contentsOfFile: path, encoding: .utf8))
  }
}
