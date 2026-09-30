-- CloverOS cron: scheduled shell lines, dispatched by running sessions.
--
-- A real cron daemon owns the event queue, which CloverOS sessions cannot
-- spare; instead cron persists the schedule and any session (text or
-- desktop) asks it "what is due?" on a timer tick. Jobs run as the user
-- who owns them through the session's own shell, so access rules apply.
--
-- The schedule file is etc/clover/crontab (text, one job per line):
--   min hour dom mon dow  command
-- Fields: "*" matches always, "*/n" steps, a number matches exactly.
-- The day-of-week is 1-7 with 1 = Sunday (Lua's os.date("%w") + 1; a
-- crontab-style 0 is accepted for Sunday). The @reboot, @hourly and @daily
-- shorthands are accepted, matching how people actually write jobs.
-- Lines starting with # are comments.
local M = {}

M.PATH = "etc/clover/crontab"

local SHORTHANDS = {
	reboot = { tag = "reboot" },
	hourly = { tag = "hourly" },
	daily = { tag = "daily" },
}

local function note(kernel, level, message)
	if kernel and type(kernel[level]) == "function" then
		pcall(kernel[level], "cron: " .. message)
	end
end

-- Match one schedule field against a time component.
function M.matchField(field, value)
	field = tostring(field or "*")
	if field == "*" then
		return true
	end
	local step = field:match("^%*/(%d+)$")
	if step then
		step = tonumber(step)
		if step and step > 0 then
			return value % step == 0
		end
		return false
	end
	return tonumber(field) == value
end

-- Match a schedule {min, hour, dom, mon, dow} against a time table.
function M.matches(schedule, t)
	return M.matchField(schedule.min, t.min)
		and M.matchField(schedule.hour, t.hour)
		and M.matchField(schedule.dom, t.dom)
		and M.matchField(schedule.mon, t.mon)
		and M.matchField(schedule.dow, t.dow)
end

function M.new(deps)
	deps = deps or {}
	local self = {
		kernel = deps.kernel,
		paths = deps.paths,
		jobs = {},
	}

	self.path = self.paths and self.paths:join(M.PATH) or M.PATH

	function self:load()
		self.jobs = {}
		if type(fs) ~= "table" or not fs.exists(self.path) then
			return false
		end
		local handle = fs.open(self.path, "r")
		if not handle then
			return false
		end
		local data = handle.readAll() or ""
		handle.close()
		for line in data:gmatch("[^\n]+") do
			self:addLine(line)
		end
		return true
	end

	function self:addLine(line)
		line = tostring(line or ""):gsub("^%s+", "")
		if line == "" or line:sub(1, 1) == "#" then
			return false
		end
		-- @reboot / @hourly / @daily shorthands
		local shorthand, rest = line:match("^@(%a+)%s+(.+)$")
		if shorthand then
			local job = SHORTHANDS[shorthand:lower()]
			if not job or rest == "" then
				return false
			end
			self.jobs[#self.jobs + 1] = { tag = job.tag, command = rest }
			return true
		end
		-- five fields plus the command
		local min, hour, dom, mon, dow, command
			= line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(.+)$")
		if not min then
			return false
		end
		if dow == "0" then
			dow = "7" -- crontab Sunday
		end
		self.jobs[#self.jobs + 1] = {
			fields = { min = min, hour = hour, dom = dom, mon = mon, dow = dow },
			command = command,
		}
		return true
	end

	-- The current time in schedule fields.
	function self:now()
		local t = {}
		local ok = pcall(function()
			t = {
				min = tonumber(os.date("%M")),
				hour = tonumber(os.date("%H")),
				dom = tonumber(os.date("%d")),
				mon = tonumber(os.date("%m")),
				dow = tonumber(os.date("%w")) + 1, -- Lua: Sunday = 1
			}
		end)
		if not ok then
			return nil
		end
		return t
	end

	-- What is due right now? Reboot-tagged jobs are included only when
	-- `reboot` is true (the caller runs them once per session).
	function self:due(reboot)
		local t = self:now()
		local out = {}
		if not t then
			return out
		end
		for _, job in ipairs(self.jobs) do
			if job.tag == "reboot" then
				if reboot then
					out[#out + 1] = job
				end
			elseif job.tag == "hourly" then
				if t.min == 0 then
					out[#out + 1] = job
				end
			elseif job.tag == "daily" then
				if t.min == 0 and t.hour == 0 then
					out[#out + 1] = job
				end
			elseif job.fields and M.matches(job.fields, t) then
				out[#out + 1] = job
			end
		end
		return out
	end

	-- Hand due jobs to the caller's runner (typically the shell's execute).
	-- Returns how many ran; failures are logged, never raised.
	function self:dispatch(runJob, reboot)
		local ran = 0
		for _, job in ipairs(self:due(reboot)) do
			note(self.kernel, "info", "running: " .. tostring(job.command))
			local ok = pcall(runJob, job.command)
			if ok then
				ran = ran + 1
			else
				note(self.kernel, "warn", "job failed: " .. tostring(job.command))
			end
		end
		return ran
	end

	return self
end

-- Session entry point: builds a cron from the root's crontab.
function M.attach(kernel, paths)
	local cron = M.new({ kernel = kernel, paths = paths })
	cron:load()
	return cron
end

return M
