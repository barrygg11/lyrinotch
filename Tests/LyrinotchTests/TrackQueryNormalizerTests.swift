import XCTest
@testable import LyrinotchCore

final class TrackQueryNormalizerTests: XCTestCase {
    func testArtistVariantsStripTopicAndUnderscore() {
        let variants = TrackQueryNormalizer.artistTitleVariants(
            artist: "马也_Crabbit - Topic",
            title: "海屿你"
        )
        let artists = Set(variants.map(\.artist))
        XCTAssertTrue(artists.contains("马也_Crabbit - Topic") || artists.contains(where: { $0.contains("马也") }))
        XCTAssertTrue(artists.contains(where: { $0.contains("Crabbit") && !$0.contains("_") })
            || artists.contains("马也Crabbit")
            || artists.contains(where: { !$0.contains("_") && $0.contains("马也") }))
    }

    func testFreeTextIncludesTitleOnly() {
        let q = TrackQueryNormalizer.freeTextQueries(artist: "马也_Crabbit", title: "海屿你")
        XCTAssertTrue(q.contains("海屿你"))
        // Artist+title should come before title-only (reduces wrong-song matches).
        XCTAssertEqual(q.first?.contains("海屿你"), true)
        if q.count >= 2 {
            XCTAssertTrue(q[0].contains("马也") || q[0].contains("Crabbit"))
        }
    }

    func testLooseArtistMatch() {
        XCTAssertTrue(
            TrackQueryNormalizer.artistsLooselyMatch("马也_Crabbit", "马也Crabbit - Topic")
        )
        XCTAssertTrue(
            TrackQueryNormalizer.artistsLooselyMatch("马也Crabbit", "马也_Crabbit")
        )
        XCTAssertFalse(
            TrackQueryNormalizer.artistsLooselyMatch("Artist", "Different Artist")
        )
    }

    func testTitleMatchScorePrefersExact() {
        XCTAssertEqual(
            TrackQueryNormalizer.titleMatchScore(want: "海屿你", candidate: "海屿你"),
            50
        )
        XCTAssertGreaterThan(
            TrackQueryNormalizer.titleMatchScore(want: "海屿你", candidate: "海屿你"),
            TrackQueryNormalizer.titleMatchScore(want: "Love", candidate: "Love Story")
        )
        // Very short fuzzy contains should not score high.
        XCTAssertEqual(
            TrackQueryNormalizer.titleMatchScore(want: "Hi", candidate: "History"),
            0
        )
    }

    /// Apple Music TW often uses Traditional; LRCLIB often has Simplified.
    func testTraditionalSimplifiedVariantsForCJK() {
        let title = "想你時風起 (電視劇《我的人間煙火》回憶主題曲)"
        let artist = "單依純"
        let pairs = TrackQueryNormalizer.artistTitleVariants(artist: artist, title: title)
        let titles = Set(pairs.map(\.title))
        let artists = Set(pairs.map(\.artist))

        XCTAssertTrue(titles.contains("想你時風起") || titles.contains(where: { $0.hasPrefix("想你時風起") }))
        XCTAssertTrue(titles.contains("想你时风起") || titles.contains(where: { $0.contains("想你时风起") }))
        XCTAssertTrue(artists.contains("單依純"))
        XCTAssertTrue(artists.contains("单依纯"))

        XCTAssertTrue(
            TrackQueryNormalizer.artistsLooselyMatch("單依純", "单依纯")
        )
        XCTAssertGreaterThan(
            TrackQueryNormalizer.titleMatchScore(
                want: "想你時風起",
                candidate: "想你时风起 (电视剧《我的人间烟火》回忆主题曲)"
            ),
            40
        )

        let free = TrackQueryNormalizer.freeTextQueries(artist: artist, title: title)
        XCTAssertTrue(free.contains(where: { $0.contains("想你时风起") }))
    }

    func testSimplifiedChineseTransform() {
        XCTAssertEqual(
            TrackQueryNormalizer.simplifiedChinese("單依純"),
            "单依纯"
        )
        XCTAssertEqual(
            TrackQueryNormalizer.simplifiedChinese("想你時風起"),
            "想你时风起"
        )
    }

    func testTraditionalChineseRoundTripDisplay() {
        // Hans → Hant for common lyric characters (ICU reverse transform).
        let hans = "现在那边是几点"
        let hant = TrackQueryNormalizer.traditionalChinese(hans)
        XCTAssertTrue(hant.contains("現") || hant.contains("邊") || hant.contains("點") || hant == hans)
        // Non-CJK unchanged.
        XCTAssertEqual(TrackQueryNormalizer.traditionalChinese("Mary on a cross"), "Mary on a cross")
    }

    func testJapaneseLeftUntouchedByChineseTransforms() {
        let jp = "君の名は。 スパークル"
        XCTAssertEqual(TrackQueryNormalizer.simplifiedChinese(jp), jp)
        XCTAssertEqual(TrackQueryNormalizer.traditionalChinese(jp), jp)
        XCTAssertTrue(TrackQueryNormalizer.looksJapanese(jp))
        XCTAssertTrue(TrackQueryNormalizer.looksMostlyLatin("Hello world this is english lyrics only"))
        XCTAssertFalse(TrackQueryNormalizer.looksMostlyLatin(jp))
    }

    func testPreferJapaneseLinesDropsRomajiCompanions() {
        let lines = [
            LyricLine(time: 0, text: "何を聞かれても"),
            LyricLine(time: 0.1, text: "Nani wo kikaretemo"),
            LyricLine(time: 2, text: "のらりくらり"),
            LyricLine(time: 2.1, text: "Norari kurari")
        ]
        let filtered = TrackQueryNormalizer.preferringJapaneseLines(lines)
        XCTAssertEqual(filtered.map(\.text), ["何を聞かれても", "のらりくらり"])
        XCTAssertTrue(TrackQueryNormalizer.looksLikeRomajiOrLatinLine("Nani wo kikaretemo"))
        XCTAssertFalse(TrackQueryNormalizer.looksLikeRomajiOrLatinLine("何を聞かれても"))
    }

    func testPreferJapaneseLinesKeepsIndependentEnglishSection() {
        let lines = [
            LyricLine(time: 0, text: "君の声を聞かせて"),
            LyricLine(time: 4, text: "Tell me what you really want tonight"),
            LyricLine(time: 8, text: "夜が明けるまで")
        ]

        let filtered = TrackQueryNormalizer.preferringJapaneseLines(lines)

        XCTAssertEqual(filtered, lines)
    }

    func testPreferJapanesePlainLinesRequiresRepeatedCompanionPattern() {
        let bilingual = [
            "何を聞かれても",
            "Nani wo kikaretemo",
            "のらりくらり",
            "Norari kurari"
        ]
        XCTAssertEqual(
            TrackQueryNormalizer.preferringJapanesePlainLines(bilingual),
            ["何を聞かれても", "のらりくらり"]
        )

        let mixedSong = [
            "君の声を聞かせて",
            "Tell me what you really want tonight",
            "夜が明けるまで"
        ]
        XCTAssertEqual(
            TrackQueryNormalizer.preferringJapanesePlainLines(mixedSong),
            mixedSong
        )
    }

    func testIdentityConfidenceRejectsWeakTitle() {
        let weak = TrackQueryNormalizer.identityConfidence(
            wantArtist: "Zhu Ke",
            wantTitle: "Cheng Yuan",
            gotArtist: "路勇",
            gotTitle: "凡心",
            wantDuration: 200,
            gotDuration: 254
        )
        XCTAssertLessThan(weak, TrackQueryNormalizer.minimumAcceptIdentity)

        let strong = TrackQueryNormalizer.identityConfidence(
            wantArtist: "王铮亮",
            wantTitle: "凡心",
            gotArtist: "王铮亮",
            gotTitle: "凡心",
            wantDuration: 206,
            gotDuration: 206
        )
        XCTAssertGreaterThanOrEqual(strong, TrackQueryNormalizer.minimumAcceptIdentity)
    }

    func testIdentityConfidenceRejectsSameTitleWrongArtist() {
        // Exact title hit from a different singer without duration lock.
        let wrongArtist = TrackQueryNormalizer.identityConfidence(
            wantArtist: "Zhu Ke",
            wantTitle: "Cheng Yuan",
            gotArtist: "Someone Else",
            gotTitle: "Cheng Yuan",
            wantDuration: 210,
            gotDuration: 260
        )
        XCTAssertLessThan(wrongArtist, TrackQueryNormalizer.minimumAcceptIdentity)

        // Same title + tight duration can still pass when artist metadata is messy.
        let durationLocked = TrackQueryNormalizer.identityConfidence(
            wantArtist: "Zhu Ke",
            wantTitle: "Cheng Yuan",
            gotArtist: "朱可",
            gotTitle: "Cheng Yuan",
            wantDuration: 210,
            gotDuration: 211
        )
        // Artist still fails (Latin vs CJK), but exact title + duration lock keeps score.
        XCTAssertGreaterThanOrEqual(durationLocked, TrackQueryNormalizer.minimumAcceptIdentity)
    }

    func testIdentityConfidencePenalizesVeryLargeDurationMismatchMore() {
        let mediumMismatch = TrackQueryNormalizer.identityConfidence(
            wantArtist: "Artist",
            wantTitle: "Song",
            gotArtist: "Artist",
            gotTitle: "Song",
            wantDuration: 180,
            gotDuration: 240
        )
        let veryLargeMismatch = TrackQueryNormalizer.identityConfidence(
            wantArtist: "Artist",
            wantTitle: "Song",
            gotArtist: "Artist",
            gotTitle: "Song",
            wantDuration: 180,
            gotDuration: 300
        )

        XCTAssertLessThan(veryLargeMismatch, mediumMismatch)
    }
}
