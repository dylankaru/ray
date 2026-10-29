//
//  EmojiStore.swift
//  ray
//
//  Created by Dylan Karunanayake on 28/10/2026.
//

struct EmojiEntry {
    let glyph: String
    let name: String
}

enum EmojiStore {
    static let all: [EmojiEntry] = {
        var out: [EmojiEntry] = []
        for v in UInt32(0x100)...0x1FAFF {
            guard let s = Unicode.Scalar(v),
                  s.properties.isEmoji,
                  !(0x1F1E6...0x1F1FF).contains(v),
                  !(0x1F3FB...0x1F3FF).contains(v),
                  let name = s.properties.name else { continue }
            let glyph = s.properties.isEmojiPresentation ? String(s) : String(s) + "\u{FE0F}"
            out.append(EmojiEntry(glyph: glyph, name: name.lowercased()))
        }
        return out
    }()
}
