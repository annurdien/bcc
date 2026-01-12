import Foundation

@main
struct bcc {
    static func main() {

        // --- Argument Parsing ---
        let args = CommandLine.arguments
        let flags = args.filter { $0.starts(with: "--") }
        let sourceFileArgs = args.dropFirst().filter { !$0.starts(with: "--") }

        let printTokens = flags.contains("--print-tokens")
        let printAST = flags.contains("--print-ast")
        let printTACKY = flags.contains("--print-tacky")
        let printAsmAst = flags.contains("--print-asm-ast")

        guard sourceFileArgs.count == 1 else {
            printErr(
                "Usage: \(CommandLine.arguments[0]) [--print-tokens | --print-ast | --print-tacky | --print-asm-ast] <source_file.c>"
            )
            exit(1)
        }
        let filePath = sourceFileArgs[0]

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

        if printTokens {
            for token in tokens {
                print(token)
            }
            exit(0)
        }

        // MARK: - Parsing
        var parser = Parser(tokens: tokens)
        let ast: Program
        do {
            ast = try parser.parse()
        } catch let error as ParserError {
            printErr(error)
            exit(1)
        } catch {
            printErr("An unexpected parser error occurred: \(error)")
            exit(1)
        }

        if printAST {
            print(ast)
            exit(0)
        }

        // MARK: - TACKY Generation
        var tackyGenerator = TACKYGenerator()
        let tackyProgram: TackyProgram
        do {
            tackyProgram = try tackyGenerator.generate(program: ast)
        } catch let error as SemanticError {
            printErr(error)
            exit(1)
        } catch {
            printErr("An unexpected error occurred during code generation: \(error)")
            exit(1)
        }

        if printTACKY {
            print(tackyProgram)
            exit(0)
        }

        // MARK: - Assembly Generation
        let codeGenerator = AssemblyGenerator()
        let asmProgram = codeGenerator.generate(program: tackyProgram)

        if printAsmAst {
            print(asmProgram)
            exit(0)
        }

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
