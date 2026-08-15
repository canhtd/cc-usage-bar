import Foundation

/// Feeds a decoded character stream into an `ANSIScreen`, honouring the escape
/// sequences Ink-based CLIs emit: cursor motion, erase, and SGR colour.
///
/// Sequences are parsed incrementally so a chunk boundary in the middle of an escape
/// sequence is handled correctly -- the partial sequence is buffered until it completes.
nonisolated final class ANSIInterpreter {
    private(set) var screen: ANSIScreen
    /// Bytes of an escape sequence seen so far but not yet terminated.
    private var partial: String = ""
    /// Escape sequences never grow past this; a stray ESC must not stall the stream.
    private static let maxPartial = 64
    /// Upper bound on how far `escapeLength` looks ahead; two more than `maxPartial` so a
    /// sequence exactly at the buffering limit is still recognised as complete.
    private static let maxScan = maxPartial + 2

    init(rows: Int, columns: Int) {
        screen = ANSIScreen(rows: rows, columns: columns)
    }

    func reset() {
        screen.reset()
        partial = ""
    }

    func resize(rows: Int, columns: Int) {
        screen = ANSIScreen(rows: rows, columns: columns)
        partial = ""
    }

    func feed(_ text: String) {
        var input = Substring(partial + text)
        partial = ""
        while let character = input.first {
            if character == "\u{1B}" {
                switch Self.escapeLength(in: input) {
                case .complete(let length):
                    apply(String(input.prefix(length)))
                    input = input.dropFirst(length)
                case .incomplete:
                    if input.count <= Self.maxPartial {
                        partial = String(input)
                        return
                    }
                    input = input.dropFirst()  // give up on an over-long sequence
                }
                continue
            }
            input = input.dropFirst()
            handleControlOrText(character)
        }
    }

    /// Dispatches on Unicode scalars, not `Character`s.
    ///
    /// Swift folds CR+LF into a single grapheme cluster, so a `Character`-level switch
    /// silently drops every line break in a stream that uses `\r\n` and writes the
    /// cluster as text instead.
    private func handleControlOrText(_ character: Character) {
        let scalars = character.unicodeScalars
        if let first = scalars.first, first.value < 0x20 || first.value == 0x7F {
            for scalar in scalars { handleControl(scalar) }
            return
        }
        screen.write(character)
    }

    private func handleControl(_ scalar: Unicode.Scalar) {
        switch scalar {
        case "\r": screen.carriageReturn()
        case "\n": screen.lineFeed()
        case "\u{08}": screen.moveRelative(rows: 0, columns: -1)
        case "\t": screen.move(row: screen.cursorRow, column: (screen.cursorColumn / 8 + 1) * 8)
        default: break  // bell, charset shifts, NUL, DEL and other C0 codes: no effect
        }
    }

    private enum EscapeLength {
        case complete(Int)
        case incomplete
    }

    /// Length of the escape sequence starting at the head of `input`, if it is terminated.
    ///
    /// Walks indices instead of materialising `Array(input)`. The old version copied the
    /// whole remaining chunk on every ESC, which is quadratic in the number of escapes --
    /// and Ink emits one every few characters, on the main actor.
    ///
    /// Only the first `maxScan` characters are ever examined. Every sequence this parser
    /// understands is far shorter than that, and `feed` already abandons anything longer,
    /// so the bound costs nothing and keeps a stray ESC from scanning a 16 KB chunk.
    private static func escapeLength(in input: Substring) -> EscapeLength {
        let end = input.index(input.startIndex, offsetBy: maxScan, limitedBy: input.endIndex)
            ?? input.endIndex
        let second = input.index(after: input.startIndex)
        guard second < end else { return .incomplete }

        func value(at index: Substring.Index) -> UInt32? {
            input[index].unicodeScalars.first?.value
        }

        switch input[second] {
        case "[":
            var index = input.index(after: second)
            while index < end, let scalar = value(at: index), (0x30...0x3F).contains(scalar) {
                index = input.index(after: index)  // parameter bytes
            }
            while index < end, let scalar = value(at: index), (0x20...0x2F).contains(scalar) {
                index = input.index(after: index)  // intermediate bytes
            }
            guard index < end else { return .incomplete }
            return .complete(input.distance(from: input.startIndex, to: index) + 1)
        case "]":  // OSC, terminated by BEL or ST
            var index = input.index(after: second)
            while index < end {
                if input[index] == "\u{07}" {
                    return .complete(input.distance(from: input.startIndex, to: index) + 1)
                }
                let next = input.index(after: index)
                if input[index] == "\u{1B}", next < end, input[next] == "\\" {
                    return .complete(input.distance(from: input.startIndex, to: index) + 2)
                }
                index = next
            }
            return .incomplete
        case "(", ")", "*", "+", "#", "%":
            return input.index(after: second) < end ? .complete(3) : .incomplete
        default:
            return .complete(2)
        }
    }

    private func apply(_ sequence: String) {
        let characters = Array(sequence)
        guard characters.count >= 2 else { return }
        switch characters[1] {
        case "[": applyCSI(Array(characters.dropFirst(2)))
        case "7": screen.saveCursor()
        case "8": screen.restoreCursor()
        case "M": screen.moveRelative(rows: -1, columns: 0)
        case "D": screen.lineFeed()
        case "E":
            screen.lineFeed()
            screen.carriageReturn()
        case "c": screen.reset()
        default: break  // charset selection, keypad modes: no effect on layout
        }
    }

    private func applyCSI(_ body: [Character]) {
        guard let final = body.last else { return }
        let parameterText = String(body.dropLast())
        // Private-use sequences (`ESC [ ? …`, `ESC [ > …`) are terminal capability
        // negotiation such as kitty keyboard flags; they must not be read as SGR.
        if let first = parameterText.first, "<=>?".contains(first) {
            return
        }
        let parameters = parameterText.split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
        let first = parameters.first ?? 0
        let count = max(1, first)
        switch final {
        case "A": screen.moveRelative(rows: -count, columns: 0)
        case "B": screen.moveRelative(rows: count, columns: 0)
        case "C": screen.moveRelative(rows: 0, columns: count)
        case "D": screen.moveRelative(rows: 0, columns: -count)
        case "E": screen.move(row: screen.cursorRow + count, column: 0)
        case "F": screen.move(row: screen.cursorRow - count, column: 0)
        case "G", "`": screen.move(row: screen.cursorRow, column: count - 1)
        case "d": screen.move(row: count - 1, column: screen.cursorColumn)
        case "H", "f":
            let row = max(1, parameters.first ?? 1)
            let column = parameters.count > 1 ? max(1, parameters[1]) : 1
            screen.move(row: row - 1, column: column - 1)
        case "J": screen.eraseInDisplay(mode: first)
        case "K": screen.eraseInLine(mode: first)
        case "s": screen.saveCursor()
        case "u": screen.restoreCursor()
        case "m": ANSISGR.apply(parameters, to: &screen.pen)
        default: break
        }
    }
}
