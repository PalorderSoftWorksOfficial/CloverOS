Kernel drivers directory

This folder contains simple driver stubs for the CloverOS kernel. Each driver is a Lua module that returns a table with the following recommended fields:

- `id`: string, unique driver identifier
- `init(kernel)`: function called when the kernel initializes the driver
- `shutdown(kernel)`: function called when the kernel is shutting down or unloading the driver

Drivers in this directory are intentionally minimal and are meant as starting points for real implementations. Typical kernel integration points (if provided by the kernel) include:

- `kernel.register_console(kernel)`
- `kernel.register_block_device(kernel)`
- `kernel.register_time_source(kernel)`
- `kernel.register_netif(kernel)`
- `kernel.register_gpio(kernel)`

Add more drivers or extend these stubs to implement device-specific logic.
