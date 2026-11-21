# DREAM GPU v1.4 UART transport

The UART bridge implements an 8-N-1 packet protocol over a serial link. The
Python adapter is `DreamGpuUartTransport` in `dream_gpu_uart.py`; it plugs
directly into `DreamGpuDevice` from the v1.3 host driver.

## Wire protocol

All multi-byte data values are little-endian.

| Request | Bytes |
|---|---|
| Read register | `D5 A5 01 ADDRESS` |
| Write register | `D5 A5 02 ADDRESS DATA0 DATA1 DATA2 DATA3` |

Response to either request begins with one status byte (`00` means success).
A read response then appends four data bytes. The current bridge returns status
zero for every decoded register transaction; the v1.2 register block currently
does not expose bus errors.

Default RTL clock divider is 434 system clocks per bit (approximately 115200
baud at 50 MHz). Set `CLKS_PER_BIT` to the actual board clock divided by the
desired baud rate. This parameter must match the physical clock and UART
settings.

## Python example

```python
from dream_gpu_driver import DreamGpuDevice
from dream_gpu_uart import DreamGpuUartTransport

with DreamGpuUartTransport.open("/dev/ttyUSB0", baudrate=115200) as link:
    gpu = DreamGpuDevice(link)
    print(hex(gpu.read_private_word(0, 0)))
```

Install `pyserial` on the host that owns the physical serial port. The RTL
module has not yet been validated on an FPGA board; simulation and physical
electrical/baud/timing validation are separate acceptance steps.
