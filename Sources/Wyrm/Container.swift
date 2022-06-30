//
//  Container.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

protocol Container {
    var size: Size { get }
    var capacity: Int { get }
    var contents: [Entity] { get set }
}
