import Foundation

/// Cheap string-similarity helper used by ContextCompressor to gate transcript-
/// driven emissions. Jaccard over word trigrams is a good tradeoff: it's O(n),
/// handles insertions/reorderings gracefully, and doesn't need any external
/// dependencies. For inputs shorter than 3 words it falls back to a word-set
/// Jaccard so short transcripts still compare sensibly.
public enum TranscriptSimilarity {
    /// Jaccard similarity over word trigrams. Returns 1.0 when inputs are
    /// identical, 0.0 when disjoint, a value in [0,1] otherwise.
    /// Empty-vs-empty = 1.0, one-empty = 0.0.
    public static func jaccard(_ a: String, _ b: String) -> Double {
        if a.isEmpty && b.isEmpty { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }
        let setA = trigrams(of: a)
        let setB = trigrams(of: b)
        if setA.isEmpty && setB.isEmpty { return 1.0 }
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        guard union > 0 else { return 0.0 }
        return Double(intersection) / Double(union)
    }

    private static func trigrams(of s: String) -> Set<String> {
        let words = s.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard words.count >= 3 else {
            // Fallback: treat the word list as a set so short inputs still
            // produce a meaningful overlap score.
            return Set(words)
        }
        var result = Set<String>()
        for i in 0..<(words.count - 2) {
            result.insert("\(words[i]) \(words[i + 1]) \(words[i + 2])")
        }
        return result
    }
}
