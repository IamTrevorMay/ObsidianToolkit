import Foundation
import SwiftUI

struct MarkdownRenderer {
    static func render(_ markdown: String) -> AttributedString {
        do {
            let attributedString = try AttributedString(markdown: markdown, options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            ))
            return attributedString
        } catch {
            return AttributedString(markdown)
        }
    }

    static func renderFull(_ markdown: String) -> AttributedString {
        do {
            return try AttributedString(markdown: markdown)
        } catch {
            return AttributedString(markdown)
        }
    }
}
