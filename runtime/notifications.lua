-- CloverOS notifications: the queue and policy behind the panel bell.
--
-- A GNOME-style session needs three things from its notification system:
-- somewhere to put them, a do-not-disturb switch that silently files
-- instead of interrupting, and toasts that are transient while the list is
-- persistent. This module owns the queue and the policy; the panel draws
-- the bell and the dropdown, and the desktop draws the toasts, so nothing
-- here touches the terminal.
--
-- The queue is capped: a session that receives thousands of rednet messages
-- must not turn the notification list into a memory leak. Oldest entries
-- are dropped first, exactly like the inbox in runtime/system.lua.
local M = {}

M.MAX = 20
M.TTL = 60 * 5 -- seconds a notification stays in the list

function M.new(deps)
	deps = deps or {}
	local self = {
		kernel = deps.kernel,
		clock = deps.clock or os.clock,
		entries = {},
		dnd = false,
		unread = 0,
		nextId = 1,
		last = nil,
	}

	local function note(level, message)
		local kernel = self.kernel
		if kernel and type(kernel[level]) == "function" then
			pcall(kernel[level], "notify: " .. message)
		end
	end

	-- Raise a notification. Returns the stored entry, or nil with a reason
	-- when DND filed it silently (the caller still shows nothing).
	function self:notify(item)
		if type(item) ~= "table" then
			return nil, "not a notification"
		end
		local title = tostring(item.title or "")
		if title == "" then
			return nil, "no title"
		end
		local now = self.clock()
		local entry = {
			id = self.nextId,
			app = tostring(item.app or "system"),
			title = title:sub(1, 48),
			body = tostring(item.body or ""):sub(1, 120),
			at = now,
		}
		self.nextId = self.nextId + 1
		self.entries[#self.entries + 1] = entry
		while #self.entries > M.MAX do
			table.remove(self.entries, 1)
		end
		self.unread = self.unread + 1
		self:expire(now)
		self.last = entry
		-- one journal entry per notification, whatever happens with toasts
		note("info", entry.app .. ": " .. entry.title)
		if self.dnd then
			return nil, "do not disturb"
		end
		return entry
	end

	-- Convenience wrapper matching the desktop's notify(text) calls.
	function self:notifyText(app, text)
		return self:notify({ app = app, title = tostring(text or "") })
	end

	-- Drop entries older than the TTL. Called on notify, list and count so
	-- a long session does not show stale entries it can never dismiss.
	function self:expire(now)
		now = now or self.clock()
		local kept = {}
		for _, entry in ipairs(self.entries) do
			if (now - entry.at) < M.TTL then
				kept[#kept + 1] = entry
			end
		end
		self.entries = kept
		return #self.entries
	end

	function self:list()
		self:expire()
		return self.entries
	end

	function self:count()
		self:expire()
		return #self.entries
	end

	function self:unreadCount()
		self:expire()
		return self.unread
	end

	function self:markRead()
		local n = self.unread
		self.unread = 0
		return n
	end

	function self:clear()
		local n = #self.entries
		self.entries = {}
		self.unread = 0
		self.last = nil
		return n
	end

	function self:remove(id)
		for i, entry in ipairs(self.entries) do
			if entry.id == id then
				table.remove(self.entries, i)
				if self.unread > 0 then
					self.unread = self.unread - 1
				end
				return true
			end
		end
		return false
	end

	function self:setDnd(on)
		self.dnd = on == true
		note("info", "do not disturb " .. (self.dnd and "on" or "off"))
		return self.dnd
	end

	function self:toggleDnd()
		return self:setDnd(not self.dnd)
	end

	-- What the panel bell shows: "3" while unread, "0" when everything has
	-- been seen, DND indicator handled by the caller's drawing.
	function self:bellText()
		local n = self:unreadCount()
		if self.dnd then
			return "z" .. tostring(n)
		end
		return tostring(n)
	end

	return self
end

return M
