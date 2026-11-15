import BOMCore
import SwiftUI

/// What is wrong with the file, in plain words, each with its position;
/// a click reveals the exact range. The rest of the document stays navigable.
struct DiagnosticsBanner: View {
    @Bindable var model: DocumentModel
    let diagnostics: [Diagnostic]

    private var errors: Int { diagnostics.count { $0.severity == .error } }
    private var warnings: Int { diagnostics.count - errors }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                model.showDiagnostics.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: errors > 0 ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(errors > 0 ? .red : .yellow)
                    Text(summary).fontWeight(.medium)
                    Text(errors > 0 ? "The file is not valid JSON. Everything that could be read is shown." : "The file is valid JSON with irregularities.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(model.showDiagnostics ? 0 : -90))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityLabel("\(summary). \(model.showDiagnostics ? "Hide" : "Show") details")

            if model.showDiagnostics, let source = model.source {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, d in
                            let position = source.lineColumn(of: d.range.lowerBound)
                            Button {
                                model.reveal(d)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Image(systemName: d.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(d.severity == .error ? .red : .yellow)
                                    Text("\(position.line):\(position.column)")
                                        .font(.system(.callout, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(minWidth: 64, alignment: .trailing)
                                    Text(d.message)
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 3)
                            .help("Reveal in source")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 140)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
        .background(errors > 0 ? Color.red.opacity(0.06) : Color.yellow.opacity(0.08))
    }

    private var summary: String {
        [errors > 0 ? "\(errors) \(errors == 1 ? "error" : "errors")" : nil,
         warnings > 0 ? "\(warnings) \(warnings == 1 ? "warning" : "warnings")" : nil]
            .compactMap { $0 }.joined(separator: ", ")
    }
}
