import http.server, urllib.request, urllib.error, sys, json, subprocess, time

API="http://127.0.0.1:1996"
HTML="http://127.0.0.1:1995"
CLI="/opt/iconnect/iconnect-cli"
_cache={"t":0,"c":0,"d":[]}

def refresh():
    n=time.time()
    if n-_cache["t"]<5: return
    _cache["t"]=n
    import hashlib
    from datetime import datetime, timezone, timedelta
    try:
        raw=subprocess.run([CLI,"peer","list"],capture_output=True,text=True,timeout=5).stdout.strip()
        c=0;devs=[]
        for l in raw.split("\n"):
            l=l.strip()
            if not l or l[0]!="|" or "ipv4" in l or "---" in l: continue
            p=[x.strip() for x in l.split("|") if x.strip()]
            if len(p)>=2:
                c+=1;hn=p[1];h=hashlib.md5(hn.encode()).hexdigest()
                u={"part1":int(h[0:8],16),"part2":int(h[8:12],16),"part3":int(h[12:16],16),"part4":int(h[16:32],16)}
                devs.append({"info":{"hostname":hn,"machine_id":u,"running_network_instances":[{"part1":1,"part2":1,"part3":1,"part4":1}],"easytier_version":p[8] if len(p)>8 else "iConnect","report_time":datetime.now(timezone(timedelta(hours=8))).isoformat()},"client_url":"121.4.21.208:1993","location":None})
        _cache["c"]=c;_cache["d"]=devs
    except: pass

class P(http.server.BaseHTTPRequestHandler):
    def log_message(self,*a):pass
    def _c(self,o=None):
        a=o or self.headers.get("origin","*")
        self.send_header("Access-Control-Allow-Origin",a)
        self.send_header("Access-Control-Allow-Credentials","true")
        self.send_header("Access-Control-Allow-Methods","GET,POST,PUT,DELETE,OPTIONS")
        self.send_header("Access-Control-Allow-Headers","Content-Type,Authorization,Cookie")
    def do_GET(self):
        if self.path.startswith("/api/v1/summary"):
            refresh();self._j({"device_count":_cache["c"]})
        elif self.path.startswith("/api/v1/machines"):
            refresh();self._j({"machines":_cache["d"]})
        elif self.path.startswith("/api/") or self.path=="/api_meta.js":
            self._p("GET",API)
        else:
            self._p("GET",HTML)
    def do_POST(self):self._p("POST",API)
    def do_PUT(self):self._p("PUT",API)
    def do_DELETE(self):self._p("DELETE",API)
    def do_OPTIONS(self):self.send_response(204);self._c();self.end_headers()
    def _j(self,d):
        self.send_response(200);self.send_header("Content-Type","application/json")
        self._c();self.end_headers()
        self.wfile.write(json.dumps(d,ensure_ascii=False).encode())
    def _p(self,m,h):
        t=h+self.path;o=self.headers.get("origin","")
        try:
            d=None
            if m in ("POST","PUT"):
                l=int(self.headers.get("Content-Length",0))
                if l>0:d=self.rfile.read(l)
            r=urllib.request.Request(t,data=d,method=m)
            for k,v in self.headers.items():
                if k.lower() not in ("host","origin","referer"):r.add_header(k,v)
            if "cookie" in self.headers:r.add_header("Cookie",self.headers["cookie"])
            try:resp=urllib.request.urlopen(r,timeout=30)
            except urllib.error.HTTPError as e:
                b=e.read();self.send_response(e.code)
                for k,v in e.headers.items():
                    if k.lower() not in ("transfer-encoding","access-control-allow-origin","access-control-allow-credentials"):self.send_header(k,v)
                self._c(o);self.end_headers();self.wfile.write(b);return
            b=resp.read();self.send_response(resp.status)
            for k,v in resp.headers.items():
                if k.lower() not in ("transfer-encoding","access-control-allow-origin","access-control-allow-credentials"):self.send_header(k,v)
            self._c(o);self.end_headers();self.wfile.write(b);resp.close()
        except Exception as e:
            self.send_response(502);self._c(o);self.end_headers()
            self.wfile.write(f"Error: {e}".encode())

if __name__=="__main__":
    http.server.HTTPServer(("0.0.0.0",1994),P).serve_forever()
