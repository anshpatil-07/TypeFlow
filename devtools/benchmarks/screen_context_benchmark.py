#!/usr/bin/env python3
"""
Screen context product benchmark runner for TypeFlow.
Upgraded to realistic ChatGPT-like complex page with 8+ message blocks,
code snippets, SQL, and long mixed content. Tests 6 cases.
"""

import argparse
import atexit
import json
import os
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
ARTIFACT_DIR = ROOT / "devtools" / "reports" / "benchmark_artifacts" / "screen_context"
PAGES_DIR = ARTIFACT_DIR / "pages"
RESULTS_PATH = ARTIFACT_DIR / "results.jsonl"
DIAGNOSTICS_LOG = os.environ.get("TYPEFLOW_DIAGNOSTICS_LOG", ROOT / "devtools" / "reports" / "benchmark_artifacts" / "typeflow_diagnostics.log")

SAFARI_BENCHMARK_WINDOW_ID = None

def run_command(command, timeout=None, check=False):
    import tempfile
    with tempfile.TemporaryFile(mode="w+") as out, tempfile.TemporaryFile(mode="w+") as err:
        try:
            with subprocess.Popen(command, stdout=out, stderr=err, text=True) as p:
                p.wait(timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            p.kill()
            p.wait()
            raise exc
        out.seek(0)
        err.seek(0)
        stdout_text = out.read()
        stderr_text = err.read()
    if check and p.returncode != 0:
        raise subprocess.CalledProcessError(p.returncode, command, stdout_text, stderr_text)
    return subprocess.CompletedProcess(command, p.returncode, stdout_text, stderr_text)

def osascript(script, timeout=None):
    return run_command(["osascript", "-e", script], timeout=timeout)

def activate_safari():
    osascript('tell application "Safari" to activate', timeout=5)
    osascript('tell application "System Events" to set frontmost of process "Safari" to true', timeout=5)
    osascript(
        'tell application "System Events" to tell process "Safari"\n'
        '  try\n'
        '    click menu item "Hide Sidebar" of menu "View" of menu bar 1\n'
        '  end try\n'
        'end tell',
        timeout=3
    )
    time.sleep(0.15)
    
    osascript(
        'tell application "Safari"\n'
        '  try\n'
        '    set bnds to bounds of front window\n'
        '  on error\n'
        '    return\n'
        '  end try\n'
        'end tell\n'
        'tell application "System Events" to tell process "Safari"\n'
        '  try\n'
        '    click at {(item 1 of bnds) + ((item 3 of bnds) - (item 1 of bnds)) / 2, (item 2 of bnds) + ((item 4 of bnds) - (item 2 of bnds)) / 2}\n'
        '  end try\n'
        'end tell',
        timeout=3
    )
    time.sleep(0.15)

def safari_open_file(page_path):
    global SAFARI_BENCHMARK_WINDOW_ID
    url = page_path.resolve().as_uri()
    # Step 1: activate Safari (fast, no document manipulation)
    osascript('tell application "Safari" to activate', timeout=8)
    time.sleep(0.3)
    # Step 2: open the URL in a new tab/window (don't close existing — avoids slowdown)
    script = (
        'tell application "Safari"\n'
        f'  make new document with properties {{URL:"{url}"}}\n'
        '  delay 0.4\n'
        '  return id of front window\n'
        'end tell'
    )
    result = osascript(script, timeout=20)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Safari open failed")
    SAFARI_BENCHMARK_WINDOW_ID = result.stdout.strip()

def cleanup_safari_window():
    global SAFARI_BENCHMARK_WINDOW_ID
    if not SAFARI_BENCHMARK_WINDOW_ID:
        return
    osascript(
        'tell application "Safari"\n'
        f'  if exists (first window whose id is {SAFARI_BENCHMARK_WINDOW_ID}) then close (first window whose id is {SAFARI_BENCHMARK_WINDOW_ID})\n'
        "end tell",
        timeout=5
    )
    SAFARI_BENCHMARK_WINDOW_ID = None

def safari_eval_javascript(source):
    escaped = source.replace("\\", "\\\\").replace('"', '\\"')
    script = (
        'tell application "Safari"\n'
        '  tell current tab of front window\n'
        f'    do JavaScript "{escaped}"\n'
        "  end tell\n"
        "end tell"
    )
    result = osascript(script, timeout=10)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Safari JavaScript failed")
    return result.stdout.strip()

def wait_for_page_ready(timeout_seconds=5.0):
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            state = safari_eval_javascript("document.readyState")
            if state in {"interactive", "complete"}:
                return
        except Exception:
            pass
        time.sleep(0.1)
    raise RuntimeError("Safari page did not become JS-ready")

def write_page(html_content):
    PAGES_DIR.mkdir(parents=True, exist_ok=True)
    path = PAGES_DIR / "screen_context_benchmark.html"
    
    if 'id="editor"' in html_content and "autofocus" not in html_content:
        html_content = html_content.replace('id="editor"', 'id="editor" autofocus')
    
    focus_script = '<script>window.addEventListener("load", () => { setTimeout(() => { document.querySelector("#editor").focus(); }, 100); });</script>'
    if "</body>" in html_content:
        html_content = html_content.replace("</body>", f"{focus_script}</body>")
    else:
        html_content += focus_script
        
    path.write_text(html_content, encoding="utf-8")
    return path

def focus_and_clear():
    osascript('tell application "System Events" to tell process "Safari" to key code 53', timeout=5)
    time.sleep(0.1)
    js = (
        "{"
        "const el=document.querySelector('#editor');"
        "el.focus(); el.innerText='';"
        "const r = document.createRange();"
        "r.selectNodeContents(el);"
        "r.collapse(false);"
        "const s = window.getSelection();"
        "s.removeAllRanges();"
        "s.addRange(r);"
        "}"
        "'ok';"
    )
    safari_eval_javascript(js)

def refocus_editor():
    osascript('tell application "System Events" to tell process "Safari" to key code 53', timeout=5)
    time.sleep(0.05)
    js = (
        "{"
        "const el=document.querySelector('#editor');"
        "if(el){el.focus();"
        "const r = document.createRange();"
        "r.selectNodeContents(el);"
        "r.collapse(false);"
        "const s = window.getSelection();"
        "s.removeAllRanges();"
        "s.addRange(r);}"
        "}"
        "'ok';"
    )
    safari_eval_javascript(js)

def keystroke_text(text):
    if not text:
        return time.perf_counter()
    if len(text) > 1:
        bulk = text[:-1]
        last = text[-1]
        escaped_bulk = bulk.replace("\\", "\\\\").replace('"', '\\"')
        osascript(f'tell application "System Events" to tell process "Safari" to keystroke "{escaped_bulk}"', timeout=15)
        time.sleep(0.3)
        escaped_last = last.replace("\\", "\\\\").replace('"', '\\"')
        osascript(f'tell application "System Events" to tell process "Safari" to keystroke "{escaped_last}"', timeout=15)
    else:
        escaped = text.replace("\\", "\\\\").replace('"', '\\"')
        osascript(f'tell application "System Events" to tell process "Safari" to keystroke "{escaped}"', timeout=15)
    time.sleep(0.2)
    return time.perf_counter()


def get_latest_diagnostics(since_epoch, line_offset=0):
    log_file = Path(DIAGNOSTICS_LOG)
    if not log_file.exists():
        return {}
    all_lines = log_file.read_text(encoding="utf-8", errors="replace").splitlines()
    lines = all_lines[line_offset:]
    diagnostic = {
        "pageContextCharsRaw": 0,
        "pageContextCharsDeduped": 0,
        "visitedNodes": 0,
        "skippedInputChars": 0,
        "skippedNavChars": 0,
        "cacheHit": True,
        "pageDirectCandidateUsed": False,
        "pageDirectMatchChars": 0,
        "promptCharsAdded": 0,
        "candidateKind": "llm",
        "visibleGhostText": ""
    }
    ghost_visible = False
    visible_ghost_text = ""
    
    for line in lines:
        if "[ScreenContextDiagnostic]" in line:
            # Legacy fields
            m = re.search(r"screenContextAvailable=(\S+)\s+screenContextUsed=(\S+)\s+screenContextChars=(\d+)\s+screenContextSource=(\S+)\s+screenContextReason=(\S+)", line)
            if m:
                diagnostic["screenContextAvailable"] = m.group(1) == "true"
                diagnostic["screenContextUsed"] = m.group(2) == "true"
                diagnostic["screenContextChars"] = int(m.group(3))
                diagnostic["screenContextSource"] = m.group(4)
                diagnostic["screenContextReason"] = m.group(5)
            # New extended fields
            for field, pat in [
                ("pageContextAvailable", r"pageContextAvailable=(\S+)"),
                ("pageContextSource", r"pageContextSource=(\S+)"),
                ("pageContextCharsRaw", r"pageContextCharsRaw=(\d+)"),
                ("pageContextCharsUsed", r"pageContextCharsUsed=(\d+)"),
                ("pageContextUsed", r"pageContextUsed=(\S+)"),
                ("activeInputExcluded", r"activeInputExcluded=(\S+)"),
                ("extractionMs", r"extractionMs=([\d.]+)"),
                ("cacheAgeMs", r"cacheAgeMs=([\d.]+)"),
                ("promptCharsAdded", r"promptCharsAdded=(\d+)"),
                ("promptTokenEstimate", r"promptTokenEstimate=(\d+)"),
            ]:
                fm = re.search(pat, line)
                if fm:
                    val = fm.group(1)
                    if field in ("pageContextAvailable", "pageContextUsed", "activeInputExcluded"):
                        diagnostic[field] = val == "true"
                    elif field in ("pageContextCharsRaw", "pageContextCharsUsed", "promptCharsAdded", "promptTokenEstimate"):
                        try: diagnostic[field] = int(val)
                        except: pass
                    elif field in ("extractionMs", "cacheAgeMs"):
                        try: diagnostic[field] = float(val)
                        except: pass
                    else:
                        diagnostic[field] = val
        
        # PageContextExtractor diagnostics
        if "[PageContextExtractor]" in line:
            diagnostic["cacheHit"] = False
            m_src = re.search(r"source=(\S+)", line)
            m_chars = re.search(r"rawChars=(\d+)", line)
            m_dedup = re.search(r"rawCharsDeduped=(\d+)", line)
            m_nodes = re.search(r"visitedNodes=(\d+)", line)
            m_skip_in = re.search(r"skippedInputChars=(\d+)", line)
            m_skip_nav = re.search(r"skippedNavChars=(\d+)", line)
            m_ms = re.search(r"extractionMs=([\d.]+)", line)
            if m_src: diagnostic["pageContextSource"] = m_src.group(1)
            if m_chars: diagnostic["pageContextCharsRaw"] = int(m_chars.group(1))
            if m_dedup: diagnostic["pageContextCharsDeduped"] = int(m_dedup.group(1))
            if m_nodes: diagnostic["visitedNodes"] = int(m_nodes.group(1))
            if m_skip_in: diagnostic["skippedInputChars"] = int(m_skip_in.group(1))
            if m_skip_nav: diagnostic["skippedNavChars"] = int(m_skip_nav.group(1))
            if m_ms: diagnostic["extractionMs"] = float(m_ms.group(1))

        # PageDirectCandidate diagnostics
        if "[PageDirectCandidate]" in line:
            m_used = re.search(r"used=(\S+)", line)
            m_mchars = re.search(r"matchChars=(\d+)", line)
            if m_used:
                diagnostic["pageDirectCandidateUsed"] = m_used.group(1) == "true"
            if m_mchars:
                diagnostic["pageDirectMatchChars"] = int(m_mchars.group(1))
            if diagnostic["pageDirectCandidateUsed"]:
                diagnostic["candidateKind"] = "pageContextContinuation"

        if "candidateKind=pageContextContinuation" in line:
            diagnostic["candidateKind"] = "pageContextContinuation"
            diagnostic["pageDirectCandidateUsed"] = True

        stripped = line.strip()
        if stripped.startswith("{"):
            try:
                data = json.loads(stripped)
                if "visibleGhostText" in data:
                    ghost_visible = bool(data.get("ghostVisible"))
                    visible_ghost_text = str(data.get("visibleGhostText") or "")
            except json.JSONDecodeError:
                pass
        elif "[VisibleSuggestionAudit]" in line:
            if "decision=visibleApplied" in line:
                ghost_visible = True
                m_ghost = re.search(r"finalSuggestion='([^']*)'", line)
                if m_ghost:
                    visible_ghost_text = m_ghost.group(1)
            elif "decision=rejectedBeforeVisible" in line:
                ghost_visible = False
                visible_ghost_text = ""
    
    diagnostic["ghostVisible"] = ghost_visible
    diagnostic["visibleGhostText"] = visible_ghost_text
    return diagnostic

# ─────────────────────────────────────────────
# COMPLEX ChatGPT-like page HTML template
# 12 message blocks, long prose, Java/Spring Boot code, SQL, nav/header/footer
# A focused textarea at the bottom
# ─────────────────────────────────────────────
COMPLEX_CHATGPT_PAGE = '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>ChatGPT – TypeFlow Benchmark Page</title>
<style>
  body { margin:0; font-family:system-ui,sans-serif; background:#212121; color:#ececec; }
  nav { background:#171717; padding:12px 24px; display:flex; align-items:center; gap:16px; }
  nav .logo { font-weight:700; font-size:18px; color:#fff; }
  nav .nav-links { display:flex; gap:12px; font-size:14px; color:#aaa; }
  .sidebar { position:fixed; top:0; left:0; width:220px; height:100%; background:#171717; padding:60px 0 0; overflow-y:auto; z-index:10; }
  .sidebar .item { padding:10px 16px; font-size:13px; color:#aaa; cursor:pointer; }
  .sidebar .item:hover { background:#2a2a2a; color:#fff; }
  .main { margin-left:220px; max-width:860px; padding:80px 24px 200px; }
  .msg { margin-bottom:28px; display:flex; gap:12px; }
  .msg .avatar { width:32px; height:32px; border-radius:50%; flex-shrink:0; font-size:13px; display:flex; align-items:center; justify-content:center; font-weight:700; }
  .msg .avatar.user { background:#19c37d; color:#000; }
  .msg .avatar.ai { background:#444; color:#fff; }
  .msg .body { flex:1; }
  .msg .body .role { font-size:13px; font-weight:600; color:#888; margin-bottom:4px; }
  .msg .body .content { font-size:15px; line-height:1.65; }
  pre { background:#1a1a1a; border-radius:8px; padding:16px; overflow-x:auto; font-size:13px; line-height:1.5; }
  code { font-family:monospace; }
  .footer-area { position:fixed; bottom:0; left:220px; right:0; background:#212121; padding:16px 24px; }
  .editor-wrap { background:#2a2a2a; border-radius:12px; padding:12px 16px; }
  div[id="editor"] { min-height:44px; max-height:180px; overflow-y:auto; outline:none; font-size:15px; color:#ececec; }
  footer.page-footer { text-align:center; font-size:12px; color:#555; padding:8px; }
</style>
</head>
<body>
<nav>
  <span class="logo">ChatGPT</span>
  <div class="nav-links">
    <span>Explore GPTs</span>
    <span>My GPTs</span>
    <span>API</span>
  </div>
</nav>
<div class="sidebar" role="navigation" aria-label="Chat history">
  <div class="item">Java Spring Boot REST API</div>
  <div class="item">SQL query optimization</div>
  <div class="item">Python ML pipeline</div>
  <div class="item">Docker networking</div>
  <div class="item">React performance tips</div>
  <div class="item">PostgreSQL indexing</div>
</div>
<div class="main" role="main">

  <div class="msg">
    <div class="avatar user">U</div>
    <div class="body">
      <div class="role">You</div>
      <div class="content">I need to build a REST API using Java Spring Boot for a customer management system. Can you show me how to structure the CustomerController and CustomerService?</div>
    </div>
  </div>

  <div class="msg">
    <div class="avatar ai">G</div>
    <div class="body">
      <div class="role">ChatGPT</div>
      <div class="content">
        Sure! Here is a clean Spring Boot REST API structure for a customer management system. We will use layered architecture with a controller, service, repository, and entity.
        <br><br>
        First, the <strong>CustomerController</strong>:
<pre><code>@RestController
@RequestMapping("/api/customers")
public class CustomerController {

    @Autowired
    private CustomerService customerService;

    @GetMapping
    public List&lt;Customer&gt; getAllCustomers() {
        return customerService.findAll();
    }

    @GetMapping("/{id}")
    public ResponseEntity&lt;Customer&gt; getCustomerById(@PathVariable Long id) {
        return customerService.findById(id)
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
    }

    @PostMapping
    public Customer createCustomer(@RequestBody Customer customer) {
        return customerService.save(customer);
    }

    @PutMapping("/{id}")
    public ResponseEntity&lt;Customer&gt; updateCustomer(@PathVariable Long id, @RequestBody Customer details) {
        return customerService.update(id, details)
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
    }

    @DeleteMapping("/{id}")
    public ResponseEntity&lt;Void&gt; deleteCustomer(@PathVariable Long id) {
        customerService.delete(id);
        return ResponseEntity.noContent().build();
    }
}</code></pre>
      </div>
    </div>
  </div>

  <div class="msg">
    <div class="avatar ai">G</div>
    <div class="body">
      <div class="role">ChatGPT</div>
      <div class="content">
        Now the <strong>CustomerService</strong>:
<pre><code>@Service
public class CustomerService {

    @Autowired
    private CustomerRepository customerRepository;

    public List&lt;Customer&gt; findAll() {
        return customerRepository.findAll();
    }

    public Optional&lt;Customer&gt; findById(Long id) {
        return customerRepository.findById(id);
    }

    public Customer save(Customer customer) {
        return customerRepository.save(customer);
    }

    public Optional&lt;Customer&gt; update(Long id, Customer details) {
        return customerRepository.findById(id).map(existing -> {
            existing.setName(details.getName());
            existing.setEmail(details.getEmail());
            existing.setPhone(details.getPhone());
            return customerRepository.save(existing);
        });
    }

    public void delete(Long id) {
        customerRepository.deleteById(id);
    }
}</code></pre>
      </div>
    </div>
  </div>

  <div class="msg">
    <div class="avatar user">U</div>
    <div class="body">
      <div class="role">You</div>
      <div class="content">How do I add pagination support to the getAllCustomers endpoint in the controller?</div>
    </div>
  </div>

  <div class="msg">
    <div class="avatar ai">G</div>
    <div class="body">
      <div class="role">ChatGPT</div>
      <div class="content">
        To add pagination to <code>getAllCustomers</code>, use Spring's <code>Pageable</code> interface:
<pre><code>@GetMapping
public Page&lt;Customer&gt; getAllCustomers(
        @RequestParam(defaultValue = "0") int page,
        @RequestParam(defaultValue = "20") int size,
        @RequestParam(defaultValue = "id") String sortBy) {
    Pageable pageable = PageRequest.of(page, size, Sort.by(sortBy));
    return customerService.findAll(pageable);
}</code></pre>
        And update the service:
<pre><code>public Page&lt;Customer&gt; findAll(Pageable pageable) {
    return customerRepository.findAll(pageable);
}</code></pre>
      </div>
    </div>
  </div>

  <div class="msg">
    <div class="avatar user">U</div>
    <div class="body">
      <div class="role">You</div>
      <div class="content">Now show me the SQL schema for the customers table, including indexes for email and phone lookup.</div>
    </div>
  </div>

  <div class="msg">
    <div class="avatar ai">G</div>
    <div class="body">
      <div class="role">ChatGPT</div>
      <div class="content">
        Here is the PostgreSQL schema with proper indexes:
<pre><code>CREATE TABLE customers (
    id          BIGSERIAL PRIMARY KEY,
    name        VARCHAR(255) NOT NULL,
    email       VARCHAR(255) NOT NULL UNIQUE,
    phone       VARCHAR(50),
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    status      VARCHAR(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE','SUSPENDED'))
);

CREATE INDEX idx_customers_email ON customers (email);
CREATE INDEX idx_customers_phone ON customers (phone);
CREATE INDEX idx_customers_status ON customers (status);
CREATE INDEX idx_customers_created_at ON customers (created_at DESC);

-- Partial index for active customers only (common query pattern)
CREATE INDEX idx_customers_active ON customers (email) WHERE status = 'ACTIVE';</code></pre>
        For common lookup queries:
<pre><code>-- Find customer by email
SELECT id, name, email, phone, status
FROM customers
WHERE email = 'john.doe@example.com' AND status = 'ACTIVE';

-- Find all active customers paginated
SELECT id, name, email, phone, created_at
FROM customers
WHERE status = 'ACTIVE'
ORDER BY created_at DESC
LIMIT 20 OFFSET 0;</code></pre>
      </div>
    </div>
  </div>

  <div class="msg">
    <div class="avatar user">U</div>
    <div class="body">
      <div class="role">You</div>
      <div class="content">What about integration tests for the CustomerController using MockMvc?</div>
    </div>
  </div>

  <div class="msg">
    <div class="avatar ai">G</div>
    <div class="body">
      <div class="role">ChatGPT</div>
      <div class="content">
        Here is a complete MockMvc integration test for the CustomerController:
<pre><code>@SpringBootTest
@AutoConfigureMockMvc
@Transactional
public class CustomerControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private CustomerRepository customerRepository;

    @BeforeEach
    void setUp() {
        customerRepository.deleteAll();
    }

    @Test
    void testCreateCustomer() throws Exception {
        Customer customer = new Customer("Alice Smith", "alice@example.com", "+1-555-0100");

        mockMvc.perform(post("/api/customers")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(customer)))
               .andExpect(status().isOk())
               .andExpect(jsonPath("$.name").value("Alice Smith"))
               .andExpect(jsonPath("$.email").value("alice@example.com"));
    }

    @Test
    void testGetAllCustomers_Paginated() throws Exception {
        customerRepository.save(new Customer("Bob Jones", "bob@example.com", "+1-555-0101"));
        customerRepository.save(new Customer("Carol Lee", "carol@example.com", "+1-555-0102"));

        mockMvc.perform(get("/api/customers?page=0&amp;size=10"))
               .andExpect(status().isOk())
               .andExpect(jsonPath("$.content.length()").value(2));
    }
}</code></pre>
      </div>
    </div>
  </div>

  <div class="msg">
    <div class="avatar ai">G</div>
    <div class="body">
      <div class="role">ChatGPT</div>
      <div class="content">
        To summarize the full architecture: the CustomerController handles HTTP requests and delegates to CustomerService which contains the business logic. The CustomerRepository extends JpaRepository for database access. The SQL schema uses BIGSERIAL primary keys with multiple indexes for fast lookup. Use MockMvc with @SpringBootTest for integration testing to verify endpoint behavior end-to-end.
        <br><br>
        The most important performance consideration is to always use paginated queries when listing customers to avoid full table scans on large datasets. The partial index on active customers ensures that the most common query pattern (filtering by status = ACTIVE) is always fast.
      </div>
    </div>
  </div>

</div>
<div class="footer-area" role="complementary">
  <div class="editor-wrap">
    <div id="editor" contenteditable="true" role="textbox" aria-label="Message input" aria-multiline="true"></div>
  </div>
  <div style="text-align:center;font-size:12px;color:#555;margin-top:8px;">ChatGPT can make mistakes. Consider checking important information.</div>
</div>
<footer class="page-footer">TypeFlow Benchmark Test Page &bull; Not for distribution</footer>
</body>
</html>'''

UNRELATED_PAGE = '''<!doctype html><html><head><title>Cooking Recipes</title></head>
<body style="font-family:sans-serif;padding:24px;">
<h1>Best Italian Pizza Recipes</h1>
<p>Making authentic Neapolitan pizza at home requires high-quality ingredients. Start with 00 flour for the perfect crust texture.</p>
<p>For the tomato sauce, use San Marzano tomatoes crushed by hand. Add fresh basil, garlic, and a drizzle of extra virgin olive oil.</p>
<p>The dough should rest for at least 24 hours in the refrigerator to develop flavor. Cook at maximum temperature, ideally 450°C in a wood-fired oven.</p>
<p>Top with fresh buffalo mozzarella and add basil after baking. Never use dried herbs on authentic Margherita pizza.</p>
<p>Recommended toppings: prosciutto, arugula, cherry tomatoes, burrata, truffle oil, anchovies, capers, olives.</p>
<h2>Side dishes</h2>
<p>Pair with a simple arugula salad dressed with lemon and olive oil. Tiramisu makes an excellent dessert.</p>
<div contenteditable="true" id="editor" style="border:1px solid #ccc;padding:12px;min-height:48px;margin-top:24px;border-radius:6px;"></div>
</body></html>'''


LAST_RAW_CHARS = 0
LAST_DEDUP_CHARS = 0
LAST_VISITED_NODES = 0

def run_case(name, html_content, typed_prefix, expected_keywords, should_use_context, require_chars_between=None):
    global LAST_RAW_CHARS, LAST_DEDUP_CHARS, LAST_VISITED_NODES
    print(f"Running Case: {name}")
    page_path = write_page(html_content)
    safari_open_file(page_path)
    wait_for_page_ready()
    activate_safari()
    focus_and_clear()
    time.sleep(0.8)  # allow AX tree to stabilize after page load
    
    log_file = Path(DIAGNOSTICS_LOG)
    log_line_offset = 0
    if log_file.exists():
        log_line_offset = len(log_file.read_text(encoding="utf-8", errors="replace").splitlines())
    
    start_time = time.time()
    keystroke_text(typed_prefix)
    refocus_editor()
    time.sleep(2.0)  # debounce + generation time
    
    diag = get_latest_diagnostics(start_time, line_offset=log_line_offset)
    elapsed = (time.time() - start_time) * 1000.0
    
    actual_sug = diag.get("visibleGhostText", "")
    sug_words = actual_sug.split()
    
    # Use new pageContext fields if available, fall back to screenContext fields
    page_used = diag.get("pageContextUsed", diag.get("screenContextUsed", False)) or diag.get("pageDirectCandidateUsed", False)
    page_source = diag.get("pageContextSource", diag.get("screenContextSource", "unknown"))
    page_chars_raw = diag.get("pageContextCharsRaw", diag.get("screenContextChars", 0))
    page_chars_deduped = diag.get("pageContextCharsDeduped", 0)
    visited_nodes = diag.get("visitedNodes", 0)

    # Cache hit metrics carryover
    if page_chars_raw > 0:
        LAST_RAW_CHARS = page_chars_raw
    else:
        page_chars_raw = LAST_RAW_CHARS

    if page_chars_deduped > 0:
        LAST_DEDUP_CHARS = page_chars_deduped
    else:
        page_chars_deduped = LAST_DEDUP_CHARS

    if visited_nodes > 0:
        LAST_VISITED_NODES = visited_nodes
    else:
        visited_nodes = LAST_VISITED_NODES

    page_chars_used = diag.get("pageContextCharsUsed", diag.get("screenContextChars", 0))
    if page_chars_used == 0 and diag.get("pageDirectMatchChars", 0) > 0:
        page_chars_used = diag.get("pageDirectMatchChars", 0)
    extraction_ms = diag.get("extractionMs", 0.0)

    
    passed = True
    fail_reason = ""
    
    if should_use_context and not page_used:
        passed = False
        fail_reason += "Expected pageContextUsed=True but got False. "
    elif not should_use_context and page_used:
        passed = False
        fail_reason += "Expected pageContextUsed=False but got True. "

    if should_use_context and require_chars_between:
        lo, hi = require_chars_between
        if not (lo <= page_chars_used <= hi):
            passed = False
            fail_reason += f"pageContextCharsUsed={page_chars_used} out of expected range [{lo},{hi}]. "

    if should_use_context:
        matched = any(kw.lower() in actual_sug.lower() for kw in expected_keywords)
        if not matched and passed:
            passed = False
            fail_reason += f"Actual suggestion '{actual_sug}' did not contain any expected keywords {expected_keywords}. "

    # Fail if benchmark page yielded fewer than 3000 raw chars for positive cases
    if should_use_context and page_chars_raw < 3000:
        passed = False
        fail_reason += f"pageContextCharsRaw={page_chars_raw} too low (expected >= 3000). "

    # Verify if direct page-context candidate was used for cases where we expect direct matching
    page_direct_used = diag.get("pageDirectCandidateUsed", False)
    page_direct_match_chars = diag.get("pageDirectMatchChars", 0)
    candidate_kind = diag.get("candidateKind", "llm")
    prompt_chars_added = diag.get("promptCharsAdded", 0)
    cache_hit = diag.get("cacheHit", True)
    page_chars_deduped = diag.get("pageContextCharsDeduped", 0)
    visited_nodes = diag.get("visitedNodes", 0)

    res = {
        "caseName": name,
        "pageContextAvailable": diag.get("pageContextAvailable", False),
        "pageContextUsed": page_used,
        "pageContextSource": page_source,
        "pageContextCharsRaw": page_chars_raw,
        "pageContextCharsDeduped": page_chars_deduped,
        "visitedNodes": visited_nodes,
        "extractionMs": round(extraction_ms, 1),
        "cacheHit": cache_hit,
        "pageDirectCandidateUsed": page_direct_used,
        "pageDirectMatchChars": page_direct_match_chars,
        "promptCharsAdded": prompt_chars_added,
        "expectedNextWords": expected_keywords,
        "actualSuggestion": actual_sug,
        "candidateKind": candidate_kind,
        "latencyMs": round(elapsed, 0),
        "passed": passed,
        "failReason": fail_reason or "none"
    }

    status = "PASS" if passed else "FAIL"
    print(f"  Result: {status} (pageUsed={page_used}, source={page_source}, charsRaw={page_chars_raw}, charsDeduped={page_chars_deduped}, visitedNodes={visited_nodes}, extractionMs={extraction_ms:.1f}ms, directUsed={page_direct_used}, kind={candidate_kind}, sug='{actual_sug[:40]}')")
    if not passed:
        print(f"  Fail Reason: {fail_reason}")
    cleanup_safari_window()
    time.sleep(0.5)
    return res



def run():
    atexit.register(cleanup_safari_window)
    RESULTS_PATH.parent.mkdir(parents=True, exist_ok=True)
    
    results = []
    
    # Case 1: Verbatim chat-page continuation (uses pageContextContinuation)
    res1 = run_case(
        "ChatGPT chat continuation",
        COMPLEX_CHATGPT_PAGE,
        "The most important performance consideration is to always use paginated ",
        ["queries", "listing", "customers", "avoid"],
        should_use_context=True,
        require_chars_between=(0, 1000)
    )
    results.append(res1)

    # Case 2: Mid-word page continuation (uses pageContextContinuation)
    res2 = run_case(
        "Java Spring Boot controller context",
        COMPLEX_CHATGPT_PAGE,
        "the CustomerController handles HTTP requests and delegates to CustomerS",
        ["ervice", "business", "logic", "CustomerService"],
        should_use_context=True,
        require_chars_between=(0, 1000)
    )
    results.append(res2)

    # Case 3: Long ChatGPT page
    res3 = run_case(
        "SQL schema context",
        COMPLEX_CHATGPT_PAGE,
        "CREATE TABLE customers (",
        ["BIGSERIAL", "PRIMARY KEY", "email", "VARCHAR", "created_at"],
        should_use_context=True,
        require_chars_between=(0, 1000)
    )
    results.append(res3)

    # Case 4: Java/Spring Boot context
    res4 = run_case(
        "Spring Boot pagination context",
        COMPLEX_CHATGPT_PAGE,
        "Pageable pageable = PageRequest.of(page, size, Sort.by(",
        ["sortBy", "pageRequest", "sort", "pageable", "PageRequest"],
        should_use_context=True,
        require_chars_between=(0, 1000)
    )
    results.append(res4)

    # Case 5: SQL context
    res5 = run_case(
        "MockMvc integration test context",
        COMPLEX_CHATGPT_PAGE,
        "Use MockMvc with @SpringBootTest for integration testing to verify endpoint behavior ",
        ["end-to-end", "endpoint", "behavior", "testing"],
        should_use_context=True,
        require_chars_between=(0, 1000)
    )
    results.append(res5)
    
    # Case 6: Negative unrelated page
    res6 = run_case(
        "Negative unrelated page",
        UNRELATED_PAGE,
        "The new Spring Boot version has ",
        ["pizza", "sauce", "cheese", "mozzarella", "recipe"],
        should_use_context=False
    )
    results.append(res6)
    
    with open(RESULTS_PATH, "w") as f:
        for r in results:
            f.write(json.dumps(r) + "\n")
    
    # Determine overall result
    total = len(results)
    passed_count = sum(1 for r in results if r["passed"])
    
    # Fail if direct page-context candidate was not tested/used in at least one positive case
    direct_tested = any(r.get("pageDirectCandidateUsed", False) for r in results)
    if not direct_tested:
        print("\nFAIL: Direct page-context candidate path was never triggered or used in positive cases!")
        # Force fail first case to make the build report fail
        results[0]["passed"] = False
        passed_count = sum(1 for r in results if r["passed"])

    print("\n━━━━ Upgraded Screen Context Benchmark Results ━━━━")
    # Table columns:
    # case, pageContextCharsRaw, pageContextCharsDeduped, visitedNodes, extractionMs, cacheHit,
    # pageDirectCandidateUsed, pageDirectMatchChars, promptCharsAdded, expectedNextWords,
    # actualSuggestion, candidateKind, latencyMs, pass/fail reason
    print(f"{'Case':<32} | {'Raw':<5} | {'Dedup':<5} | {'Nodes':<5} | {'ExtrMs':<6} | {'Hit':<4} | {'DirUsed':<7} | {'DirCh':<5} | {'Prompt':<6} | {'Kind':<15} | {'Lat':<5} | {'Pass':<4}")
    print("─" * 125)
    for r in results:
        status = "PASS" if r["passed"] else "FAIL"
        print(f"{r['caseName'][:32]:<32} | {r['pageContextCharsRaw']:<5} | {r['pageContextCharsDeduped']:<5} | {r['visitedNodes']:<5} | {r['extractionMs']:<6} | {str(r['cacheHit'])[:4]:<4} | {str(r['pageDirectCandidateUsed'])[:7]:<7} | {r['pageDirectMatchChars']:<5} | {r['promptCharsAdded']:<6} | {r['candidateKind']:<15} | {r['latencyMs']:<5} | {status:<4}")
    print("─" * 125)
    print(f"Result: {passed_count}/{total} passed")
    
    return passed_count, total


if __name__ == "__main__":
    run()
