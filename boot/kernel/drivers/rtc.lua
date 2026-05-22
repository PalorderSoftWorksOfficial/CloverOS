-- Real-time clock driver stub for CloverOS kernel
local drv = {}
drv.id = "rtc"

function drv.init(kernel)
  kernel.info("rtc: initialized")
  if kernel.register_time_source then
    pcall(kernel.register_time_source, drv)
  end
  function drv.time()
    return os.time()
  end
  function drv.date(fmt, t)
    return os.date(fmt or "%c", t)
  end
end

function drv.shutdown(kernel)
  kernel.info("rtc: shutdown")
end

return drv
