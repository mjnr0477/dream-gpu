"""Small HTTP client for DREAM GPU's local runtime API.

This module is suitable for an application adapter (including a future DREAM AI
backend) but does not itself provide hardware or model inference.
"""
from __future__ import annotations

import json
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


class DreamGpuClientError(RuntimeError):
    pass


class DreamGpuClient:
    def __init__(self, base_url: str = "http://127.0.0.1:8765",
                 token: str | None = None, timeout: float = 10.0):
        if not isinstance(base_url, str) or not base_url.startswith(("http://", "https://")):
            raise ValueError("base_url must be an HTTP or HTTPS URL")
        if timeout <= 0:
            raise ValueError("timeout must be positive")
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.timeout = timeout

    def _request(self, method: str, path: str, payload=None):
        headers = {"Accept": "application/json"}
        body = None
        if payload is not None:
            body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            headers["Content-Type"] = "application/json"
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        request = Request(self.base_url + path, data=body, headers=headers, method=method)
        try:
            with urlopen(request, timeout=self.timeout) as response:
                raw = response.read()
        except HTTPError as exc:
            try:
                detail = exc.read().decode("utf-8", errors="replace")
            except Exception:
                detail = str(exc)
            raise DreamGpuClientError(f"DREAM GPU API returned HTTP {exc.code}: {detail}") from exc
        except (URLError, TimeoutError, OSError) as exc:
            raise DreamGpuClientError(f"Cannot reach DREAM GPU runtime: {exc}") from exc
        try:
            result = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise DreamGpuClientError("DREAM GPU runtime returned invalid JSON") from exc
        if not isinstance(result, dict):
            raise DreamGpuClientError("DREAM GPU runtime returned an unexpected response")
        return result

    def health(self) -> dict:
        return self._request("GET", "/health")

    def matmul_int8(self, matrix_a, matrix_b, max_polls: int = 10000) -> list[list[int]]:
        result = self._request("POST", "/v1/matmul/int8", {
            "a": matrix_a, "b": matrix_b, "max_polls": max_polls
        })
        if result.get("ok") is not True or result.get("shape") != [4, 4]:
            raise DreamGpuClientError("DREAM GPU returned an invalid INT8 matrix result")
        return result["matrix"]

    def execute(self, instructions, lane_memory=None, max_polls: int = 10000) -> dict:
        payload = {"instructions": instructions, "max_polls": max_polls}
        if lane_memory is not None:
            payload["lane_memory"] = lane_memory
        return self._request("POST", "/v1/execute", payload)
