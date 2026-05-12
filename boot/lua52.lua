local luastate = require "luastate"

local lua52 = {}

local NULL, void = 0, 0

local function fromdouble(nl, nh)
    return ("<d"):unpack(("<II"):pack(nl, nh))
end

local function savedouble(self, addr, n)
    local data = ("<d"):pack(n)
    self.mem32[addr / 4], self.mem32[addr / 4 + 1] = ("<II"):unpack(data)
end

local function returndouble(self, n)
    local data = ("<d"):pack(n)
    local v
    v, self.reg[11] = ("<II"):unpack(data)
    return v
end

local function signed(n) if n >= 0x80000000 then return n - 0x100000000 end return n end

local function value(L, idx)
    idx = signed(idx)
    if idx == -1001000 then return debug.getregistry()
    elseif idx < -1001000 then return luastate.lua_value(L.cf and L.cf.upvalues[-idx - 1001000], L.cpu)
    elseif idx < 0 then idx = L.stack.n + idx + 1 end
    return luastate.lua_value(L.stack[idx], L.cpu)
end

local function rawvalue(L, idx)
    idx = signed(idx)
    if idx == -1001000 then return luastate.table(debug.getregistry())
    elseif idx < -1001000 then return L.cf and L.cf.upvalues[-idx - 1001000]
    elseif idx < 0 then idx = L.stack.n + idx + 1 end
    return L.stack[idx]
end

function lua52:lua_newstate(_allocf, _ud)
    -- not possible to create whole new states
    return NULL
end

function lua52:lua_close(_L)
    -- not possible to close states
    return void
end

function lua52:lua_newthread(_L)
    local L = luastate.states[_L]
    local _L1 = luastate.new_state(L.cpu)
    L:push(luastate.state(_L1))
    return _L1
end

function lua52:lua_atpanic(_L, _panicf)
    -- TODO
    return NULL
end

function lua52:lua_version(_L)
    -- this should be implemented in C
    return NULL
end

function lua52:lua_absindex(_L, idx)
    if signed(idx) <= -1001000 then return idx end
    idx = signed(idx)
    local L = luastate.states[_L]
    if idx < 0 then idx = L.stack.n + idx + 1 end
    return idx
end

function lua52:lua_gettop(_L)
    return luastate.states[_L].stack.n
end

function lua52:lua_settop(_L, idx)
    luastate.states[_L]:settop(signed(idx))
    return void
end

function lua52:lua_pushvalue(_L, idx)
    local L = luastate.states[_L]
    L:rawpush(rawvalue(L, idx))
    return void
end

function lua52:lua_remove(_L, idx)
    idx = signed(idx)
    local L = luastate.states[_L]
    if idx < 0 then idx = L.stack.n + idx + 1 end
    L:remove(idx)
    return void
end

function lua52:lua_insert(_L, idx)
    idx = signed(idx)
    local L = luastate.states[_L]
    if idx < 0 then idx = L.stack.n + idx + 1 end
    L:insert(L:pop(), idx)
    return void
end

function lua52:lua_replace(_L, idx)
    idx = signed(idx)
    local L = luastate.states[_L]
    if idx < -1001000 then L.cf.upvalues[-idx - 1001000] = L:pop() return void end
    if idx < 0 then idx = L.stack.n + idx + 1 end
    L.stack[idx] = L:pop()
    return void
end

function lua52:lua_copy(_L, fromidx, toidx)
    toidx = signed(toidx)
    local L = luastate.states[_L]
    if toidx < 0 then toidx = L.stack.n + toidx + 1 end
    L.stack[toidx] = rawvalue(L, fromidx)
    return void
end

function lua52:lua_checkstack(_L, n)
    -- always ok
    return 1
end

function lua52:lua_xmove(_from, _to, n)
    local from = luastate.states[_from]
    local to = luastate.states[_to]
    for i = 1, n do to.stack[to.stack.n+i] = from.stack[from.stack.n-n+i] end
    from.stack.n = from.stack.n - n
    to.stack.n = to.stack.n + n
    return void
end

function lua52:lua_isnumber(_L, idx)
    local L = luastate.states[_L]
    local v = rawvalue(L, idx)
    return type(v) == "number" and 1 or 0
end

function lua52:lua_isstring(_L, idx)
    local L = luastate.states[_L]
    local v = rawvalue(L, idx)
    return type(v) == "string" and 1 or 0
end

function lua52:lua_iscfunction(_L, idx)
    local L = luastate.states[_L]
    local v = rawvalue(L, idx)
    return (type(v) == "table" and v.type == "cclosure") and 1 or 0
end

function lua52:lua_isuserdata(_L, idx)
    local L = luastate.states[_L]
    local v = rawvalue(L, idx)
    return (type(v) == "table" and (v.type == "userdata" or v.type == "lightuserdata")) and 1 or 0
end

local lua_types = {
    ["nil"] = 0,
    boolean = 1,
    lightuserdata = 2,
    number = 3,
    string = 4,
    table = 5,
    ["function"] = 6,
    cclosure = 6,
    userdata = 7,
    thread = 8
}

function lua52:lua_type(_L, idx)
    idx = signed(idx)
    local L = luastate.states[_L]
    if idx == 0 or idx > L.stack.n or (idx < -L.stack.n and idx > -1001000) or (idx < -1001000 and L.cf.upvalues[-idx - 1001000] == nil) then return -1 end
    local v = rawvalue(L, idx)
    if type(v) == "table" then return lua_types[v.type]
    else return lua_types[type(v)] end
end

function lua52:lua_typename(_L, tp)
    -- implemented in C
    return NULL
end

function lua52:lua_tonumberx(_L, idx, _isnum)
    local L = luastate.states[_L]
    local n = tonumber(value(L, idx))
    if n then
        if _isnum ~= 0 then self.mem32[_isnum / 4] = 1 end
        return returndouble(self, n)
    else
        if _isnum ~= 0 then self.mem32[_isnum / 4] = 0 end
        return returndouble(self, 0)
    end
end

function lua52:lua_tointegerx(_L, idx, _isnum)
    local L = luastate.states[_L]
    local n = tonumber(value(L, idx))
    if n then
        if _isnum ~= 0 then self.mem32[_isnum / 4] = 1 end
        return bit32.band(n, 0xFFFFFFFF)
    else
        if _isnum ~= 0 then self.mem32[_isnum / 4] = 0 end
        return 0
    end
end

function lua52:lua_tounsignedx(_L, idx, _isnum)
    local L = luastate.states[_L]
    local n = tonumber(value(L, idx))
    if n then
        if _isnum ~= 0 then self.mem32[_isnum / 4] = 1 end
        return bit32.band(n, 0xFFFFFFFF)
    else
        if _isnum ~= 0 then self.mem32[_isnum / 4] = 0 end
        return 0
    end
end

function lua52:lua_toboolean(_L, idx)
    return value(luastate.states[_L], idx) and 1 or 0
end

function lua52:strptr(_L, idx, _len)
    local L = luastate.states[_L]
    local v = value(L, idx)
    -- TODO: numbers to string
    if type(v) ~= "string" then return NULL end
    if not L.cpu.sysdata.lua_tolstring then L.cpu.sysdata.lua_tolstring = {} end
    L.cpu.mem32[_len / 4] = #v
    return L.cpu.sysdata.lua_tolstring[v] or NULL
end

function lua52:lua_tolstring(_L, idx, _ptr)
    local L = luastate.states[_L]
    local v = value(L, idx)
    -- TODO: numbers to string
    if type(v) ~= "string" then return void end
    self.fficopy(self.mem + _ptr, v)
    return void
end

function lua52:lua_rawlen(_L, idx)
    local L = luastate.states[_L]
    local ok, res = pcall(rawlen, value(L, idx))
    if not ok then return 0 end
    return res
end

function lua52:lua_tocfunction(_L, idx)
    local L = luastate.states[_L]
    local v = rawvalue(L, idx)
    if type(v) ~= "table" or v.type ~= "cclosure" then return NULL end
    return v.value
end

function lua52:lua_touserdata(_L, idx)
    local L = luastate.states[_L]
    local v = rawvalue(L, idx)
    if type(v) ~= "table" or (v.type ~= "userdata" and v.type ~= "lightuserdata") then return NULL end
    return v.value
end

function lua52:lua_tothread(_L, idx)
    local L = luastate.states[_L]
    local v = rawvalue(L, idx)
    if type(v) ~= "table" or v.type ~= "thread" then return NULL end
    return v.value
end

function lua52:lua_topointer(_L, idx)
    local L = luastate.states[_L]
    local v = rawvalue(L, idx)
    if type(v) ~= "table" then return NULL end
    return tonumber(tostring(v):match(": (%x+)"), 16)
end

function lua52:lua_arith(_L, op)
    local L = luastate.states[_L]
    local b = L:pop()
    local a = L:pop()
    if type(a) == "table" and a.type == "table" then a = a.value end
    -- TODO
    return void
end

function lua52:lua_rawequal(_L, idx1, idx2)
    local L = luastate.states[_L]
    return rawequal(value(L, idx1), value(L, idx2))
end

function lua52:lua_compare(_L, idx1, idx2, op)
    local L = luastate.states[_L]
    
end

function lua52:lua_pushnil(_L)
    luastate.states[_L]:push(nil)
    return void
end

function lua52:lua_pushnumber(_L, _, nl, nh)
    luastate.states[_L]:push(fromdouble(nl, nh))
    return void
end

function lua52:lua_pushinteger(_L, n)
    if bit32.btest(n, 0x80000000) then n = n - 0x100000000 end
    luastate.states[_L]:push(n)
    return void
end

function lua52:lua_pushunsigned(_L, n)
    luastate.states[_L]:push(n)
    return void
end

function lua52:lua_pushlstring(_L, _s, len)
    luastate.states[_L]:push(self.ffistring(self.mem + _s, len))
    return _s
end

function lua52:lua_pushstring(_L, _s)
    luastate.states[_L]:push(self.ffistring(self.mem + _s))
    return _s
end



function lua52:lua_pushcclosure(_L, _fn, n)
    local L = luastate.states[_L]
    local t = {table.unpack(L.stack, L.stack.n - n + 1, L.stack.n)}
    for i = 1, n do t[i] = luastate.lua_value(t[i], L.cpu) end
    L:rawpush(luastate.cclosure(_fn, table.unpack(t, 1, n)))
    return void
end

function lua52:lua_pushboolean(_L, b)
    luastate.states[_L]:push(b ~= 0)
    return void
end

function lua52:lua_pushlightuserdata(_L, _p)
    luastate.states[_L]:rawpush(luastate.lightuserdata(_p))
    return void
end

function lua52:lua_pushthread(_L)
    local L = luastate.states[_L]
    L:rawpush(L)
    return 0 -- TODO
end

function lua52:lua_getglobal(_L, _var)
    local L = luastate.states[_L]
    L:push(_G[self.ffistring(self.mem + _var)])
    return void
end

function lua52:lua_gettable(_L, idx)
    local L = luastate.states[_L]
    local t = value(L, idx)
    L:push(t[L:pop()])
    return void
end

function lua52:lua_getfield(_L, idx, _k)
    local k = self.ffistring(self.mem + _k)
    local L = luastate.states[_L]
    local t = value(L, idx)
    L:push(t[k])
    return void
end

function lua52:lua_rawget(_L, idx)
    local L = luastate.states[_L]
    local t = value(L, idx)
    L:push(rawget(t, L:pop()))
    return void
end

function lua52:lua_rawgeti(_L, idx, n)
    local L = luastate.states[_L]
    local t = value(L, idx)
    if type(t) ~= "table" then
        for i = 1, #L.stack do print(i, L.stack[i]) end
        error("Not a table at " .. idx .. ":", t)
    end
    L:push(rawget(t, n))
    return void
end

function lua52:lua_rawgetp(_L, idx, _p)
    -- TODO
    local L = luastate.states[_L]
    local t = value(L, idx)
    L:push(rawget(t, self.mem + _p))
    return void
end

function lua52:lua_createtable(_L, narr, nrec)
    local L = luastate.states[_L]
    L:push({})
    return void
end

function lua52:lua_newuserdata(_L, _ptr)
    local L = luastate.states[_L]
    L:rawpush(luastate.userdata(_ptr, nil, nil))
    return void
end

function lua52:lua_getmetatable(_L, idx)
    local L = luastate.states[_L]
    local t = value(L, idx)
    local mt = debug.getmetatable(t)
    if mt ~= nil then
        L:push(mt)
        return 1
    end
    return 0
end

-- TODO
function lua52:lua_getuservalue(_L, idx)
    local L = luastate.states[_L]
    local t = rawvalue(L, idx)
    if type(t) == "table" then
        if t.type == "userdata" then L:push(t.uservalue)
        else L:push(nil) end
    else L:push(nil) end
    return void
end

function lua52:lua_setglobal(_L, _var)
    local L = luastate.states[_L]
    local v = L:pop()
    _G[self.ffistring(self.mem + _var)] = v
    return void
end

function lua52:lua_settable(_L, idx)
    local L = luastate.states[_L]
    local t = value(L, idx)
    local v = L:pop()
    local k = L:pop()
    t[k] = v
    return void
end

function lua52:lua_setfield(_L, idx, _k)
    local k = self.ffistring(self.mem + _k)
    local L = luastate.states[_L]
    local t = value(L, idx)
    t[k] = L:pop()
    return void
end

function lua52:lua_rawset(_L, idx)
    local L = luastate.states[_L]
    local t = value(L, idx)
    local v = L:pop()
    local k = L:pop()
    rawset(t, k, v)
    return void
end

function lua52:lua_rawseti(_L, idx, n)
    local L = luastate.states[_L]
    local t = value(L, idx)
    rawset(t, n, L:pop())
    return void
end

function lua52:lua_rawsetp(_L, idx, _p)
    -- TODO
    local L = luastate.states[_L]
    local t = value(L, idx)
    rawset(t, self.mem + _p, L:pop())
    return void
end

function lua52:lua_setmetatable(_L, idx)
    local L = luastate.states[_L]
    local t = value(L, idx)
    debug.setmetatable(t, L:pop())
    return 1
end

-- TODO
function lua52:lua_setuservalue(_L, idx)
    local L = luastate.states[_L]
    local t = rawvalue(L, idx)
    if type(t) == "table" then
        if t.type == "userdata" then t.uservalue = L:pop()
        else L:pop() end
    else L:pop() end
    return void
end



function lua52:lua_error(_L)
    error(luastate.states[_L]:pop(), 0)
end

function lua52:lua_next(_L, idx)
    local L = luastate.states[_L]
    local t = value(L, idx)
    local k = L:pop()
    local nk, nv = next(t, k)
    if nk ~= nil then
        L:push(nk)
        L:push(nv)
        return 1
    else return 0 end
end

function lua52:lua_concat(_L, n)
    local L = luastate.states[_L]
    local t = {}
    for i = n, 1, -1 do t[i] = L:pop() end
    L:push(table.concat(t))
    return void
end

function lua52:lua_len(_L, idx)
    local L = luastate.states[_L]
    local t = value(L, idx)
    L:push(#t)
    return void
end



function lua52:lua_getstack(_L, level, _ar)
    return 0
end

local lua52_list = {
    [0] = "lua_newstate",
    "lua_close",
    "lua_newthread",

    "lua_atpanic",

    "lua_version",

    "lua_absindex",
    "lua_gettop",
    "lua_settop",
    "lua_pushvalue",
    "lua_remove",
    "lua_insert",
    "lua_replace",
    "lua_copy",
    "lua_checkstack",

    "lua_xmove",

    "lua_isnumber",
    "lua_isstring",
    "lua_iscfunction",
    "lua_isuserdata",
    "lua_type",
    "lua_typename",

    "lua_tonumberx",
    "lua_tointegerx",
    "lua_tounsignedx",
    "lua_toboolean",
    "lua_tolstring",
    "lua_rawlen",
    "lua_tocfunction",
    "lua_touserdata",
    "lua_tothread",
    "lua_topointer",

    "lua_arith",

    "lua_rawequal",
    "lua_compare",

    "lua_pushnil",
    "lua_pushnumber",
    "lua_pushinteger",
    "lua_pushunsigned",
    "lua_pushlstring",
    "lua_pushstring",
    "lua_pushvfstring",
    "lua_pushfstring",
    "lua_pushcclosure",
    "lua_pushboolean",
    "lua_pushlightuserdata",
    "lua_pushthread",

    "lua_getglobal",
    "lua_gettable",
    "lua_getfield",
    "lua_rawget",
    "lua_rawgeti",
    "lua_rawgetp",
    "lua_createtable",
    "lua_newuserdata",
    "lua_getmetatable",
    "lua_getuservalue",

    "lua_setglobal",
    "lua_settable",
    "lua_setfield",
    "lua_rawset",
    "lua_rawseti",
    "lua_rawsetp",
    "lua_setmetatable",
    "lua_setuservalue",

    "lua_callk",
    "lua_getctx",
    "lua_pcallk",
    "lua_load",
    "lua_dump",

    "lua_yieldk",
    "lua_resume",
    "lua_status",

    "lua_gc",

    "lua_error",
    "lua_next",
    "lua_concat",
    "lua_len",
    "lua_getallocf",
    "lua_setallocf",

    "lua_getstack",
    "lua_getinfo",
    "lua_getlocal",
    "lua_setlocal",
    "lua_getupvalue",
    "lua_setupvalue",
    "lua_upvalueid",
    "lua_upvaluejoin",

    "lua_sethook",
    "lua_gethook",
    "lua_gethookmask",
    "lua_gethookcount",

    "strptr"
}
for k, v in pairs(lua52_list) do lua52[k] = lua52[v] end

return lua52