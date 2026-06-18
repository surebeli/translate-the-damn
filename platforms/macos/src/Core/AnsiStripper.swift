import Foundation

/// Removes ANSI escape sequences (CSI cursor/SGR colour + OSC) and carriage returns from captured
/// CLI output (spec §6 — CLIs are tamed into clean text→text calls).
public enum AnsiStripper {
    public static func strip(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)

        var i = s.startIndex
        let end = s.endIndex

        while i < end {
            let c = s[i]

            if c == "\u{1B}" {
                let next = s.index(after: i)
                guard next < end else {
                    // Lone ESC at end; drop it.
                    break
                }
                let nc = s[next]

                if nc == "[" {
                    // CSI: ESC '[' params/intermediates... final byte 0x40–0x7E
                    i = s.index(after: next)
                    while i < end {
                        let b = s[i]
                        guard let scalar = b.unicodeScalars.first,
                              scalar.value < 0x40 || scalar.value > 0x7E else {
                            break
                        }
                        i = s.index(after: i)
                    }
                    if i < end {
                        i = s.index(after: i) // consume final byte
                    }
                    continue
                }

                if nc == "]" {
                    // OSC: ESC ']' ... terminated by BEL or ST (ESC '\')
                    i = s.index(after: next)
                    while i < end {
                        let b = s[i]
                        if b == "\u{07}" {
                            i = s.index(after: i)
                            break
                        }
                        if b == "\u{1B}" {
                            let afterB = s.index(after: i)
                            if afterB < end && s[afterB] == "\\" {
                                i = s.index(after: afterB)
                                break
                            }
                        }
                        i = s.index(after: i)
                    }
                    continue
                }

                // Any other ESC sequence: drop ESC + the following byte.
                i = s.index(after: next)
                continue
            }

            if c == "\r" {
                i = s.index(after: i)
                continue
            }

            result.append(c)
            i = s.index(after: i)
        }

        return result
    }
}
