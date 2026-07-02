import sys
import time
import random
import subprocess
import argparse

def type_text(text, wpm, backspace_prob=0.0):
    # 1 WPM = 5 chars per minute
    cpm = wpm * 5
    cps = cpm / 60.0
    delay = 1.0 / cps
    
    for char in text:
        # Simulate backspacing occasionally
        if backspace_prob > 0 and random.random() < backspace_prob and char != ' ':
            # type wrong char
            wrong_char = chr(ord(char) + 1)
            if wrong_char == '"': wrong_char = 'x'
            subprocess.run(['osascript', '-e', f'tell application "System Events" to keystroke "{wrong_char}"'])
            time.sleep(delay)
            # backspace
            subprocess.run(['osascript', '-e', 'tell application "System Events" to key code 51'])
            time.sleep(delay)
            
        if char == '"':
            # Escape quotes for osascript
            subprocess.run(['osascript', '-e', 'tell application "System Events" to keystroke "\\""'])
        elif char == '\n':
            subprocess.run(['osascript', '-e', 'tell application "System Events" to keystroke return'])
        elif char == '\\':
            subprocess.run(['osascript', '-e', 'tell application "System Events" to keystroke "\\\\"'])
        else:
            subprocess.run(['osascript', '-e', f'tell application "System Events" to keystroke "{char}"'])
        
        # Add random jitter to simulate human typing
        jitter = random.uniform(0.7, 1.3)
        time.sleep(delay * jitter)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--text', required=True)
    parser.add_argument('--wpm', type=int, default=150)
    parser.add_argument('--backspace', type=float, default=0.0)
    args = parser.parse_args()
    
    type_text(args.text, args.wpm, args.backspace)
