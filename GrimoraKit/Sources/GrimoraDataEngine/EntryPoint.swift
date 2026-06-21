import Foundation
#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@main
enum GrimoraDataEngineMain {
  static func main() async {
    setlinebuf(stdout)
    setlinebuf(stderr)

    do {
      try await CommandLineRunner().run(arguments: Array(CommandLine.arguments.dropFirst()))
    } catch {
      FileHandle.standardError.write(Data("grimora-data-engine: \(error)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }
}
