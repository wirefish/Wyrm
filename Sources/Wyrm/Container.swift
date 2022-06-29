//
//  Container.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

protocol Container {
    var capacity: Int { get }
    var contents: [Entity] { get set }
}
