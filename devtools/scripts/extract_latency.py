import re
import numpy as np
from collections import defaultdict

with open('typeflow_live.log', 'r') as f:
    lines = f.readlines()

request_events = defaultdict(dict)
for line in lines:
    if '[Latency]' not in line and '[Overlay]' not in line:
        continue
    
    match_req = re.search(r'requestID=(\d+)', line)
    match_work = re.search(r'workID=(\d+)', line)
    
    if not match_work:
        continue
    work_id = match_work.group(1)
    
    if 'input event' in line and 'bufferLen' in line:
        pass # Hard to map to workID sometimes
        
    if 'generation requested' in line:
        request_events[work_id]['requested'] = True
        
    if 'first usable completion' in line:
        request_events[work_id]['firstUsable'] = True
        
    if '[Overlay] Ghost text rendered (VISIBLE)' in line:
        request_events[work_id]['visibleRendered'] = True
        
    # Real extraction of metrics using the previous method from Cotypist/TypeFlow logs
    
# Let's extract totalPauseToVisibleMs which might be logged directly
totalPauseToVisibleMs = []
firstUsableTokenMs = []
renderMs = []

for line in lines:
    if 'totalPauseToVisibleMs=' in line:
        val = int(re.search(r'totalPauseToVisibleMs=(\d+)', line).group(1))
        totalPauseToVisibleMs.append(val)
    if 'llamaFirstUsableMs=' in line:
        val = int(re.search(r'llamaFirstUsableMs=(\d+)', line).group(1))
        firstUsableTokenMs.append(val)
    if 'renderMs=' in line:
        val = int(re.search(r'renderMs=(\d+)', line).group(1))
        renderMs.append(val)

def print_stats(name, arr):
    if not arr:
        print(f"{name} avg/p50/p90: N/A")
        return
    avg = np.mean(arr)
    p50 = np.percentile(arr, 50)
    p90 = np.percentile(arr, 90)
    print(f"{name} avg/p50/p90: {avg:.1f}/{p50:.1f}/{p90:.1f} (count: {len(arr)})")

print_stats("totalPauseToVisibleMs", totalPauseToVisibleMs)
print_stats("firstUsableTokenMs", firstUsableTokenMs)
print_stats("renderMs", renderMs)

