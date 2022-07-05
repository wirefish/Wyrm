//
//  File.swift
//  
//
//  Created by Craig Becker on 6/30/22.
//

import TOMLDecoder

struct Config: Codable {
    struct Server: Codable {
        let host: String
        let port: Int
    }

    struct World: Codable {
        let rootPath: String
        let avatarPrototype: String
        let databasePath: String
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
