import XCTest
@testable import Wyrm

final class NounPhraseTests: XCTestCase {
  // Each example is a tuple containing the string to pass to init() and the
  // corresponding article, singular, and plural.
  static let examples = [
    ("a rock", "a", "rock", "rocks"),
    ("the fox", "the", "fox", "foxes"),
    ("apple", "an", "apple", "apples"),
    ("box[es] of dirt", "a", "box of dirt", "boxes of dirt"),
    ("sarcophag[us|i]", "a", "sarcophagus", "sarcophagi"),
    ("t[oo|ee]th", "a", "tooth", "teeth"),
    ("Bob", nil, "Bob", "Bob"),
    ("_ air", nil, "air", "air")
  ]

  // Tests that construction of a NounPhrase from a String results in the expected
  // article, singular, and plural.
  func testInit() throws {
    for (phrase, article, singular, plural) in Self.examples {
      let noun = NounPhrase(phrase)
      XCTAssertEqual(noun.article, article)
      XCTAssertEqual(noun.singular, singular)
      XCTAssertEqual(noun.plural, plural)
    }
  }

  // Tests that formatting NounPhrases in various ways results in the expected String.
  func testFormat() throws {
    for (phrase, article, singular, plural) in Self.examples {
      let noun = NounPhrase(phrase)
      XCTAssertEqual(noun.format([]), singular)
      XCTAssertEqual(noun.format([.indefinite]),
                     article != nil ? "\(article!) \(singular)" : singular)
      XCTAssertEqual(noun.format([.definite]),
                     article != nil ? "the \(singular)" : singular)
      XCTAssertEqual(noun.format([.noQuantity], count: 33), plural)
      XCTAssertEqual(noun.format([.plural, .noQuantity]), plural)
      XCTAssertEqual(noun.format([.plural, .capitalized]), plural.capitalized())
      XCTAssertEqual(noun.format([.indefinite, .capitalized]),
                     article != nil ? "\(article!.capitalized()) \(singular)" :
                      singular.capitalized())
    }
  }
}
