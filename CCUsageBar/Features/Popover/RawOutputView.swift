import SwiftUI

/// The "Show raw output" disclosure: the terminal screen with its ANSI colours intact.
///
/// This is the debug/fallback path. It exists so that when a future Claude Code layout
/// defeats the parser, the user can still read the numbers instead of seeing nothing.
struct RawOutputView: View {
    let rows: [[ANSICell]]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Raw output")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView([.horizontal, .vertical]) {
                Text(attributed)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
            }
            .frame(height: 180)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    /// Rebuilds the screen as an `AttributedString`, coalescing runs that share attributes.
    private var attributed: AttributedString {
        var result = AttributedString()
        for (index, row) in rows.enumerated() {
            if index > 0 { result += AttributedString("\n") }
            var runText = ""
            var runCell = ANSICell.blank
            for cell in row {
                if cell.foreground != runCell.foreground || cell.bold != runCell.bold {
                    result += styled(runText, like: runCell)
                    runText = ""
                    runCell = cell
                }
                runText.append(cell.character)
            }
            result += styled(runText, like: runCell)
        }
        return result
    }

    private func styled(_ text: String, like cell: ANSICell) -> AttributedString {
        guard !text.isEmpty else { return AttributedString() }
        var piece = AttributedString(text)
        if let foreground = cell.foreground {
            piece.foregroundColor = Color(
                red: foreground.red, green: foreground.green, blue: foreground.blue)
        }
        if cell.bold { piece.inlinePresentationIntent = .stronglyEmphasized }
        return piece
    }
}
