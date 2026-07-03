with open('safari_product_benchmark.py', 'r') as f:
    code = f.read()
target = """            safari_eval_javascript(js_tab)
            time.sleep(0.4)
            after_tab = read_editor_text(selector, editor_type)"""
replacement = """            safari_eval_javascript(js_tab)
            time.sleep(0.4)
            osascript('tell application "System Events" to tell process "Safari"\\nkey code 123\\nkey code 124\\nend tell')
            time.sleep(0.1)
            after_tab = read_editor_text(selector, editor_type)"""
code = code.replace(target, replacement)
with open('safari_product_benchmark.py', 'w') as f:
    f.write(code)
