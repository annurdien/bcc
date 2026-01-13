import Foundation

enum Token: Equatable {
    // Keywords
    case keywordInt
    case keywordLong
    case keywordReturn
    case keywordVoid
    case keywordIf
    case keywordElse
    case keywordDo
    case keywordWhile
    case keywordFor
    case keywordBreak
    case keywordContinue
    case keywordStatic

    // Single character tokens
    case openParen
    case closeParen
    case openBrace
    case closeBrace
    case semicolon
    case tilde
    case exclamation
    case plus
    case star
    case slash
    case questionMark
    case colon
    case comma
    case ampersandAmpersand
    case pipePipe
    case equalEqual
    case exclamationEqual
    case lessThan
    case lessThanEqual
    case greaterThan
    case greaterThanEqual
    case equal // = Assignment

    // One or two character tokens
    case minus

    case minusMinus

    // Tokens with associated values
    case identifier(String)
    case integerLiteral(Int)

    // Eof token
    case eof
}
