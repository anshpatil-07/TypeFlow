
import Foundation
import CoreGraphics

let source = CGEventSource(stateID: .hidSystemState)
let vKey: CGKeyCode = 0
var varChar = "a".utf16.first!

let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &varChar)
up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &varChar)
down?.post(tap: .cghidEventTap)
up?.post(tap: .cghidEventTap)
