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
    case keywordUnsigned

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
    case percent
    case questionMark
    case colon
    case comma
    case ampersand
    case pipe
    case caret
    case ampersandAmpersand
    case pipePipe
    case equalEqual
    case exclamationEqual
    case lessThan
    case lessThanLessThan
    case lessThanEqual
    case greaterThan
    case greaterThanGreaterThan
    case greaterThanEqual
    case equal // = Assignment
    case plusEqual // +=
    case minusEqual // -=
    case starEqual // *=
    case slashEqual // /=
    case percentEqual // %=
    case ampersandEqual // &=
    case pipeEqual // |=
    case caretEqual // ^=
    case lessThanLessThanEqual // <<=
    case greaterThanGreaterThanEqual // >>=

    // One or two character tokens
    case minus

    case minusMinus
    case plusPlus

    // Tokens with associated values
    case identifier(String)
    case integerLiteral(Int)

    // Eof token
    case eof
}
