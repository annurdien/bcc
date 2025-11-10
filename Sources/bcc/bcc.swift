import Foundation

@main
struct bcc {
    static func main() {
        // MARK: - Get the source code
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

        // MARK: - Lexing
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

        // MARK: - Parsing
        var parser = Parser(tokens: tokens)
        let ast: Program

        do {
            ast = try parser.parse()
        } catch let error as ParserError {
            printErr(error)
            exit(1)  // Exit with 1 for failure
        } catch {
            printErr("An unexpected parser error occurred: \(error)")
            exit(1)
        }

        // MARK: - ASM-AST Generator
        let codeGenerator = AssemblyAST()
        let asmProgram = codeGenerator.generate(program: ast)
        
        // MARK: - Code Emission
        let codeEmitter = CodeEmitter()
        let assemblyCode = codeEmitter.emit(program: asmProgram)

        // MARK: - Output the assembly code
        print(assemblyCode)

    }

    static private func printErr(_ message: Any) {
        if let data = "\(message)\n".data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
