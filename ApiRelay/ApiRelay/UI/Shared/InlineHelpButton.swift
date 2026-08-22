import SwiftUI

/// 系统设置式说明按钮：放在行尾控件**之前**（子页行是 ⓘ 然后 〉）。
struct InlineHelpButton: View {
    var title: LocalizedStringKey
    var message: LocalizedStringResource
    var secondaryMessage: LocalizedStringResource? = nil
    /// 空态等没有行标题时，弹层带标题。
    var showsTitle: Bool = true

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: AppSymbols.Action.info)
                .font(.body)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .tint(.secondary)
        .fixedSize()
        .help(String(localized: "help.about"))
        .accessibilityLabel(Text("help.about"))
        .accessibilityHint(Text(title))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            let messageText = String(localized: message)
            let isArticle = messageText.contains("\n")
            VStack(alignment: .leading, spacing: isArticle ? 12 : 10) {
                if showsTitle {
                    Text(title)
                        .font(isArticle ? .headline : .subheadline.weight(.semibold))
                }
                contentStack(messageText, color: .primary, isArticle: isArticle)
                if let secondaryMessage {
                    if isArticle {
                        Divider()
                    }
                    contentStack(
                        String(localized: secondaryMessage),
                        color: .secondary,
                        isArticle: isArticle
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(isArticle ? 16 : 14)
            .frame(width: isArticle ? 320 : 268, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private func contentStack(_ text: String, color: Color, isArticle: Bool) -> some View {
        VStack(alignment: .leading, spacing: isArticle ? 8 : 8) {
            ForEach(Array(Self.blocks(in: text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .numbered(let number, let body):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(number).")
                            .font(.subheadline.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        Text(body)
                            .font(.subheadline)
                            .foregroundStyle(color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .sentence(let sentence):
                    Text(sentence)
                        .font(.subheadline)
                        .foregroundStyle(color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    enum Block: Equatable {
        case sentence(String)
        case numbered(String, String)
    }

    /// 文案自带换行（回收站说明）时按段落排；否则按「。」/句号拆行。
    static func blocks(in text: String) -> [Block] {
        if text.contains("\n") {
            return text
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map(parseLine)
        }
        return sentences(in: text).map { .sentence($0) }
    }

    static func parseLine(_ line: String) -> Block {
        if let numbered = numberedItem(line) {
            return .numbered(numbered.number, numbered.body)
        }
        return .sentence(line)
    }

    /// `1. 正文` 编号项，避免把序号拆成单独一行。
    static func numberedItem(_ line: String) -> (number: String, body: String)? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let number = line[line.startIndex..<dot]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        var rest = line[line.index(after: dot)...]
        guard rest.first?.isWhitespace == true else { return nil }
        rest = rest.drop(while: \.isWhitespace)
        guard !rest.isEmpty else { return nil }
        return (String(number), String(rest))
    }

    /// 中文句号「。」与英文句号后换行；保留句号。不拆 `1.0` 与 `1. 列表`。
    static func sentences(in text: String) -> [String] {
        var lines: [String] = []
        var current = ""
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            let character = chars[index]
            current.append(character)
            let isChineseStop = character == "。" || character == "！" || character == "？"
            if isChineseStop {
                appendSentence(&lines, &current)
                index += 1
                continue
            }
            if character == "." || character == "!" || character == "?" {
                let previousIsDigit = index > 0 && chars[index - 1].isNumber
                let nextIsDigit = index + 1 < chars.count && chars[index + 1].isNumber
                if previousIsDigit && nextIsDigit {
                    index += 1
                    continue
                }
                // `1. ` 编号列表
                if previousIsDigit,
                   index + 1 < chars.count,
                   chars[index + 1].isWhitespace {
                    index += 1
                    continue
                }
                let nextIsSpaceOrEnd = index + 1 >= chars.count
                    || chars[index + 1].isWhitespace
                    || chars[index + 1] == "\n"
                if nextIsSpaceOrEnd {
                    appendSentence(&lines, &current)
                    if index + 1 < chars.count && chars[index + 1].isWhitespace {
                        index += 1
                    }
                }
            }
            index += 1
        }
        appendSentence(&lines, &current)
        return lines
    }

    private static func appendSentence(_ lines: inout [String], _ current: inout String) {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            lines.append(trimmed)
        }
        current = ""
    }
}
