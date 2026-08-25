import Foundation
import NaturalLanguage

/// Local, offline task classifier. Lexicon-first (fast, precise on domain
/// jargon), sentence-embedding fallback (catches phrasing the lexicon misses),
/// and an explicit "unknown" verdict so a guess never becomes a wrong tag.
enum Tag: String, CaseIterable {
    case analysis = "Analysis"
    case creative = "Creative"
    case campaign = "Campaign"
    case comms    = "Comms"
    case admin    = "Admin"

    var hex: UInt32 {
        switch self {
        case .analysis: 0xFF7A1A   // accent — the core of the job
        case .creative: 0xC77DFF
        case .campaign: 0x3DD68C
        case .comms:    0x5AA9FF
        case .admin:    0x8A93A6
        }
    }
}

struct Tagger {
    /// True when built against an SDK carrying Apple's on-device model.
    static var usingAppleModel: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return AppleModelTagger.available }
        #endif
        return false
    }

    static var backendName: String { usingAppleModel ? "Apple on-device model" : "Local lexicon" }

    /// Classifies asynchronously so an LLM backend can be awaited; the
    /// lexicon path returns immediately.
    static func tagAsync(_ title: String) async -> Tag? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), AppleModelTagger.available {
            if let t = await AppleModelTagger.tag(title) { return t }
        }
        #endif
        return tag(title)
    }

    /// weight 3 = decisive domain term, 2 = strong, 1 = weak hint
    static let lexicon: [Tag: [(String, Double)]] = [
        .analysis: [("analysis",3),("analyse",3),("analyze",3),("report",3),("reporting",3),
                    ("pull",2),("data",2),("dashboard",3),("roas",3),("troas",3),("cpi",3),
                    ("ltv",3),("retention",3),("cohort",3),("profit",3),("revenue",3),
                    ("metrics",3),("numbers",2),("stats",2),("benchmark",2),("forecast",2),
                    ("halo",2),("incrementality",3),("attribution",3),("appsflyer",2),
                    ("spend check",3),("deep dive",2),("investigate",2),("audit",2),
                    ("competitor",2),("sweep",1),("keyword report",3),("aso report",3)],
        .creative: [("creative",3),("creatives",3),("playable",3),("playables",3),
                    ("static",3),("statics",3),("video",3),("teaser",3),("banner",3),
                    ("asset",2),("assets",2),("artwork",3),("design",3),("mockup",3),
                    ("screenshot",3),("screenshots",3),("icon",2),("thumbnail",2),
                    ("storyboard",3),("brief",2),("concept",2),("cutdown",3),("hook",2),
                    ("reskin",3),("re-skin",3),("render",2),("edit video",3),("ugc",3),
                    ("figma",3),("canva",3),("photoshop",3),("aso",2)],
        .campaign: [("campaign",3),("campaigns",3),("budget",3),("bid",3),("bids",3),
                    ("kill",2),("scale",2),("pause",2),("launch",2),("upload",2),
                    ("targeting",3),("audience",2),("ad set",3),("adset",3),("adgroup",3),
                    ("ad group",3),("rotation",2),("reallocation",2),("allocation",2),
                    ("bulk",2),("meta ads",3),("google ads",3),("applovin",1),
                    ("mintegral",1),("unity ads",2),("tiktok ads",3),("apple ads",3),
                    ("optimisation",2),("optimization",2),("setup",1),("turn off",2)],
        .comms:    [("email",3),("emails",3),("reply",3),("respond",2),("answer",2),
                    ("slack",3),("message",2),("call",2),("sync",3),("standup",3),
                    ("1on1",3),("1:1",3),("one on one",3),("meeting",3),("interview",3),
                    ("catch up",2),("follow-up",1),("follow up",1),("intro",1),
                    ("presentation",2),("present",2),("share with",2),("align",2),
                    ("feedback to",2),("onboarding",2)],
        .admin:    [("invoice",4),("invoices",4),("billing",4),("expense",4),("expenses",4),("contract",4),
                    ("paperwork",3),("admin",3),("plan",2),("planning",2),("schedule",2),
                    ("organise",2),("organize",2),("cleanup",2),("clean up",2),
                    ("documentation",2),("document",1),("doc",1),("notes",1),("tidy",2),
                    ("backup",2),("setup account",2),("access",1),("password",2),("okr",2)],
    ]

    private static let embedding = NLEmbedding.sentenceEmbedding(for: .english)
    private static let prototypes: [Tag: [String]] = [
        .analysis: ["analyze performance data and metrics", "pull a report of results"],
        .creative: ["design creative visual assets", "produce video ad artwork"],
        .campaign: ["manage advertising campaigns and budgets", "launch and optimize ads"],
        .comms:    ["reply to email and messages", "meeting or call with a teammate"],
        .admin:    ["file invoices and paperwork", "plan and organize schedule"],
    ]

    /// Returns nil when nothing is confident enough — untagged beats mistagged.
    static func tag(_ title: String) -> Tag? {
        let t = " " + title.lowercased()
            .replacingOccurrences(of: "[^a-z0-9: ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression) + " "

        var scores: [Tag: Double] = [:]
        for (tag, terms) in lexicon {
            var s = 0.0
            for (term, w) in terms where t.contains(" \(term) ") || t.contains(" \(term)") && term.contains(" ") {
                s += w
            }
            if s > 0 { scores[tag] = s }
        }
        if let best = scores.max(by: { $0.value < $1.value }) {
            let others = scores.filter { $0.key != best.key }.map(\.value).max() ?? 0
            if best.value >= 3 || best.value > others { return best.key }
        }

        guard let embedding, let v = embedding.vector(for: title) else { return nil }
        var sims: [(Tag, Double)] = []
        for (tag, protos) in prototypes {
            let best = protos.compactMap { embedding.vector(for: $0) }
                .map { cosine(v, $0) }.max() ?? 0
            sims.append((tag, best))
        }
        sims.sort { $0.1 > $1.1 }
        guard let top = sims.first, sims.count > 1 else { return nil }
        // Only trust the embedding when it is both confident and decisive.
        return (top.1 > 0.45 && top.1 - sims[1].1 > 0.05) ? top.0 : nil
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        var d = 0.0, na = 0.0, nb = 0.0
        for i in 0..<min(a.count, b.count) { d += a[i]*b[i]; na += a[i]*a[i]; nb += b[i]*b[i] }
        return (na == 0 || nb == 0) ? 0 : d / (na.squareRoot() * nb.squareRoot())
    }
}

#if canImport(FoundationModels)
import FoundationModels

/// Apple's on-device language model — same class of engine Cotypist uses.
/// Compiled in only when built against the macOS 26 SDK; falls back silently.
@available(macOS 26, *)
enum AppleModelTagger {
    static var available: Bool {
        SystemLanguageModel.default.availability == .available
    }

    static func tag(_ title: String) async -> Tag? {
        let options = Tag.allCases.map(\.rawValue).joined(separator: ", ")
        let prompt = """
        Classify this work task into exactly one category: \(options).
        Reply with the category word only, nothing else.

        Task: \(title)
        """
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let answer = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return Tag.allCases.first { answer.hasPrefix($0.rawValue.lowercased()) }
        } catch {
            return nil
        }
    }
}
#endif
