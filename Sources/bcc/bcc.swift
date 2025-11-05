import Foundation

@main
struct bcc {
    static func main() {
        guard CommandLine.arguments.count > 1 else {
            printErr("Usage: \(CommandLine.arguments[0]) <source_file.c>")
            exit(1)
        }
        let filePath = CommandLine.arguments[1]

        let sourceCode: String
        do {
            sourceCode = try String(contentsOfFile: filePath, encoding: .ascii)
        } catch {
            printErr("Error reading file: \(error.localizedDescription)")
            exit(1)
        }

        var lexer = Lexer(source: sourceCode)
        let tokens: [Token]
        do {
            tokens = try lexer.tokenize()
        } catch let error as LexerError {
            printErr(error)
            exit(1)
        } catch {
            printErr("An unexpected lexer error occurred: \(error)")
            exit(1)
        }

        var parser = Parser(tokens: tokens)
        do {
            let ast = try parser.parse()
            printErr(ast)
            exit(0)

        } catch let error as ParserError {
            printErr(error)
            exit(1)  // Exit with 1 for failure
        } catch {
            printErr("An unexpected parser error occurred: \(error)")
            exit(1)
        }
    }

    static private func printErr(_ message: Any) {
    if let data = "\(message)\n".data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}
}
