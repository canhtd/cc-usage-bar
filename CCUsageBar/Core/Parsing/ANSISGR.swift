import Foundation

/// Applies SGR (`ESC [ … m`) parameters to a pen cell.
///
/// Only the attributes the raw-output view renders are tracked: bold plus 8/256/truecolour
/// foreground and background. Everything else is accepted and ignored so that unknown
/// attributes never desynchronise the parameter walk.
nonisolated enum ANSISGR {
    static func apply(_ parameters: [Int], to pen: inout ANSICell) {
        var index = 0
        let values = parameters.isEmpty ? [0] : parameters
        while index < values.count {
            let code = values[index]
            switch code {
            case 0:
                pen.foreground = nil
                pen.background = nil
                pen.bold = false
            case 1: pen.bold = true
            case 22: pen.bold = false
            case 30...37: pen.foreground = ANSIColor.indexed(code - 30)
            case 90...97: pen.foreground = ANSIColor.indexed(code - 90 + 8)
            case 39: pen.foreground = nil
            case 40...47: pen.background = ANSIColor.indexed(code - 40)
            case 100...107: pen.background = ANSIColor.indexed(code - 100 + 8)
            case 49: pen.background = nil
            case 38, 48:
                let isForeground = code == 38
                let consumed = readExtendedColor(values, from: index) { color in
                    if isForeground { pen.foreground = color } else { pen.background = color }
                }
                index += consumed
            default: break
            }
            index += 1
        }
    }

    /// Reads `5;n` (256-colour) or `2;r;g;b` (truecolour) after a 38/48 introducer.
    /// Returns how many extra parameters were consumed.
    private static func readExtendedColor(
        _ values: [Int], from index: Int, assign: (ANSIColor?) -> Void
    ) -> Int {
        guard index + 1 < values.count else { return 0 }
        switch values[index + 1] {
        case 5:
            guard index + 2 < values.count else { return 1 }
            assign(ANSIColor.indexed(values[index + 2]))
            return 2
        case 2:
            guard index + 4 < values.count else { return values.count - index - 1 }
            assign(ANSIColor(byte: values[index + 2], values[index + 3], values[index + 4]))
            return 4
        default:
            return 1
        }
    }
}
