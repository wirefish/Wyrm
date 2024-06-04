import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct ScriptValueMacro: AccessorMacro {
  public static func expansion(of node: AttributeSyntax,
                               providingAccessorsOf declaration: some DeclSyntaxProtocol,
                               in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
    guard let varDecl = declaration.as(VariableDeclSyntax.self),
          let patternBinding = varDecl.bindings.as(PatternBindingListSyntax.self)?.first?.as(PatternBindingSyntax.self),
          let identifier = patternBinding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
          let identifierType = patternBinding.typeAnnotation?.as(TypeAnnotationSyntax.self)?.type else {
      return []
    }

    if let wrappedType = identifierType.as(OptionalTypeSyntax.self)?.wrappedType {
      return [
        "get { \(raw: wrappedType).fromValue(self.get(\"\(raw: identifier)\")) }",
        "set { try! self.set(\"\(raw: identifier)\", to: newValue.toValue()) }"
      ]
    } else {
      guard case let .argumentList(arguments) = node.arguments,
            let defaultValue = arguments.first(where: { $0.label?.text == "default" }) else {
        return []
      }
      return [
        "get { \(raw: identifierType).fromValue(self.get(\"\(raw: identifier)\")) ?? \(defaultValue.expression) }",
        "set { try! self.set(\"\(raw: identifier)\", to: newValue.toValue()) }"
      ]
    }
  }
}

@main
struct wyrmPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    ScriptValueMacro.self,
  ]
}
