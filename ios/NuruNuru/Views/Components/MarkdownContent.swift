import SwiftUI

// MARK: - Block Types

private enum MdBlock {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case code(code: String)
    case quote(text: String)
    case listItem(ordered: Bool, number: Int, text: String)
    case rule
    case blank
}

// MARK: - Block Parser

private func parseBlocks(_ content: String) -> [MdBlock] {
    let lines = content.components(separatedBy: "\n")
    var result: [MdBlock] = []
    var i = 0

    while i < lines.count {
        let raw = lines[i]
        let trimmedLeading = String(raw.drop(while: { $0 == " " || $0 == "\t" }))

        if trimmedLeading.hasPrefix("```") {
            var codeLines: [String] = []
            i += 1
            while i < lines.count && !lines[i].drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("```") {
                codeLines.append(lines[i])
                i += 1
            }
            result.append(.code(code: codeLines.joined(separator: "\n")))
        } else if i + 1 < lines.count,
                  !raw.trimmingCharacters(in: .whitespaces).isEmpty,
                  lines[i + 1].trimmingCharacters(in: .whitespaces).unicodeScalars.allSatisfy({ $0 == "=" }),
                  !lines[i + 1].trimmingCharacters(in: .whitespaces).isEmpty {
            result.append(.heading(level: 1, text: raw.trimmingCharacters(in: .whitespaces)))
            i += 1
        } else if i + 1 < lines.count,
                  !raw.trimmingCharacters(in: .whitespaces).isEmpty,
                  lines[i + 1].trimmingCharacters(in: .whitespaces).count >= 2,
                  lines[i + 1].trimmingCharacters(in: .whitespaces).unicodeScalars.allSatisfy({ $0 == "-" }) {
            result.append(.heading(level: 2, text: raw.trimmingCharacters(in: .whitespaces)))
            i += 1
        } else if trimmedLeading.hasPrefix("##### ") {
            result.append(.heading(level: 5, text: String(trimmedLeading.dropFirst(6))))
        } else if trimmedLeading.hasPrefix("#### ") {
            result.append(.heading(level: 4, text: String(trimmedLeading.dropFirst(5))))
        } else if trimmedLeading.hasPrefix("### ") {
            result.append(.heading(level: 3, text: String(trimmedLeading.dropFirst(4))))
        } else if trimmedLeading.hasPrefix("## ") {
            result.append(.heading(level: 2, text: String(trimmedLeading.dropFirst(3))))
        } else if trimmedLeading.hasPrefix("# ") {
            result.append(.heading(level: 1, text: String(trimmedLeading.dropFirst(2))))
        } else if isHorizontalRule(trimmedLeading) {
            result.append(.rule)
        } else if trimmedLeading.hasPrefix("> ") {
            result.append(.quote(text: String(trimmedLeading.dropFirst(2))))
        } else if isUnorderedListItem(trimmedLeading) {
            result.append(.listItem(ordered: false, number: 0, text: String(trimmedLeading.dropFirst(2))))
        } else if let (num, rest) = parseOrderedListItem(trimmedLeading) {
            result.append(.listItem(ordered: true, number: num, text: rest))
        } else if raw.trimmingCharacters(in: .whitespaces).isEmpty {
            result.append(.blank)
        } else {
            var paraLines = [raw]
            while i + 1 < lines.count {
                let next = lines[i + 1]
                let nextT = String(next.drop(while: { $0 == " " || $0 == "\t" }))
                if next.trimmingCharacters(in: .whitespaces).isEmpty
                    || nextT.hasPrefix("#")
                    || nextT.hasPrefix("```")
                    || nextT.hasPrefix(">")
                    || isUnorderedListItem(nextT)
                    || parseOrderedListItem(nextT) != nil
                    || isHorizontalRule(nextT) { break }
                let separator = paraLines.last?.hasSuffix("  ") == true ? "\n" : " "
                paraLines.append(separator + next)
                i += 1
            }
            result.append(.paragraph(text: paraLines.joined()))
        }
        i += 1
    }
    return result
}

private func isHorizontalRule(_ s: String) -> Bool {
    let stripped = s.filter { $0 != " " }
    guard stripped.count >= 3 else { return false }
    return stripped.allSatisfy { $0 == "-" }
        || stripped.allSatisfy { $0 == "*" }
        || stripped.allSatisfy { $0 == "_" }
}

private func isUnorderedListItem(_ s: String) -> Bool {
    guard s.count >= 2, let first = s.first else { return false }
    return (first == "-" || first == "*" || first == "+") && s.dropFirst().first == " "
}

private func parseOrderedListItem(_ s: String) -> (Int, String)? {
    guard let dotRange = s.range(of: ". ") else { return nil }
    let prefix = String(s[s.startIndex..<dotRange.lowerBound])
    guard let num = Int(prefix) else { return nil }
    return (num, String(s[dotRange.upperBound...]))
}

// MARK: - Inline Parser

private func buildAttributed(_ text: String, linkColor: Color) -> AttributedString {
    var result = AttributedString()
    var i = text.startIndex

    func advance(_ n: Int) -> String.Index? {
        text.index(i, offsetBy: n, limitedBy: text.endIndex)
    }

    while i < text.endIndex {
        let rest = text[i...]

        if rest.hasPrefix("***"), let start3 = advance(3), start3 <= text.endIndex,
           let end = text.range(of: "***", range: start3..<text.endIndex) {
            var a = AttributedString(text[start3..<end.lowerBound])
            a.font = Font.body.bold().italic()
            result += a
            i = end.upperBound
        } else if rest.hasPrefix("**"), let start2 = advance(2), start2 <= text.endIndex,
                  let end = text.range(of: "**", range: start2..<text.endIndex) {
            var a = AttributedString(text[start2..<end.lowerBound])
            a.font = Font.body.bold()
            result += a
            i = end.upperBound
        } else if rest.hasPrefix("__"), let start2 = advance(2), start2 <= text.endIndex,
                  let end = text.range(of: "__", range: start2..<text.endIndex) {
            var a = AttributedString(text[start2..<end.lowerBound])
            a.font = Font.body.bold()
            result += a
            i = end.upperBound
        } else if text[i] == "*", let next1 = advance(1), next1 < text.endIndex, text[next1] != "*",
                  let end = text.range(of: "*", range: next1..<text.endIndex) {
            var a = AttributedString(text[next1..<end.lowerBound])
            a.font = Font.body.italic()
            result += a
            i = end.upperBound
        } else if text[i] == "_", let next1 = advance(1), next1 < text.endIndex, text[next1] != "_",
                  let end = text.range(of: "_", range: next1..<text.endIndex) {
            var a = AttributedString(text[next1..<end.lowerBound])
            a.font = Font.body.italic()
            result += a
            i = end.upperBound
        } else if rest.hasPrefix("~~"), let start2 = advance(2), start2 <= text.endIndex,
                  let end = text.range(of: "~~", range: start2..<text.endIndex) {
            var a = AttributedString(text[start2..<end.lowerBound])
            a.strikethroughStyle = Text.LineStyle(pattern: .solid)
            result += a
            i = end.upperBound
        } else if text[i] == "`", let next1 = advance(1), next1 < text.endIndex,
                  let end = text.range(of: "`", range: next1..<text.endIndex) {
            var a = AttributedString(text[next1..<end.lowerBound])
            a.font = Font.system(.body, design: .monospaced)
            a.backgroundColor = Color(white: 0.2)
            result += a
            i = end.upperBound
        } else if text[i] == "[",
                  let cb = text.range(of: "]", range: text.index(after: i)..<text.endIndex),
                  cb.upperBound < text.endIndex, text[cb.upperBound] == "(",
                  let cp = text.range(of: ")", range: text.index(after: cb.upperBound)..<text.endIndex) {
            let linkText = String(text[text.index(after: i)..<cb.lowerBound])
            let url      = String(text[text.index(after: cb.upperBound)..<cp.lowerBound])
            var a = AttributedString(linkText)
            a.foregroundColor = linkColor
            a.underlineStyle  = Text.LineStyle(pattern: .solid)
            if let u = URL(string: url) { a.link = u }
            result += a
            i = cp.upperBound
        } else {
            result += AttributedString(String(text[i]))
            i = text.index(after: i)
        }
    }
    return result
}

// MARK: - MarkdownContent

/// Markdown block+inline renderer.
/// Mirrors Android MarkdownContent composable.
struct MarkdownContent: View {

    let content: String

    @Environment(\.nuruTheme) private var theme

    var body: some View {
        let blocks = parseBlocks(content)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MdBlock) -> some View {
        switch block {
        case .blank:
            Spacer().frame(height: 6)

        case .heading(let level, let text):
            VStack(alignment: .leading, spacing: 4) {
                if level <= 2 { Spacer().frame(height: 8) }
                let (size, weight) = headingStyle(level)
                Text(text)
                    .font(.system(size: size, weight: weight))
                    .foregroundStyle(theme.textPrimary)
                    .lineSpacing(size * 0.35)
                if level == 1 {
                    Spacer().frame(height: 4)
                    Divider().background(theme.borderColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph(let text):
            Text(buildAttributed(text, linkColor: NuruColors.lineGreen))
                .font(NuruFont.bodyMedium())
                .foregroundStyle(theme.textPrimary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                    .lineSpacing(4)
                    .padding(12)
            }
            .background(theme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(NuruColors.lineGreen)
                    .frame(width: 3)
                Text(text)
                    .font(NuruFont.bodyMedium())
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .listItem(let ordered, let number, let text):
            HStack(alignment: .top, spacing: 8) {
                Text(ordered ? "\(number)." : "•")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.textSecondary)
                    .frame(minWidth: 20, alignment: .leading)
                Text(buildAttributed(text, linkColor: NuruColors.lineGreen))
                    .font(NuruFont.bodyMedium())
                    .foregroundStyle(theme.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .rule:
            VStack(spacing: 4) {
                Spacer().frame(height: 4)
                Divider().background(theme.borderColor)
                Spacer().frame(height: 4)
            }
        }
    }

    private func headingStyle(_ level: Int) -> (CGFloat, Font.Weight) {
        switch level {
        case 1:  return (26, .bold)
        case 2:  return (22, .bold)
        case 3:  return (18, .semibold)
        case 4:  return (16, .semibold)
        default: return (14, .medium)
        }
    }
}
