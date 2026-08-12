import Foundation

public enum BoundedResponseError: Error, Equatable, Sendable {
    case invalidHTTPResponse
    case responseTooLarge(maximumBytes: Int)
}

/// Streams an HTTP response and stops reading once its decompressed body exceeds
/// the caller's byte budget. Content-Length is an early rejection only; the
/// streamed count remains authoritative for chunked and misleading responses.
public enum BoundedResponseLoader {
    public static func data(
        for request: URLRequest,
        in session: URLSession,
        maximumBytes: Int
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        let maximumBytes = max(1, maximumBytes)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BoundedResponseError.invalidHTTPResponse
        }
        if http.expectedContentLength > Int64(maximumBytes) {
            throw BoundedResponseError.responseTooLarge(maximumBytes: maximumBytes)
        }

        var data = Data()
        if http.expectedContentLength > 0 {
            data.reserveCapacity(min(maximumBytes, Int(http.expectedContentLength)))
        }
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else {
                throw BoundedResponseError.responseTooLarge(maximumBytes: maximumBytes)
            }
            data.append(byte)
        }
        return (data, http)
    }
}
