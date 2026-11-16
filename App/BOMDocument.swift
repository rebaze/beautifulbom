import SwiftUI
import UniformTypeIdentifiers

/// A read-only document: the file's bytes, untouched. Parsing happens in
/// `DocumentModel`, off the main thread.
struct BOMDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    static let writableContentTypes: [UTType] = []

    let bytes: [UInt8]

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        bytes = [UInt8](data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.featureUnsupported)
    }
}
