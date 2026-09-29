-- Simple block/disk driver stub for CloverOS kernel
local drv = {}
drv.id = "disk"

function drv.init(kernel)
  kernel.info("disk: initialized")
  if kernel.register_block_device then
    pcall(kernel.register_block_device, drv)
  end
  -- simple probe: expose a read-only list of "disks"
  function drv.list()
    -- map available /diskN
    local out = {}
    for i = 0, 99 do
      local p = "/disk" .. (i == 0 and "" or i)
      if fs.exists(p) then table.insert(out, p) end
    end
    return out
  end
end

function drv.shutdown(kernel)
  kernel.info("disk: shutdown")
end

return drv
