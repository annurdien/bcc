import Foundation

@main
struct bcc {
    static func main() {
        guard CommandLine.arguments.count > 1 else {
            print("Usage: \(CommandLine.arguments[0]) <source_file.c>")
            exit(1)
        }
        let filePath = CommandLine.arguments[1]

        let sourceCode: String
        do {
            sourceCode = try String(contentsOfFile: filePath, encoding: .ascii)
        } catch {
            print("Error reading file: \(error.localizedDescription)")
            exit(1)
        }

        var lexer = Lexer(source: sourceCode)

        do {
            let tokens = try lexer.tokenize()

            for token in tokens {
                print(token)
            }

            exit(0)

        } catch let error as LexerError {
            print(error)
            exit(1)
        } catch {
            print("An unexpected error occured: \(error)")
            exit(1)
        }
    }
}
