import Foundation

public enum Matcher {
    static let fillers: Set<String> = ["i", "im", "i'm", "am", "working", "on", "the", "a", "an", "for", "to", "with", "please", "start", "task", "my"]
    public static func tokens(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty && !fillers.contains($0) }
    }
    public static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        var row = Array(0...y.count)
        for (i, c) in x.enumerated() {
            var next = [i + 1]
            for (j, d) in y.enumerated() { next.append(min(next[j] + 1, row[j + 1] + 1, row[j] + (c == d ? 0 : 1))) }
            row = next
        }
        return row[y.count]
    }
    public static func ranked(_ query: String, tasks: [WorkTask]) -> [(task: WorkTask, score: Double)] {
        let q = Set(tokens(query)); guard !q.isEmpty else { return [] }
        let results: [(task: WorkTask, score: Double)] = tasks.filter { !$0.done }.compactMap { task -> (task: WorkTask, score: Double)? in
            let title = Set(tokens(task.title)), project = Set(tokens(task.project))
            func matches(_ word: String, in words: Set<String>) -> Bool {
                words.contains { candidate in candidate == word || (word.count >= 4 && candidate.count >= 4 && distance(word, candidate) <= 1) }
            }
            let hits = q.filter { matches($0, in: title.union(project)) }.count
            guard hits > 0 else { return nil }
            let titleHits = q.filter { matches($0, in: title) }.count
            let score = Double(hits) / Double(q.count) * 0.75 + Double(titleHits) / Double(max(title.count, 1)) * 0.25
            return (task, score)
        }
        return Array(results.sorted { $0.score == $1.score ? $0.task.title < $1.task.title : $0.score > $1.score }.prefix(5))
    }
}
