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
        let tokens: [Token]
        do {
            tokens = try lexer.tokenize()
        } catch let error as LexerError {
            print(error)
            exit(1)
        } catch {
            print("An unexpected lexer error occurred: \(error)")
            exit(1)
        }

        var parser = Parser(tokens: tokens)
        do {
            let ast = try parser.parse()
            print(ast)
            exit(0)

        } catch let error as ParserError {
            print(error)
            exit(1)
        } catch {
            print("An unexpected parser error occurred: \(error)")
            exit(1)
        }
    }
}
