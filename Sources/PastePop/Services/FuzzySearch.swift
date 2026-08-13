import Foundation

/// 轻量模糊匹配 + 打分。子序列匹配（query 的字符按序出现在 text 中即算命中），
/// 对「连续命中」「词首命中」「起始命中」加分，越相关分越高；不命中返回 nil。
enum FuzzySearch {
    static func score(query: String, in text: String) -> Int? {
        let normalizedQuery = query.lowercased()
        guard !normalizedQuery.isEmpty else { return 0 }

        var score = 0
        var queryIndex = normalizedQuery.startIndex
        var textCount = 0
        var previousMatchIndex = -2
        var previousCharacter: Character?

        for character in text {
            let textIndex = textCount
            textCount += 1
            guard queryIndex < normalizedQuery.endIndex else { break }

            guard character.lowercased() == String(normalizedQuery[queryIndex]) else {
                previousCharacter = character
                continue
            }

            var charScore = 1

            // 连续命中：紧接上一个命中
            if textIndex == previousMatchIndex + 1 {
                charScore += 5
            }

            if textIndex == 0 {
                // 整段起始命中
                charScore += 8
            } else {
                let previous = previousCharacter
                if previous == " " || previous == "_" || previous == "-" || previous == "/" || previous == "." {
                    // 词首命中（分隔符之后）
                    charScore += 6
                } else if previous?.isLowercase == true && character.isUppercase {
                    // camelCase 边界
                    charScore += 4
                }
            }

            score += charScore
            previousMatchIndex = textIndex
            queryIndex = normalizedQuery.index(after: queryIndex)
            previousCharacter = character
        }

        // query 必须全部命中
        guard queryIndex == normalizedQuery.endIndex else {
            return nil
        }

        // 文本越短相对越相关（轻微加权）
        if textCount < text.count {
            textCount = text.count
        }
        score += max(0, 10 - textCount / 20)
        return score
    }
}
