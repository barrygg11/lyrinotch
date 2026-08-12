import CoreFoundation
import Foundation

/// Builds alternate artist/title queries so LRCLIB can match messy player metadata.
///
/// Apple Music / Spotify often use **Traditional Chinese** titles; LRCLIB frequently
/// indexes the **Simplified** form (or YouTube-style blobs). We emit both.
public enum TrackQueryNormalizer {
    /// Ordered unique query pairs to try (most specific first).
    static func artistTitleVariants(artist: String, title: String) -> [(artist: String, title: String)] {
        let titles = titleVariants(title)
        let artists = artistVariants(artist)
        var pairs: [(String, String)] = []
        var seen = Set<String>()

        for a in artists {
            for t in titles {
                let key = "\(a.lowercased())|\(t.lowercased())"
                if seen.insert(key).inserted {
                    pairs.append((a, t))
                }
            }
        }
        return pairs
    }

    static func freeTextQueries(artist: String, title: String) -> [String] {
        let t = primaryTitle(title)
        let a = primaryArtist(artist)
        let aNoUS = primaryArtist(artist.replacingOccurrences(of: "_", with: " "))
        let japanese = looksJapanese(t) || looksJapanese(a)
        // Artist+title first — title-only last (same title ≠ same song).
        var queries = [
            "\(a) \(t)",
            "\(aNoUS) \(t)",
            t
        ]
        // Hans mirrors only for Chinese (not Japanese) metadata.
        if !japanese {
            let tSim = simplifiedChinese(t)
            let aSim = simplifiedChinese(a)
            queries.insert("\(aSim) \(tSim)", at: 2)
            queries.append(tSim)
            if tSim != t {
                queries.insert("\(a) \(tSim)", at: 2)
            }
        }
        var seen = Set<String>()
        return queries.compactMap { q in
            let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard seen.insert(trimmed.lowercased()).inserted else { return nil }
            return trimmed
        }
    }

    static func primaryArtist(_ artist: String) -> String {
        artistVariants(artist).first ?? artist
    }

    static func primaryTitle(_ title: String) -> String {
        let variants = titleVariants(title)
        // Prefer a form without drama / live parentheticals for matching.
        if let core = variants.first(where: {
            !$0.contains("(") && !$0.contains("（") && !$0.contains("【") && !$0.contains("[")
        }) {
            return core
        }
        return variants.first ?? title
    }

    /// Loose equality for scoring search hits against player metadata.
    static func artistsLooselyMatch(_ a: String, _ b: String) -> Bool {
        let x = fold(a)
        let y = fold(b)
        if x.isEmpty || y.isEmpty { return false }
        if x == y { return true }
        if x.contains(y) || y.contains(x) {
            let shorter = min(x.count, y.count)
            let longer = max(x.count, y.count)
            // Avoid treating generic suffixes such as “Artist” as a match for
            // “Different Artist”, while keeping “The Beatles” ↔ “Beatles”.
            if shorter >= 4, Double(shorter) / Double(longer) >= 0.6 {
                return true
            }
        }
        // Token overlap (handles "马也Crabbit" vs "马也_Crabbit - Topic")
        let xt = Set(tokens(x))
        let yt = Set(tokens(y))
        return !xt.isEmpty && !yt.isEmpty && !xt.isDisjoint(with: yt)
    }

    /// Title affinity score 0…50 for ranking LRCLIB hits.
    static func titleMatchScore(want: String, candidate: String) -> Int {
        // Prefer core title (strip (Live) / TV drama tails) then compare with 繁簡 fold.
        let w = primaryTitle(want).trimmingCharacters(in: .whitespacesAndNewlines)
        let cCore = primaryTitle(candidate).trimmingCharacters(in: .whitespacesAndNewlines)
        let c = cCore.isEmpty
            ? candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            : cCore
        guard !w.isEmpty, !c.isEmpty else { return 0 }

        let wl = w.lowercased()
        let cl = c.lowercased()
        if wl == cl { return 50 }

        let wf = fold(w)
        let cf = fold(c)
        if wf == cf { return 48 }

        // Prefix / contains on **folded** strings so 繁體 want matches 简体 LRCLIB titles.
        let minLen = min(wf.count, cf.count)
        if minLen >= 4, cf == wf || cf.hasPrefix(wf) || wf.hasPrefix(cf) {
            return 42
        }
        if minLen >= 4, cf.contains(wf) || wf.contains(cf) {
            // Slightly lower than pure prefix; still above token-only noise.
            return 36
        }
        if minLen >= 4 {
            let wt = Set(tokens(wf))
            let ct = Set(tokens(cf))
            if !wt.isEmpty, !ct.isEmpty, !wt.isDisjoint(with: ct) {
                return 18
            }
        }
        return 0
    }

    // MARK: - Private

    private static func artistVariants(_ artist: String) -> [String] {
        var list: [String] = []
        let raw = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return list }

        list.append(raw)

        var cleaned = raw
        let suffixes = [" - Topic", " - topic", " Topic", " – Topic"]
        for s in suffixes {
            if let r = cleaned.range(of: s, options: .caseInsensitive) {
                cleaned = String(cleaned[..<r.lowerBound])
            }
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty { list.append(cleaned) }

        let noUnderscore = cleaned.replacingOccurrences(of: "_", with: "")
        if !noUnderscore.isEmpty { list.append(noUnderscore) }

        let spacedUnderscore = cleaned.replacingOccurrences(of: "_", with: " ")
        if !spacedUnderscore.isEmpty { list.append(spacedUnderscore) }

        // First artist before comma / & / feat.
        for sep in [",", " & ", " feat.", " ft.", " featuring ", "／", "/"] {
            if let r = cleaned.range(of: sep, options: .caseInsensitive) {
                let first = String(cleaned[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !first.isEmpty { list.append(first) }
            }
        }

        // Simplified Chinese forms for LRCLIB (Chinese only — skip Japanese).
        if !list.contains(where: looksJapanese) {
            let beforeSim = list.count
            for i in 0..<beforeSim {
                let sim = simplifiedChinese(list[i])
                if sim != list[i] { list.append(sim) }
            }
        }

        return unique(list)
    }

    private static func titleVariants(_ title: String) -> [String] {
        var list: [String] = []
        let raw = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return list }
        list.append(raw)

        // Strip common suffixes: (Live), 【官方】, - Radio Edit, TV 主題曲 parenthesis, etc.
        let stripped = raw
        if let r = stripped.range(of: " - ") {
            let head = String(stripped[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !head.isEmpty { list.append(head) }
        }
        // Remove bracketed tails (half- and full-width)
        for pattern in [#"\s*[\(（].*[\)）]\s*$"#, #"\s*[\【\[].*[\]\】]\s*$"#] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(stripped.startIndex..., in: stripped)
                let next = regex.stringByReplacingMatches(in: stripped, range: range, withTemplate: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !next.isEmpty { list.append(next) }
            }
        }

        // Simplified Chinese mirrors (LRCLIB often indexes Hans for Chinese catalog).
        // Do not manufacture Hans variants of Japanese titles.
        if !list.contains(where: looksJapanese) {
            let beforeSimCount = list.count
            for i in 0..<beforeSimCount {
                let sim = simplifiedChinese(list[i])
                if sim != list[i] { list.append(sim) }
            }
        }

        return unique(list)
    }

    private static func fold(_ s: String) -> String {
        // Normalize 繁/簡 so "單依純" matches "单依纯" in scoring.
        simplifiedChinese(s)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "–", with: "")
            .replacingOccurrences(of: "topic", with: "")
    }

    /// Traditional → Simplified via ICU (macOS). No-op for non-CJK / Japanese.
    public static func simplifiedChinese(_ string: String) -> String {
        // Never run 繁簡 on Japanese — ICU mangles kana-adjacent text and hurts matching.
        if looksJapanese(string) { return string }
        let mutable = NSMutableString(string: string)
        CFStringTransform(mutable, nil, "Traditional-Simplified" as CFString, false)
        return mutable as String
    }

    /// Simplified → Traditional via ICU (macOS). Used for display when the user
    /// prefers 繁體中文 while LRCLIB often returns 简体.
    /// Leaves Japanese (and pure Latin) untouched.
    public static func traditionalChinese(_ string: String) -> String {
        if looksJapanese(string) { return string }
        // Skip pure Latin / non-CJK lines (English lyrics, timestamps noise).
        if !containsCJKIdeograph(string) { return string }
        let mutable = NSMutableString(string: string)
        // Reverse of Traditional-Simplified.
        CFStringTransform(mutable, nil, "Traditional-Simplified" as CFString, true)
        return mutable as String
    }

    // MARK: - Script detection (lyrics language affinity)

    /// Hiragana / Katakana present → treat as Japanese metadata or lyrics.
    public static func looksJapanese(_ string: String) -> Bool {
        for u in string.unicodeScalars {
            let v = u.value
            if (0x3040...0x309F).contains(v) { return true } // Hiragana
            if (0x30A0...0x30FF).contains(v) { return true } // Katakana
            if (0x31F0...0x31FF).contains(v) { return true } // Katakana ext
            if (0xFF66...0xFF9D).contains(v) { return true } // Halfwidth katakana
        }
        return false
    }

    public static func containsCJKIdeograph(_ string: String) -> Bool {
        string.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    /// Mostly Latin letters (English / romanization lyric dumps).
    public static func looksMostlyLatin(_ string: String) -> Bool {
        var letters = 0
        var latin = 0
        for u in string.unicodeScalars {
            guard CharacterSet.letters.contains(u) else { continue }
            letters += 1
            if u.isASCII { latin += 1 }
        }
        guard letters >= 12 else { return false }
        return Double(latin) / Double(letters) >= 0.88
    }

    /// Sample of synced/plain body for script scoring.
    public static func lyricBodyLooksJapanese(_ synced: String?, plain: String?) -> Bool {
        let sample = String((synced ?? plain ?? "").prefix(600))
        return looksJapanese(sample)
    }

    public static func lyricBodyLooksMostlyLatin(_ synced: String?, plain: String?) -> Bool {
        let sample = String((synced ?? plain ?? "").prefix(600))
        // Ignore LRC timestamps for Latin ratio.
        let stripped = sample.replacingOccurrences(
            of: #"\[\d+:\d+[^\]]*\]"#,
            with: " ",
            options: .regularExpression
        )
        return looksMostlyLatin(stripped)
    }

    /// Single line that is romaji / English (no kana, no CJK), e.g. "Nani wo kikaretemo".
    public static func looksLikeRomajiOrLatinLine(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return false }
        if looksJapanese(t) || containsCJKIdeograph(t) { return false }
        var letters = 0
        var latin = 0
        for u in t.unicodeScalars {
            guard CharacterSet.letters.contains(u) else { continue }
            letters += 1
            if u.isASCII { latin += 1 }
        }
        guard letters >= 3 else { return false }
        return Double(latin) / Double(letters) >= 0.9
    }

    /// Drop Latin companion lines only when they share (or nearly share) a
    /// timestamp with Japanese text. Independent English verses/choruses are
    /// real lyrics and must remain in the timeline.
    public static func preferringJapaneseLines(_ lines: [LyricLine]) -> [LyricLine] {
        let japaneseTimes = lines.compactMap { line -> TimeInterval? in
            looksJapanese(line.text) || containsCJKIdeograph(line.text)
                ? line.time
                : nil
        }.sorted()
        guard !japaneseTimes.isEmpty else { return lines }
        let companionTolerance: TimeInterval = 0.35
        let filtered = lines.filter { line in
            guard looksLikeRomajiOrLatinLine(line.text) else { return true }
            return !containsTime(
                line.time,
                within: companionTolerance,
                in: japaneseTimes
            )
        }
        // Safety: don't empty the timeline if filtering was too aggressive.
        guard filtered.count >= max(2, lines.count / 5) else { return lines }
        return filtered
    }

    private static func containsTime(
        _ time: TimeInterval,
        within tolerance: TimeInterval,
        in sortedTimes: [TimeInterval]
    ) -> Bool {
        guard !sortedTimes.isEmpty else { return false }
        var low = 0
        var high = sortedTimes.count
        while low < high {
            let middle = (low + high) / 2
            if sortedTimes[middle] < time - tolerance {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low < sortedTimes.count
            && sortedTimes[low] <= time + tolerance
    }

    public static func preferringJapanesePlainLines(_ lines: [String]) -> [String] {
        let isJapanese = lines.map { looksJapanese($0) || containsCJKIdeograph($0) }
        guard isJapanese.contains(true) else { return lines }

        // Plain lyrics have no timestamps. Require a repeated adjacent
        // Japanese→Latin pattern before treating Latin lines as companions;
        // one language transition can simply be a genuine English section.
        let companionIndices = Set(lines.indices.filter { index in
            guard looksLikeRomajiOrLatinLine(lines[index]) else { return false }
            return index > lines.startIndex && isJapanese[index - 1]
        })
        guard companionIndices.count >= 2 else { return lines }
        let filtered = lines.enumerated().compactMap { index, line in
            companionIndices.contains(index) ? nil : line
        }
        guard filtered.count >= max(2, lines.count / 5) else { return lines }
        return filtered
    }

    /// Identity confidence 0…100 for a candidate track vs player metadata.
    /// Used to reject “random” multi-source hits (especially NetEase first-result fallbacks).
    public static func identityConfidence(
        wantArtist: String,
        wantTitle: String,
        gotArtist: String?,
        gotTitle: String?,
        wantDuration: TimeInterval? = nil,
        gotDuration: Double? = nil
    ) -> Int {
        var score = 0
        let titleScore = titleMatchScore(want: wantTitle, candidate: gotTitle ?? "")
        score += titleScore // 0…50

        let artistOK: Bool
        if let gotArtist, !gotArtist.isEmpty {
            artistOK = artistsLooselyMatch(gotArtist, wantArtist)
            score += artistOK ? 40 : 0
        } else {
            artistOK = false
        }

        if let wantDuration, wantDuration > 0, let gotDuration, gotDuration > 0 {
            let delta = abs(gotDuration - wantDuration)
            if delta < 3 { score += 20 }
            else if delta < 8 { score += 10 }
            else if delta > 90 { score -= 40 }
            else if delta > 45 { score -= 25 }
        }

        // Gate: must have a real title signal; artist alone is not enough
        // (avoids “same artist, wrong song” and random search tops).
        if titleScore < 30 {
            score = min(score, 25)
        }
        // Pinyin / Latin metadata vs CJK candidate title: require stronger title hit.
        let wantLatin = looksMostlyLatin(wantTitle) || looksMostlyLatin(wantArtist)
        let gotCJK = containsCJKIdeograph(gotTitle ?? "") || looksJapanese(gotTitle ?? "")
        if wantLatin && gotCJK && titleScore < 42 {
            score = min(score, 20)
        }
        // Same (or near) title, different artist: only accept with a tight duration lock.
        // Otherwise multi-source search tops “Cheng Yuan” by the wrong singer slip through.
        if !artistOK {
            let durationClose: Bool = {
                guard let wantDuration, wantDuration > 0, let gotDuration, gotDuration > 0 else {
                    return false
                }
                return abs(gotDuration - wantDuration) < 5
            }()
            if titleScore >= 48, durationClose {
                // Title exact + duration lock is enough when artist metadata is messy.
            } else if titleScore < 42 {
                score = min(score, 28)
            } else {
                score = min(score, 35)
            }
        }
        return max(0, min(100, score))
    }

    /// Minimum identity confidence to accept a non-exact multi-source hit.
    public static let minimumAcceptIdentity = 48

    private static func tokens(_ folded: String) -> [String] {
        // Keep CJK runs and latin runs as soft tokens by splitting empty isn't enough;
        // use a simple character n-gram-ish: whole string is enough for contains.
        // Also split on non-alnum for latin.
        let parts = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        if parts.isEmpty { return folded.isEmpty ? [] : [folded] }
        return parts
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in items {
            let t = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if seen.insert(t.lowercased()).inserted {
                out.append(t)
            }
        }
        return out
    }
}
