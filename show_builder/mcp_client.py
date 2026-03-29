"""MCP protocol client — the I/O boundary.

Action module: all network communication goes through here.
Single responsibility: send JSON-RPC to QLC+ MCP server, return parsed results.
"""

import json
import time
import urllib.request
import urllib.error


class MCPClient:
    """Streamable HTTP MCP client for QLC+ MCP server."""

    def __init__(self, host="127.0.0.1", port=9696):
        self.url = f"http://{host}:{port}/mcp"
        self.session = None
        self._id = 0

    def connect(self, max_retries=10, retry_delay=2):
        """Initialize MCP session with retry logic."""
        body = json.dumps({
            "jsonrpc": "2.0", "method": "initialize", "id": 1,
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "phase-builder", "version": "2.0"}
            }
        }).encode()
        for attempt in range(max_retries):
            try:
                req = urllib.request.Request(
                    self.url, body, {"Content-Type": "application/json"}
                )
                resp = urllib.request.urlopen(req, timeout=5)
                for h in resp.headers.items():
                    if h[0].lower() == "mcp-session-id":
                        self.session = h[1]
                if not self.session:
                    raise RuntimeError("No MCP session ID in response")
                print(f"  ✓ Connected (session: {self.session[:12]}...)")
                return
            except (ConnectionRefusedError, urllib.error.URLError) as e:
                if attempt < max_retries - 1:
                    print(f"  ⏳ Waiting for server... ({attempt+1}/{max_retries})")
                    time.sleep(retry_delay)
                else:
                    raise RuntimeError(
                        f"Cannot connect to MCP server at {self.url}: {e}"
                    )

    def call(self, tool, args, retries=2):
        """Call an MCP tool and return the parsed result."""
        self._id += 1
        body = json.dumps({
            "jsonrpc": "2.0", "method": "tools/call", "id": self._id,
            "params": {"name": tool, "arguments": args}
        }).encode()
        headers = {
            "Content-Type": "application/json",
            "Mcp-Session-Id": self.session,
        }
        for attempt in range(retries + 1):
            try:
                req = urllib.request.Request(self.url, body, headers)
                resp = urllib.request.urlopen(req, timeout=30)
                r = json.loads(resp.read())
                return json.loads(r["result"]["content"][0]["text"])
            except Exception as e:
                if attempt < retries:
                    print(f"  ⚠ Retry {attempt+1}/{retries}: {e}")
                    time.sleep(1)
                else:
                    raise
