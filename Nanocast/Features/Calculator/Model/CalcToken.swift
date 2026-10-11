import Foundation

enum CalcToken: Equatable, Sendable {
    case number(Double)
    case compactNumber(Double)
    case intLiteral(UInt64, base: CalcNumberBase)
    case ident(String)
    case op(CalcOperator)
    case arrow
    case comma
}
