-- Linux-style boot messages (kernel journal + init)
local M = {}

function M.run(ctx)
  local kernel, term, colors = ctx.kernel, ctx.term, ctx.colors
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.lightGray)
  kernel.ui.clear()

  kernel.ui.centerText(1, "CloverOS GNU/Linux 2.0")
  kernel.ui.centerText(2, "Loading kernel " .. kernel.version() .. " ...")

  if not kernel.status().booted then
    kernel.boot()
  end

  local y = 4
  for _, line in ipairs(kernel.journal()) do
    if y < select(2, term.getSize()) - 2 then
      term.setCursorPos(1, y)
      term.clearLine()
      local short = #line > 50 and (line:sub(1, 47) .. "...") or line
      term.write(short)
      y = y + 1
    end
  end

  kernel.ui.centerText(select(2, term.getSize()) - 1, "[ OK ] Started multi-user shell.")
  kernel.sleep(0.5)
end

return M
