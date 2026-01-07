import Foundation

enum ParserError: Error, CustomStringConvertible {
    case expectedToken(String, found: Token)
    case expectedExpression(found: Token)
    case unexpectedToken(Token)
    case unsupportedUnaryOperator(Token)

    var description: String {
        switch self {
        case .expectedToken(let expected, let found):
            return "Parser Error: Expected \(expected) but found \(found)"
        case .expectedExpression(let found):
            return "Parser Error: Expected an expression but found \(found)"
        case .unexpectedToken(let found):
            return "Parser Error: Unexpected token \(found) at end of file"
        case .unsupportedUnaryOperator(let found):
            return "Parser Error: Unsupported unary operator \(found)"
        }
    }
}

struct Parser {
    let tokens: [Token]
    var currentIndex: Int = 0

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    private func peek() -> Token {
        guard currentIndex < tokens.count else {
            return tokens.last ?? .eof
        }
        return tokens[currentIndex]
    }

    @discardableResult
    private mutating func advance() -> Token {
        let token = peek()
        if token != .eof {
            currentIndex += 1
        }
        return token
    }

    @discardableResult
    private mutating func consume(_ expected: Token) throws -> Token {
        let token = peek()
        if token == expected {
            return advance()
        } else {
            throw ParserError.expectedToken(String(describing: expected), found: token)
        }
    }

    private mutating func parseExpression() throws -> Expression {
        let token = peek()

        switch token {
        case .integerLiteral(let value):
            advance()
            return .constant(value)

        case .minus:
            advance()
            let innerExp = try parseExpression()
            return .unary(.negate, innerExp)
        
        case .tilde:
            advance()
            let innerExp = try parseExpression()
            return .unary(.complement, innerExp)

        case .exclamation:
            advance()
            let innerExp = try parseExpression()
            return .unary(.logicalNot, innerExp)
        
        case .openParen:
            advance()
            let innerExp = try parseExpression()
            try consume(.closeParen)
            return innerExp
        
        case .minusMinus:
            throw ParserError.unexpectedToken(token)
        
        default:
            throw ParserError.expectedExpression(found: token)
        }
    }

    private mutating func parseStatement() throws -> Statement {
        try consume(.keywordReturn)
        let expression = try parseExpression()
        try consume(.semicolon)

        return .return(expression)
    }

    private mutating func parseFunction() throws -> FunctionDeclaration {
        try consume(.keywordInt)

        let nameToken = peek()
        guard case .identifier(let name) = nameToken else {
            throw ParserError.expectedToken("identifier", found: nameToken)
        }
        advance()

        try consume(.openParen)
        try consume(.keywordVoid)
        try consume(.closeParen)
        try consume(.openBrace)

        let body = try parseStatement()

        try consume(.closeBrace)

        return FunctionDeclaration(name: name, body: body)
    }

    mutating func parse() throws -> Program {
        let function = try parseFunction()

        guard peek() == .eof else {
            throw ParserError.unexpectedToken(peek())
        }

        return Program(function: function)
    }
}
