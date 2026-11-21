"""Local HTTP runtime bridge for DREAM GPU hardware.

The service is intentionally loopback-only by default. It exposes a small,
versioned JSON API over the tested DreamGpuDevice transport abstraction.
"""
from __future__ import annotations

import argparse
import hmac
import ipaddress
import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

from dream_gpu_driver import DreamGpuDevice
from dream_gpu_uart import DreamGpuUartTransport

MAX_BODY_BYTES = 65536
MAX_POLLS = 1_000_000


def _json_bytes(value: Any) -> bytes:
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def _validate_execution(payload: Any) -> tuple[list[int], list[list[int]], int]:
    if not isinstance(payload, dict):
        raise ValueError("request body must be a JSON object")
    instructions = payload.get("instructions")
    if not isinstance(instructions, list) or not instructions:
        raise ValueError("instructions must be a non-empty array")
    if len(instructions) > 256:
        raise ValueError("instructions cannot exceed 256 words")
    for word in instructions:
        if isinstance(word, bool) or not isinstance(word, int) or not 0 <= word <= 0xFFFFFFFF:
            raise ValueError("each instruction must be an unsigned 32-bit integer")

    lane_memory = payload.get("lane_memory", [[], [], [], []])
    if not isinstance(lane_memory, list) or len(lane_memory) != 4:
        raise ValueError("lane_memory must contain exactly four lane arrays")
    checked_memory: list[list[int]] = []
    for lane in lane_memory:
        if not isinstance(lane, list) or len(lane) > 64:
            raise ValueError("each lane memory array must contain at most 64 words")
        checked_lane = []
        for word in lane:
            if isinstance(word, bool) or not isinstance(word, int) or not 0 <= word <= 0xFFFFFFFF:
                raise ValueError("lane memory values must be unsigned 32-bit integers")
            checked_lane.append(word)
        checked_memory.append(checked_lane)

    max_polls = payload.get("max_polls", 10000)
    if isinstance(max_polls, bool) or not isinstance(max_polls, int) or not 1 <= max_polls <= MAX_POLLS:
        raise ValueError(f"max_polls must be an integer from 1 to {MAX_POLLS}")
    return instructions, checked_memory, max_polls


def _validate_matrix_request(payload: Any):
    if not isinstance(payload, dict):
        raise ValueError("request body must be a JSON object")
    matrices = []
    for key in ("a", "b"):
        matrix = payload.get(key)
        if not isinstance(matrix, list) or len(matrix) != 4:
            raise ValueError(f"{key} must be a 4x4 matrix")
        checked = []
        for row in matrix:
            if not isinstance(row, list) or len(row) != 4:
                raise ValueError(f"{key} must be a 4x4 matrix")
            if any(isinstance(v, bool) or not isinstance(v, int) or not -128 <= v <= 127 for v in row):
                raise ValueError("INT8 matrix elements must be integers in range -128..127")
            checked.append(row)
        matrices.append(checked)
    max_polls = payload.get("max_polls", 10000)
    if isinstance(max_polls, bool) or not isinstance(max_polls, int) or not 1 <= max_polls <= MAX_POLLS:
        raise ValueError(f"max_polls must be an integer from 1 to {MAX_POLLS}")
    return matrices[0], matrices[1], max_polls


def make_handler(device: DreamGpuDevice, api_token: str | None = None):
    device_lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        server_version = "DREAM-GPU-Runtime/1.5"

        def log_message(self, fmt, *args):
            # Avoid logging authorization headers or request bodies.
            super().log_message(fmt, *args)

        def _send(self, status: int, payload: dict[str, Any]) -> None:
            body = _json_bytes(payload)
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def _authorized(self) -> bool:
            if api_token is None:
                return True
            supplied = self.headers.get("Authorization", "")
            prefix = "Bearer "
            if not supplied.startswith(prefix):
                return False
            return hmac.compare_digest(supplied[len(prefix):], api_token)

        def _read_json(self):
            raw_length = self.headers.get("Content-Length")
            try:
                length = int(raw_length or "")
            except ValueError:
                raise ValueError("Content-Length is required")
            if length < 1 or length > MAX_BODY_BYTES:
                raise ValueError(f"request body must be between 1 and {MAX_BODY_BYTES} bytes")
            raw = self.rfile.read(length)
            try:
                return json.loads(raw.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise ValueError("request body must be valid UTF-8 JSON") from exc

        def do_GET(self):
            if not self._authorized():
                self._send(401, {"error": "unauthorized"})
                return
            if self.path != "/health":
                self._send(404, {"error": "not_found"})
                return
            try:
                with device_lock:
                    status = device.status()
                    cycles = device.read_register(device.CYCLES)
                    instructions = device.read_register(device.INSTRUCTIONS)
                self._send(200, {
                    "service": "dream-gpu-runtime",
                    "api_version": "1.6",
                    "device_responding": True,
                    "execution_done": status.done,
                    "fault": status.fault,
                    "halted_mask": status.halted_mask,
                    "cycles": cycles,
                    "instructions": instructions,
                    "hardware": "FPGA/RTL-compatible accelerator over UART",
                    "capabilities": {
                        "lanes": 4,
                        "instruction_words": 256,
                        "private_words_per_lane": 64,
                        "integer_accumulators": 4,
                        "floating_point": False,
                        "tensor_acceleration": True,\n                        "tensor_unit": "4x4 signed INT8 matrix multiply",
                        "physical_fpga_verified": False
                    }
                })
            except Exception as exc:
                self._send(503, {"service": "dream-gpu-runtime", "device_responding": False,
                                 "error": str(exc)})

        def do_POST(self):
            if not self._authorized():
                self._send(401, {"error": "unauthorized"})
                return
            if self.path == "/v1/matmul/int8":
                try:
                    matrix_a, matrix_b, max_polls = _validate_matrix_request(self._read_json())
                except ValueError as exc:
                    self._send(400, {"error": "invalid_request", "detail": str(exc)})
                    return
                try:
                    with device_lock:
                        result = device.run_int8_matmul(matrix_a, matrix_b, max_polls=max_polls)
                    self._send(200, {"ok": True, "dtype": "int32", "shape": [4, 4],
                                     "matrix": [list(row) for row in result]})
                except TimeoutError as exc:
                    self._send(504, {"error": "tensor_timeout", "detail": str(exc)})
                except Exception as exc:
                    self._send(503, {"error": "device_unavailable", "detail": str(exc)})
                return
            if self.path != "/v1/execute":
                self._send(404, {"error": "not_found"})
                return
            try:
                instructions, lane_memory, max_polls = _validate_execution(self._read_json())
            except ValueError as exc:
                self._send(400, {"error": "invalid_request", "detail": str(exc)})
                return

            try:
                with device_lock:
                    device.reset()
                    device.load_program(instructions)
                    for lane_id, words in enumerate(lane_memory):
                        for offset, word in enumerate(words):
                            device.write_private_word(lane_id, offset, word)
                    device.start()
                    device.wait_done(max_polls=max_polls)
                    result = device.results()
                self._send(200, {
                    "ok": True,
                    "accumulators": list(result.accumulators),
                    "program_counters": list(result.program_counters),
                    "halted_mask": result.status.halted_mask,
                    "cycles": result.cycles,
                    "instructions": result.instructions,
                    "branches": result.branches,
                    "fault_code": result.fault_code
                })
            except TimeoutError as exc:
                try:
                    with device_lock:
                        device.stop()
                except Exception:
                    pass
                self._send(504, {"error": "execution_timeout", "detail": str(exc)})
            except RuntimeError as exc:
                self._send(409, {"error": "device_fault", "detail": str(exc)})
            except Exception as exc:
                self._send(503, {"error": "device_unavailable", "detail": str(exc)})

    return Handler


def main() -> None:
    parser = argparse.ArgumentParser(description="DREAM GPU v1.5 local runtime API")
    parser.add_argument("--serial-port", required=True, help="FPGA UART device, e.g. /dev/ttyUSB0")
    parser.add_argument("--baudrate", type=int, default=115200)
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--token", default=os.environ.get("DREAM_GPU_API_TOKEN"))
    args = parser.parse_args()

    try:
        address = ipaddress.ip_address(args.bind)
    except ValueError as exc:
        raise SystemExit("--bind must be a literal IPv4 or IPv6 address") from exc
    if not address.is_loopback and not args.token:
        raise SystemExit("Non-loopback binding requires --token or DREAM_GPU_API_TOKEN")
    if args.token is not None and len(args.token) < 24:
        raise SystemExit("API token must be at least 24 characters")

    transport = DreamGpuUartTransport.open(args.serial_port, args.baudrate)
    device = DreamGpuDevice(transport)
    server = ThreadingHTTPServer((args.bind, args.port), make_handler(device, args.token))
    print(f"DREAM GPU runtime listening on http://{args.bind}:{args.port}")
    print("This API exposes integer processor execution; it is not an LLM inference server.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        transport.close()


if __name__ == "__main__":
    main()
