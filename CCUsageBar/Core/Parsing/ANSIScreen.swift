import Foundation

/// A character cell with the subset of SGR attributes worth rendering.
nonisolated struct ANSICell: Equatable, Sendable {
    var character: Character = " "
    var foreground: ANSIColor?
    var background: ANSIColor?
    var bold: Bool = false

    static let blank = ANSICell()
    var isBlank: Bool { self == .blank }
}

/// An RGB colour resolved from an SGR sequence.
nonisolated struct ANSIColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(byte r: Int, _ g: Int, _ b: Int) {
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    /// The 16 standard ANSI colours plus the 6x6x6 cube and greyscale ramp of 256-colour mode.
    static func indexed(_ index: Int) -> ANSIColor? {
        switch index {
        case 0..<16:
            let base: [(Int, Int, Int)] = [
                (0, 0, 0), (170, 0, 0), (0, 170, 0), (170, 85, 0),
                (0, 0, 170), (170, 0, 170), (0, 170, 170), (170, 170, 170),
                (85, 85, 85), (255, 85, 85), (85, 255, 85), (255, 255, 85),
                (85, 85, 255), (255, 85, 255), (85, 255, 255), (255, 255, 255),
            ]
            let c = base[index]
            return ANSIColor(byte: c.0, c.1, c.2)
        case 16..<232:
            let n = index - 16
            let ramp = [0, 95, 135, 175, 215, 255]
            return ANSIColor(byte: ramp[n / 36], ramp[(n / 6) % 6], ramp[n % 6])
        case 232..<256:
            let level = 8 + (index - 232) * 10
            return ANSIColor(byte: level, level, level)
        default:
            return nil
        }
    }
}

/// A fixed-size virtual terminal screen.
///
/// Claude Code's Ink renderer repaints differentially: it moves the cursor with
/// `ESC [ n G` / `ESC [ n B` and overwrites only the characters that changed. Stripping
/// escape codes from the raw byte stream therefore produces garbage such as
/// `these are indepndnt characteristics`. Replaying the stream onto this grid and then
/// reading the grid back is the only way to recover the text the user actually sees.
nonisolated struct ANSIScreen: Sendable {
    let rows: Int
    let columns: Int
    private(set) var grid: [[ANSICell]]
    private(set) var cursorRow = 0
    private(set) var cursorColumn = 0
    var pen = ANSICell()
    private var savedCursor: (row: Int, column: Int)?

    init(rows: Int, columns: Int) {
        self.rows = max(1, rows)
        self.columns = max(1, columns)
        self.grid = Array(repeating: Array(repeating: ANSICell.blank, count: self.columns), count: self.rows)
    }

    mutating func reset() {
        grid = Array(repeating: Array(repeating: ANSICell.blank, count: columns), count: rows)
        cursorRow = 0
        cursorColumn = 0
        pen = ANSICell()
        savedCursor = nil
    }

    // MARK: - Cursor

    mutating func move(row: Int, column: Int) {
        cursorRow = min(max(row, 0), rows - 1)
        cursorColumn = min(max(column, 0), columns - 1)
    }

    mutating func moveRelative(rows deltaRows: Int, columns deltaColumns: Int) {
        move(row: cursorRow + deltaRows, column: cursorColumn + deltaColumns)
    }

    mutating func carriageReturn() { cursorColumn = 0 }

    mutating func saveCursor() { savedCursor = (cursorRow, cursorColumn) }

    mutating func restoreCursor() {
        if let saved = savedCursor { move(row: saved.row, column: saved.column) }
    }

    /// Moves to the next line, scrolling the grid up when the cursor is on the last row.
    mutating func lineFeed() {
        if cursorRow >= rows - 1 {
            grid.removeFirst()
            grid.append(Array(repeating: ANSICell.blank, count: columns))
        } else {
            cursorRow += 1
        }
    }

    // MARK: - Writing

    mutating func write(_ character: Character) {
        if cursorColumn >= columns {
            cursorColumn = columns - 1
        }
        var cell = pen
        cell.character = character
        grid[cursorRow][cursorColumn] = cell
        cursorColumn += 1
    }

    // MARK: - Erasing

    /// `ESC [ n K` -- 0: to end of line, 1: to start of line, 2: whole line.
    mutating func eraseInLine(mode: Int) {
        let range: Range<Int>
        switch mode {
        case 1: range = 0..<min(cursorColumn + 1, columns)
        case 2: range = 0..<columns
        default: range = min(cursorColumn, columns)..<columns
        }
        for column in range { grid[cursorRow][column] = .blank }
    }

    /// `ESC [ n J` -- 0: to end of screen, 1: to start of screen, 2/3: whole screen.
    mutating func eraseInDisplay(mode: Int) {
        switch mode {
        case 1:
            for row in 0..<cursorRow { grid[row] = Array(repeating: .blank, count: columns) }
            eraseInLine(mode: 1)
        case 2, 3:
            grid = Array(repeating: Array(repeating: .blank, count: columns), count: rows)
        default:
            eraseInLine(mode: 0)
            for row in (cursorRow + 1)..<rows { grid[row] = Array(repeating: .blank, count: columns) }
        }
    }

    // MARK: - Reading back

    /// The visible text, one line per row, with trailing blanks trimmed.
    var text: String {
        grid.map { row in
            String(row.map(\.character)).replacingOccurrences(
                of: "\\s+$", with: "", options: .regularExpression)
        }.joined(separator: "\n")
    }

    /// Rows trimmed to the last non-blank one, for compact raw display.
    var trimmedRows: [[ANSICell]] {
        var result = grid
        while let last = result.last, last.allSatisfy(\.isBlank) { result.removeLast() }
        return result
    }
}
