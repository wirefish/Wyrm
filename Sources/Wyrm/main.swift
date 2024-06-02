//
//  main.swift
//  Wyrm
//

let config = try! Config(contentsOfFile: "config/config.toml")

let logger = Logger(level: .debug)  // FIXME:

let world = try! World(config: config)

world.start()

let args = CommandLine.arguments
if args.count > 1 && args[1] == "repl" {
  while true {
    print(">> ", terminator: "")
    guard let s = readLine() else {
      break
    }
    let parser = Parser(scanner: Scanner(s))
    if let stmt = parser.parseSingleStatement() {
      let compiler = Compiler()
      if let fn = compiler.compileFunction(parameters: [], body: stmt, in: world.builtins) {
        do {
          print("-> \(try world.exec(fn, args: [], context: [world.builtins]))")
        } catch {
          print("error: \(error)")
        }
      }
    }
  }

} else if let server = GameServer(config) {
  server.run()
}
