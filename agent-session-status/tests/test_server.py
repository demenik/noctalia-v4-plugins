import json
import os
import sys
import unittest


PLUGIN_DIR = os.path.dirname(os.path.dirname(__file__))
sys.path.insert(0, PLUGIN_DIR)

import server


class SessionStoreTest(unittest.TestCase):
    def setUp(self):
        self.store = server.SessionStore()

    def test_upserts_session_by_agent_and_id(self):
        first = self.store.upsert("codex", {
            "id": "s1",
            "title": "Initial title",
            "status": "running",
        })
        second = self.store.upsert("codex", {
            "id": "s1",
            "title": "Updated title",
            "status": "blocked",
        })

        self.assertEqual(first["id"], "s1")
        self.assertEqual(second["title"], "Updated title")
        self.assertEqual(second["status"], "blocked")
        self.assertEqual(len(self.store.snapshot()["agents"][0]["sessions"]), 1)

    def test_running_count_only_counts_running_sessions(self):
        self.store.upsert("codex", {"id": "a", "title": "A", "status": "running"})
        self.store.upsert("codex", {"id": "b", "title": "B", "status": "blocked"})
        self.store.upsert("claude", {"id": "c", "title": "C", "status": "completed"})

        self.assertEqual(self.store.snapshot()["runningCount"], 1)


class McpRequestTest(unittest.TestCase):
    def setUp(self):
        self.store = server.SessionStore()

    def request(self, body, headers=None, token="secret", method="POST", path="/mcp"):
        return server.handle_request(
            self.store,
            token,
            method,
            path,
            headers or {},
            json.dumps(body).encode("utf-8") if body is not None else b"",
        )

    def test_initialize_returns_mcp_capabilities(self):
        status, _, body = self.request({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-06-18",
                "clientInfo": {"name": "test", "version": "1.0.0"},
                "capabilities": {},
            },
        })

        self.assertEqual(status, 200)
        self.assertEqual(body["jsonrpc"], "2.0")
        self.assertEqual(body["id"], 1)
        self.assertIn("tools", body["result"]["capabilities"])
        self.assertIn("prompts", body["result"]["capabilities"])
        self.assertIn("report_session", body["result"]["instructions"])

    def test_tools_list_exposes_session_tools(self):
        status, _, body = self.request({
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list",
        })

        self.assertEqual(status, 200)
        names = [tool["name"] for tool in body["result"]["tools"]]
        self.assertEqual(names, ["report_session", "list_sessions"])
        self.assertIn("task start", body["result"]["tools"][0]["description"])

    def test_prompts_expose_usage_instructions(self):
        status, _, body = self.request({
            "jsonrpc": "2.0",
            "id": 7,
            "method": "prompts/list",
        })

        self.assertEqual(status, 200)
        self.assertEqual(body["result"]["prompts"][0]["name"], "agent-session-reporting")

        status, _, body = self.request({
            "jsonrpc": "2.0",
            "id": 8,
            "method": "prompts/get",
            "params": {
                "name": "agent-session-reporting",
            },
        })

        self.assertEqual(status, 200)
        text = body["result"]["messages"][0]["content"]["text"]
        self.assertIn("X-Agent", text)
        self.assertIn("completed", text)

    def test_report_session_requires_authorization(self):
        status, _, body = self.request({
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {
                "name": "report_session",
                "arguments": {"id": "s1", "title": "Title", "status": "running"},
            },
        }, {"X-Agent": "codex"})

        self.assertEqual(status, 200)
        self.assertEqual(body["error"]["code"], -32001)

    def test_report_session_requires_agent_header(self):
        status, _, body = self.request({
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {
                "name": "report_session",
                "arguments": {"id": "s1", "title": "Title", "status": "running"},
            },
        }, {"Authorization": "Bearer secret"})

        self.assertEqual(status, 200)
        self.assertEqual(body["error"]["code"], -32602)
        self.assertIn("X-Agent", body["error"]["message"])

    def test_report_session_accepts_authorized_update(self):
        status, _, body = self.request({
            "jsonrpc": "2.0",
            "id": 5,
            "method": "tools/call",
            "params": {
                "name": "report_session",
                "arguments": {"id": "s1", "title": "Title", "status": "running"},
            },
        }, {"Authorization": "Bearer secret", "X-Agent": "codex"})

        self.assertEqual(status, 200)
        text = body["result"]["content"][0]["text"]
        payload = json.loads(text)
        self.assertEqual(payload["session"]["agent"], "codex")
        self.assertEqual(payload["snapshot"]["runningCount"], 1)

    def test_list_sessions_returns_snapshot(self):
        self.store.upsert("codex", {"id": "s1", "title": "Title", "status": "running"})

        status, _, body = self.request({
            "jsonrpc": "2.0",
            "id": 6,
            "method": "tools/call",
            "params": {
                "name": "list_sessions",
                "arguments": {},
            },
        }, {"Authorization": "Bearer secret", "X-Agent": "codex"})

        self.assertEqual(status, 200)
        payload = json.loads(body["result"]["content"][0]["text"])
        self.assertEqual(payload["runningCount"], 1)
        self.assertEqual(payload["agents"][0]["agent"], "codex")

    def test_list_sessions_only_returns_calling_agent_sessions(self):
        self.store.upsert("codex", {"id": "s1", "title": "Codex", "status": "running"})
        self.store.upsert("claude", {"id": "s2", "title": "Claude", "status": "running"})

        status, _, body = self.request({
            "jsonrpc": "2.0",
            "id": 9,
            "method": "tools/call",
            "params": {
                "name": "list_sessions",
                "arguments": {},
            },
        }, {"Authorization": "Bearer secret", "X-Agent": "codex"})

        self.assertEqual(status, 200)
        payload = json.loads(body["result"]["content"][0]["text"])
        self.assertEqual(payload["runningCount"], 1)
        self.assertEqual([agent["agent"] for agent in payload["agents"]], ["codex"])

    def test_list_sessions_requires_authorization(self):
        self.store.upsert("codex", {"id": "s1", "title": "Codex", "status": "running"})

        status, _, body = self.request({
            "jsonrpc": "2.0",
            "id": 10,
            "method": "tools/call",
            "params": {
                "name": "list_sessions",
                "arguments": {},
            },
        }, {"X-Agent": "codex"})

        self.assertEqual(status, 200)
        self.assertEqual(body["error"]["code"], -32001)

    def test_report_session_response_only_returns_calling_agent_snapshot(self):
        self.store.upsert("claude", {"id": "s2", "title": "Claude", "status": "running"})

        status, _, body = self.request({
            "jsonrpc": "2.0",
            "id": 11,
            "method": "tools/call",
            "params": {
                "name": "report_session",
                "arguments": {"id": "s1", "title": "Codex", "status": "running"},
            },
        }, {"Authorization": "Bearer secret", "X-Agent": "codex"})

        self.assertEqual(status, 200)
        payload = json.loads(body["result"]["content"][0]["text"])
        self.assertEqual(payload["snapshot"]["runningCount"], 1)
        self.assertEqual([agent["agent"] for agent in payload["snapshot"]["agents"]], ["codex"])

    def test_get_mcp_returns_405_when_sse_not_supported(self):
        status, _, body = server.handle_request(self.store, "secret", "GET", "/mcp", {}, b"")

        self.assertEqual(status, 405)
        self.assertIn("SSE", body["error"])


if __name__ == "__main__":
    unittest.main()
