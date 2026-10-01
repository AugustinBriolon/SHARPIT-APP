import Foundation

/// A file the athlete picked, read into memory, ready to upload.
nonisolated struct FoodLogImportFile: Sendable, Equatable {
    var filename: String
    var contentType: String
    var data: Data
}

/// A `multipart/form-data` body with one file field (RFC 7578), the shape a browser's file
/// input posts. Pure, so the exact bytes the server reads can be checked.
nonisolated enum MultipartFormData {
    static func body(boundary: String, fieldName: String, file: FoodLogImportFile) -> Data {
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data(
            "Content-Disposition: form-data; name=\"\(quoted(fieldName))\"; filename=\"\(quoted(file.filename))\"\r\n".utf8
        ))
        body.append(Data("Content-Type: \(file.contentType)\r\n\r\n".utf8))
        body.append(file.data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    /// A quote or a line break in a filename would end the header early.
    private static func quoted(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\"", with: "%22")
    }
}
