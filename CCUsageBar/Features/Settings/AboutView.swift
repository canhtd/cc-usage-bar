import SwiftUI

/// Version, licence, and credit to the project this rewrite was inspired by (F8, §0).
struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "2.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("CC Usage Bar")
                .font(.title2.weight(.semibold))
            Text("Version \(version)")
                .font(.callout)
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reads Claude Code's own `/usage` output through a pseudo-terminal. It makes no network requests, reads no secrets, and never touches your Claude configuration files.")
                    Divider()
                    Text("MIT Licence.")
                    Text("Inspired by cc-usage-bar by Yilei He (MIT). This is an independent rewrite; no source was copied.")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(20)
    }
}
