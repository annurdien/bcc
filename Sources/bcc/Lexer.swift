import Foundation

enum LexerError: Error, CustomStringConvertible {
    case unrecognizedToken(near: String)

    var description: String {
        switch self {
        case .unrecognizedToken(let near):
            return "Unrecognized token near: \(near)"
        }
    }
}

struct Lexer {
    let source: String
    var currentIndex: String.Index

    init(source: String) {
        self.source = source
        self.currentIndex = source.startIndex
    }

    private var isAtEnd: Bool {
        currentIndex >= source.endIndex
    }

    private func peek() -> Character? {
        guard !isAtEnd else { return nil }
        return source[currentIndex]
    }

    @discardableResult
    private mutating func advance() -> Character? {
        guard !isAtEnd else { return nil }
        let char = source[currentIndex]
        currentIndex = source.index(after: currentIndex)
        return char
    }

    mutating func tokenize() throws -> [Token] {
        var tokens: [Token] = []

        while !isAtEnd {
            let tokenStart = currentIndex

            if let char = peek(), char.isWhitespace {
                advance()
                continue
            }
            
            // Handle single-line comments //
            if source[currentIndex] == "/" {
                let nextIndex = source.index(after: currentIndex)
                if nextIndex < source.endIndex && source[nextIndex] == "/" {
                    // Consume until newline
                    while !isAtEnd && peek() != "\n" {
                         advance()
                    }
                    continue
                }
            }

            if let token = scanNextToken() {
                tokens.append(token)
            } else {
                let remaining = source[tokenStart...]
                let snippet = String(remaining.prefix(10))
                throw LexerError.unrecognizedToken(near: snippet)
            }
        }
        
        tokens.append(.eof)

        return tokens
    }

    private mutating func scanNextToken() -> Token? {
        guard let char = peek() else { return nil }

        switch char {
        case "(":
            advance()
            return .openParen
        case ")":
            advance()
            return .closeParen
        case "{":
            advance()
            return .openBrace
        case "}":
            advance()
            return .closeBrace
        case ";":
            advance()
            return .semicolon
        case "~":
            advance()
            return .tilde
        case "!":
            advance()
            if peek() == "=" {
                advance()
                return .exclamationEqual
            }
            return .exclamation
        case ":":
            advance()
            return .colon        case ",":
             advance()
             return .comma        case "?":
            advance()
            return .questionMark
        case "+":
            advance()
            return .plus
        case "*":
            advance()
            return .star
        case "/":
            advance()
            if peek() == "/" {
                // Single-line comment: consume until newline
                while let char = peek(), char != "\n" {
                    advance()
                }
                
                // Consumed comment. Now we might be at \n.
                // We need to skip any whitespace (including the newline we just hit)
                // before scanning the next token, because scanNextToken() doesn't handle whitespace.
                while let char = peek(), char.isWhitespace {
                    advance()
                }
                
                // Now recurse
                return scanNextToken()
            }
            return .slash
        case "%":
            advance()
            return .percent
        case "&":
            advance()
            if peek() == "&" {
                advance()
                return .ampersandAmpersand
            }
            return .ampersand
        case "|":
            advance()
            if peek() == "|" {
                advance()
                return .pipePipe
            }
            return .pipe
        case "^":
            advance()
            return .caret
        case "=":
            advance()
            if peek() == "=" {
                advance()
                return .equalEqual
            }
            return .equal
        case "<":
            advance()
            if peek() == "=" {
                advance()
                return .lessThanEqual
            } else if peek() == "<" {
                advance()
                return .lessThanLessThan
            }
            return .lessThan
        case ">":
            advance()
            if peek() == "=" {
                advance()
                return .greaterThanEqual
            } else if peek() == ">" {
                advance()
                return .greaterThanGreaterThan
            }
            return .greaterThan
        case "-":
            advance()

            if let nextChar = peek(), nextChar == "-" {
                advance()
                return .minusMinus
            } else {
                return .minus
            }

        default:
            if char.isLetter || char == "_" {
                return scanIdentifierOrKeyword()
            }

            if char.isNumber {
                return scanNumber()
            }

            return nil
        }
    }

    private mutating func scanIdentifierOrKeyword() -> Token {
        let startIndex = currentIndex

        while let char = peek(), char.isLetter || char.isNumber || char == "_" {
            advance()
        }

        let identifierString = String(source[startIndex..<currentIndex])

        switch identifierString {
        case "int": return .keywordInt
        case "long": return .keywordLong
        case "return": return .keywordReturn
        case "void": return .keywordVoid
        case "if": return .keywordIf
        case "else": return .keywordElse
        case "do": return .keywordDo
        case "while": return .keywordWhile
        case "for": return .keywordFor
        case "break": return .keywordBreak
        case "continue": return .keywordContinue
        case "static": return .keywordStatic
        case "unsigned": return .keywordUnsigned
        default: return .identifier(identifierString)
        }
    }

    private mutating func scanNumber() -> Token? {
        let startIndex = currentIndex

        while let char = peek(), char.isNumber {
            advance()
        }

        if let char = peek(), char.isLetter || char == "_" {
            return nil
        }

        let numberString = String(source[startIndex..<currentIndex])

        if let value = Int(numberString) {
            return .integerLiteral(value)
        } else {
            return nil
        }
    }
}
