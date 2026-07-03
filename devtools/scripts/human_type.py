import sys
import random
import time
import subprocess

def run_human_typing(phrase):
    script = 'tell application "System Events"\n'
    total_ms = 0
    total_chars = len(phrase)
    
    for char in phrase:
        c = char.replace('\\', '\\\\').replace('"', '\\"')
        script += f'    keystroke "{c}"\n'
        
        if char == ' ':
            delay_ms = random.randint(45, 140)
        elif char in [',', ';', ':']:
            delay_ms = random.randint(160, 300)
        elif char in ['.', '?', '!']:
            delay_ms = random.randint(350, 700)
        else:
            if random.random() < 0.1:
                delay_ms = random.randint(120, 220)
            else:
                delay_ms = random.randint(45, 95)
        
        script += f'    delay {delay_ms / 1000.0}\n'
        total_ms += delay_ms
    
    script += 'end tell\n'
    
    print(f"[TypingHarness] mode=humanPaced targetWPM=150 phrase='{phrase}'")
    
    start_time = time.time()
    
    # Execute the AppleScript
    process = subprocess.Popen(['osascript', '-'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = process.communicate(input=script.encode('utf-8'))
    
    end_time = time.time()
    elapsed_ms = int((end_time - start_time) * 1000)
    
    # Calculate effective WPM: (chars / 5) / (elapsed_ms / 60000)
    effective_wpm = (total_chars / 5) / (elapsed_ms / 60000) if elapsed_ms > 0 else 0
    
    print(f"[TypingHarness] totalChars={total_chars}")
    print(f"[TypingHarness] elapsedMs={elapsed_ms}")
    print(f"[TypingHarness] effectiveWPM={effective_wpm:.1f}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        phrase = sys.argv[1]
        run_human_typing(phrase)
