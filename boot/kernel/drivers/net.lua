-- Network driver stub for CloverOS kernel
local drv = {}
drv.id = "net"

function drv.init(kernel)
  kernel.info("net: initialized")
  if kernel.register_netif then
    pcall(kernel.register_netif, drv)
  end
  -- Provide a minimal send/recv hook
  function drv.send(iface, payload)
    kernel.info("net: send on " .. tostring(iface) .. ": " .. tostring(payload))
    return true
  end
end

function drv.shutdown(kernel)
  kernel.info("net: shutdown")
end

return drv
