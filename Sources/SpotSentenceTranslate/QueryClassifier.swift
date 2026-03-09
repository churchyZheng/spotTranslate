import Foundation
import NaturalLanguage

struct TranslationCandidate: Equatable, Sendable {
    let originalText: String
    let normalizedText: String
    let sourceLanguage: Locale.Language
    let targetLanguage: Locale.Language
}

enum QueryClassifier {
    static func translationCandidate(for rawText: String) -> TranslationCandidate? {
        let normalizedText = normalize(rawText)
        guard normalizedText.count >= 2 else {
            return nil
        }

        if looksLikeURL(normalizedText) {
            return nil
        }

        let tokenCount = normalizedText.split(whereSeparator: \.isWhitespace).count
        let ideographCount = normalizedText.unicodeScalars.filter(\.properties.isIdeographic).count
        let containsSentencePunctuation = normalizedText.contains(where: isSentencePunctuation)
        let shouldTranslate = tokenCount >= 2 || ideographCount >= 4 || (containsSentencePunctuation && normalizedText.count >= 6)

        guard shouldTranslate else {
            return nil
        }

        let sourceLanguage = preferredSourceLanguage(for: normalizedText)

        return TranslationCandidate(
            originalText: rawText,
            normalizedText: normalizedText,
            sourceLanguage: sourceLanguage,
            targetLanguage: preferredTargetLanguage(for: sourceLanguage)
        )
    }

    static func normalize(_ rawText: String) -> String {
        rawText
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func preferredSourceLanguage(for text: String) -> Locale.Language {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        if recognizer.dominantLanguage?.rawValue.hasPrefix("zh") == true {
            return Locale.Language(identifier: "zh-Hans")
        }

        return Locale.Language(identifier: "en")
    }

    static func preferredTargetLanguage(for sourceLanguage: Locale.Language) -> Locale.Language {
        if sourceLanguage.maximalIdentifier.hasPrefix("zh-Hans") {
            return Locale.Language(identifier: "en")
        }

        return Locale.Language(identifier: "zh-Hans")
    }

    private static func looksLikeURL(_ text: String) -> Bool {
        let lowercasedText = text.lowercased()
        return lowercasedText.hasPrefix("http://")
            || lowercasedText.hasPrefix("https://")
            || lowercasedText.hasPrefix("file://")
            || lowercasedText.hasPrefix("www.")
    }

    private static func isSentencePunctuation(_ character: Character) -> Bool {
        ",.!?;:，。！？；：、()[]{}\"'".contains(character)
    }
}
