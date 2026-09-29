-- Simple console driver stub for CloverOS kernel
local drv = {}
drv.id = "console"

function drv.init(kernel)
  kernel.info("console: initialized")
  if kernel.register_console then
    pcall(kernel.register_console, drv)
  end
  -- Provide a simple write implementation if kernel uses it
  function drv.write(...)
    local parts = { ... }
    for i = 1, #parts do parts[i] = tostring(parts[i]) end
    write(table.concat(parts, " "))
  end
end

function drv.shutdown(kernel)
  kernel.info("console: shutdown")
end

return drv
