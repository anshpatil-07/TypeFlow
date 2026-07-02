import Foundation
import CoreGraphics

let args = CommandLine.arguments
if args.count < 2 { exit(1) }
let text = args[1]
var delayMs = 55
if args.count >= 3 { delayMs = Int(args[2]) ?? 55 }

let source = CGEventSource(stateID: .hidSystemState)

// Basic ascii to keycode mapping for the benchmark cases
let charToKeyCode: [Character: CGKeyCode] = [
    "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38,
    "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17,
    "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
    "A": 0, "B": 11, "C": 8, "D": 2, "E": 14, "F": 3, "G": 5, "H": 4, "I": 34, "J": 38,
    "K": 40, "L": 37, "M": 46, "N": 45, "O": 31, "P": 35, "Q": 12, "R": 15, "S": 1, "T": 17,
    "U": 32, "V": 9, "W": 13, "X": 7, "Y": 16, "Z": 6,
    " ": 49, "\n": 36, "\t": 48,
    "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
    ".": 47, ",": 43, ";": 41, "'": 39, "[": 33, "]": 30, "`": 50, "-": 27, "=": 24, "\\": 42,
    "/": 44,
    ")": 29, "!": 18, "@": 19, "#": 20, "$": 21, "%": 23, "^": 22, "&": 26, "*": 28, "(": 25,
    ">": 47, "<": 43, ":": 41, "\"": 39, "{": 33, "}": 30, "~": 50, "_": 27, "+": 24, "|": 42,
    "?": 44
]

let shiftChars: Set<Character> = [
    "A","B","C","D","E","F","G","H","I","J","K","L","M",
    "N","O","P","Q","R","S","T","U","V","W","X","Y","Z",
    ")","!","@","#","$","%","^","&","*","(","<",">",":",
    "\"","{","}","~","_","+","|","?"
]

for char in text {
    let code = charToKeyCode[char] ?? 0
    let vKey: CGKeyCode = code
    let needsShift = shiftChars.contains(char)
    
    var varChar = char.utf16.first!
    
    let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
    
    if vKey == 0 || !charToKeyCode.keys.contains(char) {
        down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &varChar)
        up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &varChar)
    }
    
    if needsShift {
        down?.flags = .maskShift
        up?.flags = .maskShift
    } else {
        down?.flags = []
        up?.flags = []
    }
    
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
    
    Thread.sleep(forTimeInterval: Double(delayMs) / 1000.0)
}

