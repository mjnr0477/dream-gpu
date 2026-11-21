# DREAM GPU application client

`software/host/dream_gpu_client.py` is the application-facing HTTP client for
the local runtime service. It uses Python's standard library and can be used by
a future DREAM AI backend adapter without importing Verilog or serial details.

```python
from dream_gpu_client import DreamGpuClient

gpu = DreamGpuClient("http://127.0.0.1:8765", token=None)
health = gpu.health()
result = gpu.matmul_int8(
    [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12], [13, 14, 15, 16]],
    [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]],
)
```

For a remote service, configure a strong token and use HTTPS through a trusted
reverse proxy. Do not expose the built-in HTTP server directly to the public
internet. This client provides an application integration contract; it does
not mean the accelerator is physically connected or that model inference is
currently supported.
