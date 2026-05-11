local luastate = { states = {} }

local State = {}
State.__index = State

function State:push(v)
	self.stack.n = self.stack.n + 1
	self.stack[self.stack.n] = luastate.stack_value(v)
end

function State:rawpush(v)
	self.stack.n = self.stack.n + 1
	self.stack[self.stack.n] = v
end

function State:pop()
	local v = self.stack[self.stack.n]
	self.stack.n = self.stack.n - 1
	return luastate.lua_value(v, self.cpu)
end

function State:rawpop()
	local v = self.stack[self.stack.n]
	self.stack.n = self.stack.n - 1
	return v
end

function State:settop(i)
	if i < 0 then
		self.stack.n = self.stack.n + i + 1
	elseif i > 0 then
		self.stack.n = i
	end
end

function State:insert(val, i)
	if i < 0 then
		i = self.stack.n + i + 1
	end
	for j = self.stack.n, i, -1 do
		self.stack[j + 1] = self.stack[j]
	end
	self.stack[i] = luastate.stack_value(val)
	self.stack.n = self.stack.n + 1
end

function State:remove(i)
	if i < 0 then
		i = self.stack.n + i + 1
	end
	for j = i, self.stack.n do
		self.stack[j] = self.stack[j + 1]
	end
	self.stack.n = self.stack.n - 1
end

function luastate.call_state(cpu, cf, ...)
	local state = setmetatable({
		cpu = cpu,
		cf = cf,
		coro = coroutine.running(),
		stack = table.pack(...),
	}, State)
	for i = 1, state.stack.n do
		state.stack[i] = luastate.stack_value(state.stack[i])
	end
	local id = #luastate.states + 1
	luastate.states[id] = state
	return id
end

function luastate.new_state(cpu)
	local state = setmetatable({
		cpu = cpu,
		stack = { n = 0 },
	}, State)
	local id = #luastate.states + 1
	luastate.states[id] = state
	return id
end

function luastate.table(tbl)
	return { type = "table", value = tbl }
end

function luastate.state(_state)
	return { type = "thread", value = _state }
end

function luastate.cclosure(_ptr, ...)
	return { type = "cclosure", value = _ptr, upvalues = { ... } }
end

function luastate.userdata(_ptr, mt, uv)
	return { type = "userdata", value = _ptr, object = setmetatable({}, mt), uservalue = uv }
end

function luastate.lightuserdata(_ptr)
	return { type = "lightuserdata", value = _ptr }
end

function luastate.stack_value(v)
	local tp = type(v)
	if tp == "table" then
		return luastate.table(v)
	elseif tp == "thread" then
		for i, state in ipairs(luastate.states) do
			if state.coro == v then
				return luastate.state(i)
			end
		end
		local state = setmetatable({
			coro = v,
			stack = { n = 0 },
		}, State)
		local id = #luastate.states + 1
		luastate.states[id] = state
		return luastate.state(id)
	else
		return v
	end
end

function luastate.lua_value(v, cpu)
	if type(v) == "table" then
		if v.type == "table" then
			return v.value
		elseif v.type == "thread" then
			return luastate.states[v.value].coro
		elseif v.type == "cclosure" then
			return function(...)
				local state = luastate.call_state(cpu, v, ...)
				local nres = cpu:call(v.value, state)
				local st = luastate.states[state].stack
				for i = st.n - nres + 1, st.n do
					st[i] = luastate.lua_value(st[i], cpu)
				end
				luastate.states[state] = nil
				return table.unpack(st, st.n - nres + 1, st.n)
			end
		elseif v.type == "userdata" then
			return v.object
		elseif v.type == "lightuserdata" then
			return v -- TODO
		end
	else
		return v
	end
end

return luastate
