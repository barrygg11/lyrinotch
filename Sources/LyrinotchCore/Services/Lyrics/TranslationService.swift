import Foundation

/// Optional line translation (free MyMemory public endpoint; best-effort).
public actor TranslationService {
    public static let shared = TranslationService()

    private var cache: [String: String] = [:]
    private let session: URLSession
    private let maximumResponseBytes: Int

    public init(
        session: URLSession = .shared,
        maximumResponseBytes: Int = 128_000
    ) {
        self.session = session
        self.maximumResponseBytes = max(1, maximumResponseBytes)
    }

    public func clearCache() {
        cache.removeAll(keepingCapacity: false)
    }

    /// Translate a short lyric line. Empty / already-target-ish text returns nil.
    public func translate(
        _ text: String,
        to targetLang: String
    ) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 400 else { return nil }
        let target = targetLang.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty,
              target.count <= 16,
              target.allSatisfy({
                  $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
              })
        else { return nil }

        let key = "\(target)|\(trimmed)"
        if let cached = cache[key] { return cached }

        // Detect rough source: ja if kana, zh if CJK, else auto.
        let source: String
        if TrackQueryNormalizer.looksJapanese(trimmed) {
            source = "ja"
        } else if TrackQueryNormalizer.containsCJKIdeograph(trimmed) {
            source = "zh-CN"
        } else {
            source = "en"
        }
        if source == target || (source.hasPrefix("zh") && target.hasPrefix("zh")) {
            return nil
        }

        var components = URLComponents(string: "https://api.mymemory.translated.net/get")
        components?.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "langpair", value: "\(source)|\(target)")
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Lyrinotch/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let loaded = try await BoundedResponseLoader.data(
                for: request,
                in: session,
                maximumBytes: maximumResponseBytes
            )
            let data = loaded.data
            let http = loaded.response
            guard
                  http.url?.scheme?.lowercased() == "https",
                  (200..<300).contains(http.statusCode),
                  http.expectedContentLength <= 0
                    || http.expectedContentLength <= Int64(maximumResponseBytes),
                  data.count <= maximumResponseBytes,
                  !Task.isCancelled
            else {
                return nil
            }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let resp = json["responseData"] as? [String: Any],
                let translated = resp["translatedText"] as? String
            else { return nil }

            let out = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !out.isEmpty, out.lowercased() != trimmed.lowercased() else { return nil }
            // MyMemory free tier may return quota messages — ignore those.
            if out.localizedCaseInsensitiveContains("MYMEMORY WARNING") { return nil }
            cache[key] = out
            if cache.count > 200 {
                cache.removeAll(keepingCapacity: true)
            }
            return out
        } catch {
            return nil
        }
    }
}
