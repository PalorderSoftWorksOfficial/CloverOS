-- GPIO driver stub for CloverOS kernel
local drv = {}
drv.id = "gpio"

function drv.init(kernel)
  kernel.info("gpio: initialized")
  if kernel.register_gpio then
    pcall(kernel.register_gpio, drv)
  end
  drv.pins = {}
  function drv.set(pin, value)
    drv.pins[pin] = value
    kernel.info("gpio: set pin " .. tostring(pin) .. " = " .. tostring(value))
    return true
  end
  function drv.get(pin)
    return drv.pins[pin]
  end
end

function drv.shutdown(kernel)
  kernel.info("gpio: shutdown")
end

return drv
