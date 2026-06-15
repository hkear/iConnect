import http.server, urllib.request, urllib.error, sys, subprocess, json, re

API  = "http://127.0.0.1:1996"
HTML = "http://127.0.0.1:1995"
CLI  = "/opt/iconnect/iconnect-cli"

# Cache CLI results for 3 seconds to avoid excessive calls
_cache = {"time": 0, "peers": "", "routes": "", "node": "", "tun": ""}

def _refresh_cache():
    now = __import__("time").time()
    if now - _cache["time"] < 3:
        return
    _cache["time"] = now
    try:
        _cache["peers"] = subprocess.run([CLI,"peer","list"], capture_output=True, text=True, timeout=5).stdout.strip()
    except: pass
    try:
        _cache["routes"] = subprocess.run([CLI,"route","list"], capture_output=True, text=True, timeout=5).stdout.strip()
    except: pass
    try:
        _cache["node"] = subprocess.run([CLI,"node","info"], capture_output=True, text=True, timeout=5).stdout.strip()
    except: pass
    try:
        for line in subprocess.run(["ip","addr","show","tun0"], capture_output=True, text=True).stdout.split("\n"):
            if "inet " in line: _cache["tun"] = line.strip().split()[1]; break
    except: pass

def get_peer_count():
    _refresh_cache()
    peers = _cache["peers"]
    if not peers: return 0
    return len([p for p in peers.split("\n") if p.strip()])

def gen_fake_devices():
    """Generate device entries from real peer data"""
    _refresh_cache()
    peers = _cache["peers"]
    devices = []
    for line in peers.split("\n"):
        line = line.strip()
        if not line or line.startswith("Peer"):
            continue
        # Parse peer line like: "3493224363    10.126.126.1     hostname      Online    13ms"
        parts = line.split()
        if len(parts) >= 2:
            dev = {
                "machine_id": parts[0] if len(parts) > 0 else "unknown",
                "hostname": parts[2] if len(parts) > 2 else parts[0],
                "easytier_version": "iConnect",
                "running_network_count": 1,
                "running_network_instances": ["iconnect-instance-1"],
                "location": None
            }
            devices.append(dev)
    return devices

def is_auth(headers):
    cookie = headers.get("cookie", "")
    if not cookie: return False
    try:
        req = urllib.request.Request(API + "/api/v1/summary")
        req.add_header("Cookie", cookie)
        resp = urllib.request.urlopen(req, timeout=5)
        return resp.status == 200
    except urllib.error.HTTPError as e:
        return e.code == 200
    except:
        return False

class Proxy(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def _cors(self, origin=None):
        ao = origin or self.headers.get("origin", "*")
        self.send_header("Access-Control-Allow-Origin", ao)
        self.send_header("Access-Control-Allow-Credentials", "true")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, Cookie")

    def do_GET(self):
        if self.path == "/status":
            self._serve_status()
        elif self.path == "/api/v1/summary":
            self._inject_summary()
        elif self.path == "/api/v1/machines" or self.path == "/api/v1/devices":
            self._inject_devices()
        elif self.path == "/api/network-status":
            self._serve_network_api()
        elif self.path.startswith("/api/") or self.path == "/api_meta.js":
            self._proxy("GET", API)
        else:
            self._proxy("GET", HTML)

    def do_POST(self):   self._proxy("POST", API)
    def do_PUT(self):    self._proxy("PUT", API)
    def do_DELETE(self): self._proxy("DELETE", API)

    def do_OPTIONS(self):
        self.send_response(204); self._cors(); self.end_headers()

    # --- Injected endpoints ---

    def _inject_summary(self):
        """Replace /api/v1/summary with real peer count"""
        if not is_auth(self.headers):
            self._proxy("GET", API); return
        count = get_peer_count()
        resp = json.dumps({"device_count": count})
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self._cors()
        self.end_headers()
        self.wfile.write(resp.encode())

    def _inject_devices(self):
        """Replace /api/v1/machines with real peer list"""
        if not is_auth(self.headers):
            self._proxy("GET", API); return
        devices = gen_fake_devices()
        resp = json.dumps(devices, ensure_ascii=False)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self._cors()
        self.end_headers()
        self.wfile.write(resp.encode())

    # --- Network status endpoints ---

    def _serve_network_api(self):
        if not is_auth(self.headers):
            self.send_response(401)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"error":"Unauthorized"}')
            return
        _refresh_cache()
        data = {"tun_ip": _cache["tun"], "node": _cache["node"],
                "peers": _cache["peers"], "routes": _cache["routes"],
                "peer_count": get_peer_count()}
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self._cors()
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False, indent=2).encode())

    def _serve_status(self):
        if not is_auth(self.headers):
            self.send_response(401)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"""<!DOCTYPE html><html><head><meta charset=utf-8><title>Login Required</title>
<style>body{font-family:sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;background:#1a1a2e;color:#e0e0e0}
.box{background:#16213e;padding:30px;border-radius:10px;text-align:center}a{color:#00d4ff}</style></head>
<body><div class="box"><h2>Login Required</h2><p>Please <a href="/">login</a> first.</p></div></body></html>""")
            return
        _refresh_cache()
        count = get_peer_count()
        html = f"""<!DOCTYPE html><html><head><meta charset=utf-8><title>iConnect Network</title>
<meta http-equiv="refresh" content="10">
<style>*{{margin:0;padding:0;box-sizing:border-box}}
body{{font-family:system-ui,-apple-system,sans-serif;background:#0f172a;color:#e2e8f0;padding:24px;min-height:100vh}}
h1{{color:#38bdf8;margin-bottom:24px;font-size:1.5rem}}
.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:16px}}
.card{{background:#1e293b;border:1px solid #334155;border-radius:12px;padding:20px}}
.card h2{{color:#38bdf8;font-size:1rem;margin-bottom:12px;display:flex;align-items:center;gap:8px}}
.card h2 .dot{{width:8px;height:8px;border-radius:50%}}
.dot.green{{background:#22c55e;box-shadow:0 0 6px #22c55e}}
pre{{font-family:monospace;font-size:.85rem;color:#94a3b8;white-space:pre-wrap;line-height:1.5}}
.badge{{display:inline-block;background:#1e40af;color:#93c5fd;border-radius:20px;padding:2px 10px;font-size:.75rem}}
.footer{{text-align:center;color:#475569;margin-top:24px;font-size:.8rem}}a{{color:#38bdf8}}
</style></head><body>
<h1>iConnect Network Status</h1>
<div class="grid">
<div class="card"><h2><span class="dot green"></span> Core Server</h2><pre>TUN: {_cache['tun']}</pre><pre>{_cache['node']}</pre></div>
<div class="card"><h2><span class="dot green"></span> Peers <span class="badge">{count} online</span></h2><pre>{_cache['peers'] or 'No peers'}</pre></div>
<div class="card"><h2>Routes</h2><pre>{_cache['routes'] or 'No routes'}</pre></div>
</div>
<div class="footer">Auto-refresh: 10s | <a href="/">Web Panel</a></div>
</body></html>"""
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(html.encode())

    # --- Generic proxy ---
    def _proxy(self, method, target_host):
        path = self.path
        target = target_host + path
        origin = self.headers.get("origin", "")
        try:
            data = None
            if method in ("POST", "PUT"):
                length = int(self.headers.get("Content-Length", 0))
                if length > 0: data = self.rfile.read(length)
            req = urllib.request.Request(target, data=data, method=method)
            for k, v in self.headers.items():
                if k.lower() not in ("host", "origin", "referer"):
                    req.add_header(k, v)
            if "cookie" in self.headers:
                req.add_header("Cookie", self.headers["cookie"])
            try:
                resp = urllib.request.urlopen(req, timeout=30)
            except urllib.error.HTTPError as e:
                body = e.read()
                self.send_response(e.code)
                for k, v in e.headers.items():
                    if k.lower() not in ("transfer-encoding","access-control-allow-origin","access-control-allow-credentials"):
                        self.send_header(k, v)
                self._cors(origin)
                self.end_headers()
                self.wfile.write(body)
                return
            body = resp.read()
            self.send_response(resp.status)
            for k, v in resp.headers.items():
                if k.lower() not in ("transfer-encoding","access-control-allow-origin","access-control-allow-credentials"):
                    self.send_header(k, v)
            self._cors(origin)
            self.end_headers()
            self.wfile.write(body)
            resp.close()
        except Exception as e:
            self.send_response(502)
            self._cors(origin)
            self.end_headers()
            self.wfile.write(f"Proxy error: {e}".encode())

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 1994
    http.server.HTTPServer(("0.0.0.0", port), Proxy).serve_forever()
