import Foundation
import Testing

@testable import CCUsageBar

/// R2: the virtual screen has to reconstruct text that Ink only ever wrote differentially.
@Suite("ANSI virtual screen")
struct ANSIScreenTests {
    private func render(_ input: String, rows: Int = 4, columns: Int = 40) -> [String] {
        let interpreter = ANSIInterpreter(rows: rows, columns: columns)
        interpreter.feed(input)
        return interpreter.screen.text.components(separatedBy: "\n")
    }

    @Test("Cursor column addressing overwrites in place")
    func columnAbsolute() {
        // This is exactly the shape Ink emits when only two characters changed.
        let lines = render("these are indepe\u{1B}[17Gdent\r\u{1B}[1Gthose")
        #expect(lines[0] == "those are indepedent")
    }

    @Test("A differential repaint recovers the visible text")
    func differentialRepaint() {
        let lines = render("Last 24h \u{1B}[1Gxxxx\u{1B}[6G report")
        #expect(lines[0] == "xxxx  report")
    }

    @Test("Erase in line clears to the end")
    func eraseInLine() {
        let lines = render("abcdefgh\r\u{1B}[4C\u{1B}[K")
        #expect(lines[0] == "abcd")
    }

    @Test("Erase in display clears everything")
    func eraseInDisplay() {
        let lines = render("abc\ndef\u{1B}[2J")
        #expect(lines.joined().isEmpty)
    }

    @Test("Relative cursor motion addresses the right row")
    func relativeMotion() {
        let lines = render("\u{1B}[2B\u{1B}[5Ghere")
        #expect(lines[0].isEmpty)
        #expect(lines[2] == "    here")
    }

    @Test("Absolute positioning uses one-based coordinates")
    func absolutePositioning() {
        let lines = render("\u{1B}[2;3Hxy")
        #expect(lines[1] == "  xy")
    }

    @Test("Writing past the last row scrolls instead of dropping text")
    func scrolls() {
        let lines = render("one\r\ntwo\r\nthree\r\nfour\r\nfive", rows: 3)
        #expect(lines == ["three", "four", "five"])
    }

    @Test("Private-mode sequences are consumed and never read as SGR")
    func privateSequencesIgnored() {
        let interpreter = ANSIInterpreter(rows: 2, columns: 20)
        interpreter.feed("\u{1B}[?2026h\u{1B}[>4;2m\u{1B}[<u\u{1B}[>1uPLAIN")
        #expect(interpreter.screen.text.components(separatedBy: "\n")[0] == "PLAIN")
        #expect(interpreter.screen.pen.bold == false)
        #expect(interpreter.screen.pen.foreground == nil)
    }

    @Test("Truecolour and bold reach the pen; reset clears them")
    func sgrAttributes() {
        let interpreter = ANSIInterpreter(rows: 1, columns: 20)
        interpreter.feed("\u{1B}[1m\u{1B}[38;2;177;185;249mX")
        #expect(interpreter.screen.pen.bold)
        #expect(interpreter.screen.pen.foreground == ANSIColor(byte: 177, 185, 249))
        interpreter.feed("\u{1B}[0mY")
        #expect(interpreter.screen.pen.bold == false)
        #expect(interpreter.screen.pen.foreground == nil)
    }

    @Test("256-colour and 8-colour codes resolve")
    func indexedColours() {
        let interpreter = ANSIInterpreter(rows: 1, columns: 10)
        interpreter.feed("\u{1B}[38;5;196mA")
        #expect(interpreter.screen.pen.foreground == ANSIColor.indexed(196))
        interpreter.feed("\u{1B}[31mB")
        #expect(interpreter.screen.pen.foreground == ANSIColor.indexed(1))
    }

    @Test("An escape sequence split across feeds is still applied")
    func splitEscapeSequence() {
        let interpreter = ANSIInterpreter(rows: 1, columns: 20)
        interpreter.feed("abcdef\r\u{1B}[")
        interpreter.feed("3GZ")
        #expect(interpreter.screen.text.components(separatedBy: "\n")[0] == "abZdef")
    }

    @Test("CR+LF is treated as two controls, not as one printable grapheme")
    func carriageReturnLineFeed() {
        // Swift folds "\r\n" into a single Character; a Character-level switch would write
        // it to the screen and lose every line break.
        let lines = render("alpha\r\nbeta", rows: 3)
        #expect(lines[0] == "alpha")
        #expect(lines[1] == "beta")
    }

    @Test("Exit status decoding matches WIFEXITED / WEXITSTATUS")
    func exitStatusDecoding() {
        #expect(PTYProcess.exitCode(from: 127 << 8) == 127)
        #expect(PTYProcess.exitCode(from: 0) == 0)
        #expect(PTYProcess.exitCode(from: SIGKILL) == -SIGKILL)
    }

    @Test("OSC title sequences are swallowed whole")
    func oscIgnored() {
        let lines = render("\u{1B}]0;some window title\u{07}VISIBLE")
        #expect(lines[0] == "VISIBLE")
    }
}
