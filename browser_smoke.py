import subprocess
import time

def run():
    print("Opening Safari with textarea...")
    url = "data:text/html,<textarea id='t' autofocus style='width:100vw;height:100vh;font-size:24px;'></textarea>"
    
    # Open Safari
    subprocess.run(['osascript', '-e', f'tell application "Safari" to open location "{url}"'])
    time.sleep(2)
    subprocess.run(['osascript', '-e', 'tell application "Safari" to activate'])
    time.sleep(1)
    
    print("Typing in browser...")
    phrase = "This is a browser smoke test to ensure TypeFlow works in web textareas "
    for char in phrase:
        if char == '"':
            subprocess.run(['osascript', '-e', 'tell application "System Events" to keystroke "\\""'])
        else:
            subprocess.run(['osascript', '-e', f'tell application "System Events" to keystroke "{char}"'])
        time.sleep(0.08)
    
    time.sleep(2)
    print("Closing Safari...")
    subprocess.run(['osascript', '-e', 'tell application "Safari" to close current tab of window 1'])

if __name__ == '__main__':
    run()
