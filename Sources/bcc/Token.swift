import Foundation

enum Token: Equatable {
    // Keywords
    case keywordInt
    case keywordReturn
    case keywordVoid

    // Single character tokens
    case openParen
    case closeParen
    case openBrace
    case closeBrace
    case semicolon
    case tilde

    // One or two character tokens
    case minus
    case minusMinus

    // Tokens with associated values
    case identifier(String)
    case integerLiteral(Int)

    // Eof token
    case eof
}
