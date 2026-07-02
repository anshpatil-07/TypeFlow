import sys
import statistics

def parse_log(filename):
    with open(filename, 'r', errors='replace') as f:
        content = f.read()
    
    blocks = content.split('[DetailedLatency]')
    requests = []
    
    for block in blocks[1:]:
        req = {}
        for line in block.strip().split('\n'):
            line = line.strip()
            
            if '- totalPauseToVisibleMs:' in line:
                val = line.split(':')[-1].strip()
                if val != 'nil': req['totalPauseToVisibleMs'] = float(val)
            elif '- activeLine=' in line:
                req['activeLine'] = line.split("'", 1)[-1].rsplit("'", 1)[0]
            elif '- finalSuggestion=' in line:
                req['finalSuggestion'] = line.split("'", 1)[-1].rsplit("'", 1)[0]
            elif '- boundedPrefixLen:' in line:
                req['boundedPrefixLen'] = int(line.split(':')[-1].strip())
            elif '- promptTokenCount:' in line:
                req['promptTokenCount'] = int(line.split(':')[-1].strip())
            elif '- debounceActualDelayMs:' in line:
                val = line.split(':')[-1].strip()
                if val != 'nil': req['debounceActualDelayMs'] = float(val)
            elif '- promptBuildMs:' in line:
                val = line.split(':')[-1].strip()
                if val != 'nil': req['promptBuildMs'] = float(val)
            elif '- tokenizationMs:' in line:
                val = line.split(':')[-1].strip()
                if val != 'nil': req['tokenizationMs'] = float(val)
            elif '- firstUsableTokenMs:' in line:
                val = line.split(':')[-1].strip()
                if val != 'nil': req['firstUsableTokenMs'] = float(val)
            elif '- renderMs:' in line:
                val = line.split(':')[-1].strip()
                if val != 'nil': req['renderMs'] = float(val)
            elif '- visibleApplied=' in line:
                req['visibleApplied'] = line.split('=')[-1].strip() == 'true'
            elif '- requestQueuedAt:' in line:
                req['queuedAt'] = float(line.split(':')[-1].strip())
            elif '- requestDequeuedAt:' in line:
                req['dequeuedAt'] = float(line.split(':')[-1].strip())
        
        if 'totalPauseToVisibleMs' in req and req.get('visibleApplied'):
            req['queueWaitMs'] = (req.get('dequeuedAt', 0) - req.get('queuedAt', 0)) * 1000.0
            requests.append(req)
            
    # Calculate stats
    latencies = sorted([r['totalPauseToVisibleMs'] for r in requests])
    first_tokens = sorted([r.get('firstUsableTokenMs', 0) for r in requests if 'firstUsableTokenMs' in r])
    renders = sorted([r.get('renderMs', 0) for r in requests if 'renderMs' in r])
    
    if not latencies:
        print(f"{filename} - No visible latencies found.")
        return
        
    def get_percentiles(data):
        return {
            'avg': sum(data)/len(data),
            'p50': statistics.median(data),
            'p90': data[int(len(data)*0.9)] if len(data) >= 10 else data[-1],
            'max': data[-1]
        }
    
    lat = get_percentiles(latencies)
    ft = get_percentiles(first_tokens)
    rd = get_percentiles(renders)
    
    print(f"=== {filename} ===")
    print(f"Total Visible Completions: {len(latencies)}")
    print(f"totalPauseToVisibleMs avg/p50/p90/max: {lat['avg']:.1f} / {lat['p50']:.1f} / {lat['p90']:.1f} / {lat['max']:.1f}")
    print(f"firstUsableTokenMs avg/p50/p90/max: {ft['avg']:.1f} / {ft['p50']:.1f} / {ft['p90']:.1f} / {ft['max']:.1f}")
    print(f"renderMs avg/p50/p90/max: {rd['avg']:.1f} / {rd['p50']:.1f} / {rd['p90']:.1f} / {rd['max']:.1f}")
    
if __name__ == '__main__':
    args = sys.argv[1:] if len(sys.argv) > 1 else ['typeflow_live.log']
    for arg in args:
        parse_log(arg)
