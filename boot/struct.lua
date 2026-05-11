-- MIT License
--
-- Copyright (c) 2023 JackMacWindows
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

-- ===== Notes =====
-- * Includes the following types:
--   - All standard C89 integral & float types
--   - C++ bool
--   - C stdint.h fixed-width integer types
--   - size_t
--   - Lua number types (lua_Integer, lua_Unsigned, lua_Number)
--   - Special string types: string_t = variable width string preceeded by size_t for length,
--     string[8|16|32|64]_t = string with fixed-width integer size
--   - [const] char * = NUL-terminated C string
--   - [const] char[] = fixed width string
-- * Pointers are not supported outside C strings
-- * Variable-length arrays are not supported - decode these manually using [0] length arrays & loops
-- * The decoder accepts an index to start decoding at as the second argument
-- * The decoder only parses the fields for the struct, and returns the index of
--   the next data (like string.unpack)
-- * To encode a union, pass a table with *exactly one* member
-- * All fields encoded must have a value, including filling all array entries
-- * Do not include default values in structure definitions
-- * The length operator on a type returns the size of the type (provided it
--   doesn't have char* or string_t strings)

--[=[ Usage:
    local struct = require "struct"

    -- define struct type
    local myStruct = struct [[
        typedef uint32_t array8_t[8];
        struct {
            int foo;
            double bar;
            array8_t baz;
            const char * name;
            union {
                int i;
                float f;
            } data;
        }
    ]]
    -- encode table to binary
    local binary = myStruct {
        foo = 10,
        bar = 3.14,
        baz = {1, 2, 3, 4, 5, 6, 7, 8},
        name = "Hello World!",
        data = {f = 0.5}
    }
    -- decode to table
    local tab = myStruct(binary)
    print(tab.name, tab.data.i)

    -- chain type definitions
    local types = {}
    struct([[
        typedef struct {
            unsigned short	coord, inc;
        } EnvNode;

        typedef struct {
            EnvNode			nodes[12];
            unsigned char	max;
            unsigned char	sus;
            unsigned char	loopStart;
            unsigned char	flags;
        } Envelope;

        typedef struct {
            unsigned short	samples[96];
            Envelope		envVol;
            Envelope		envPan;
            unsigned short	volFade;
            unsigned char	vibType;
            unsigned char	vibSweep;
            unsigned char	vibDepth;
            unsigned char	vibRate;
        } Instrument;
    ]], types)
    -- get the size of a type
    print(#types.Instrument)
    -- create empty object
    local inst = types.Instrument()
    inst.envVol.nodes[1] = {5, 12}
    -- write to file
    local file = io.open("file.bin", "wb")
    file:write(types.Instrument(inst))
    file:close()

    -- variable length arrays
    struct([[
        struct {
            uint8_t szNodes;
            EnvNode nodes[0];
        } VarEnvelope;
    ]], types)
    local st = {szNodes = 6, nodes = {}}
    for i = 1, 6 do st.nodes[i] = {coord = i*2-1, inc = i*2} end
    -- encode
    local data = types.VarEnvelope(st)
    for i = 1, st.szNodes do data = data .. types.EnvNode(st.nodes[i]) end
    -- decode
    local tab, pos = types.VarEnvelope(data)
    for i = 1, tab.szNodes do tab.nodes[i], pos = types.EnvNode(data, pos) end
--]=]

local keywords = {
	bool = { 0 },
	char = { 1 },
	short = { 2 },
	long = { 3 },
	int = { 4 },
	float = { 5 },
	double = { 6 },
	unsigned = { 7 },
	signed = { 8 },
	const = { 9 },
	typedef = { 10 },
	struct = { 11 },
	union = { 12 },
	enum = { 13 },
}

local symbols = {
	["*"] = { 16 },
	["["] = { 17 },
	["]"] = { 18 },
	["{"] = { 19 },
	["}"] = { 20 },
	[";"] = { 21 },
	[","] = { 22 },
	["="] = { 23 },
}

for k, v in pairs(keywords) do
	setmetatable(v, {
		__tostring = function()
			return k
		end,
	})
end
for k, v in pairs(symbols) do
	setmetatable(v, {
		__tostring = function()
			return k
		end,
	})
end

local function mktype(a, ...)
	return a and 2 ^ a[1] + mktype(...) or 0
end

local base_types = {
	[mktype(keywords.bool)] = setmetatable({}, {
		__call = function(_, v, p)
			if type(v) == "string" then
				return v:byte(p) ~= 0, (p or 1) + 1
			elseif type(v) == "boolean" then
				return v and "\x01" or "\0"
			end
		end,
		__len = function()
			return 1
		end,
	}),
	[mktype(keywords.char)] = "b",
	[mktype(keywords.signed, keywords.char)] = "b",
	[mktype(keywords.unsigned, keywords.char)] = "B",
	[mktype(keywords.short)] = "h",
	[mktype(keywords.signed, keywords.short)] = "h",
	[mktype(keywords.unsigned, keywords.short)] = "H",
	[mktype(keywords.int)] = "i",
	[mktype(keywords.signed, keywords.int)] = "i",
	[mktype(keywords.signed)] = "i",
	[mktype(keywords.unsigned, keywords.int)] = "I",
	[mktype(keywords.unsigned)] = "I",
	[mktype(keywords.long, keywords.int)] = "l",
	[mktype(keywords.long, keywords.signed, keywords.int)] = "l",
	[mktype(keywords.long, keywords.signed)] = "l",
	[mktype(keywords.long, keywords.unsigned, keywords.int)] = "L",
	[mktype(keywords.long, keywords.unsigned)] = "L",
	[mktype(keywords.float)] = "f",
	[mktype(keywords.double)] = "d",
	int8_t = "i1",
	uint8_t = "I1",
	int16_t = "i2",
	uint16_t = "I2",
	int32_t = "i4",
	uint32_t = "I4",
	int64_t = "i8",
	uint64_t = "I8",
	intmax_t = "i8",
	uintmax_t = "I8",
	size_t = "T",
	string_t = "s",
	string8_t = "s1",
	string16_t = "s2",
	string32_t = "s4",
	string64_t = "s8",
	lua_Integer = "j",
	lua_Unsigned = "J",
	lua_Number = "n",
}

local struct, union

local array_mt = {
	__call = function(self, obj, pos)
		if type(obj) == "table" then
			local res = ""
			for i = 1, self.size do
				if type(self.type) == "string" then
					res = res .. self.type:pack(obj[i])
				else
					res = res .. self.type(obj[i])
				end
			end
			return res
		elseif type(obj) == "string" then
			local res = {}
			for i = 1, self.size do
				if type(self.type) == "string" then
					res[i], pos = self.type:unpack(obj, pos)
				else
					res[i], pos = self.type(obj, pos)
				end
			end
			return res, pos
		elseif obj == nil then
			local res = {}
			for i = 1, self.size do
				if type(self.type) == "string" then
					res[i] = (self.type == "z" or self.type:sub(1, 1) == "c" or self.type:sub(1, 1) == "s") and "" or 0
				else
					res[i] = self.type()
				end
			end
			return res
		else
			error("bad argument #1 (expected string or table, got " .. type(obj) .. ")", 2)
		end
	end,
	__len = function(self)
		if type(self.type) == "string" then
			return self.type:packsize() * self.size
		else
			return #self.type * self.size
		end
	end,
}

local struct_mt = {
	__call = function(self, obj, pos)
		if type(obj) == "table" then
			local res = ""
			local fmt, par = "", {}
			for _, v in ipairs(self) do
				if type(v.type) == "string" then
					fmt, par[#par + 1] = fmt .. v.type, obj[v.name]
				else
					if #fmt > 0 then
						res, fmt, par = res .. fmt:pack(table.unpack(par)), "", {}
					end
					res = res .. v.type(obj[v.name])
				end
			end
			if #fmt > 0 then
				res = res .. fmt:pack(table.unpack(par))
			end
			return res
		elseif type(obj) == "string" then
			pos = pos or 1
			local res, fmt, names = {}, "", {}
			for _, v in ipairs(self) do
				if type(v.type) == "string" then
					fmt, names[#names + 1] = fmt .. v.type, v.name
				else
					if #fmt > 0 then
						local r = table.pack(fmt:unpack(obj, pos))
						for i = 1, r.n - 1 do
							res[names[i]] = r[i]
						end
						pos = r[r.n]
						fmt, names = "", {}
					end
					res[v.name], pos = v.type(obj, pos)
				end
			end
			if #fmt > 0 then
				local r = table.pack(fmt:unpack(obj, pos))
				for i = 1, r.n - 1 do
					res[names[i]] = r[i]
				end
				pos = r[r.n]
			end
			return res, pos
		elseif obj == nil then
			local res = {}
			for _, v in ipairs(self) do
				if type(v.type) == "string" then
					res[v.name] = (v.type == "z" or v.type:sub(1, 1) == "c" or v.type:sub(1, 1) == "s") and "" or 0
				else
					res[v.name] = v.type()
				end
			end
			return res
		else
			error("bad argument #1 (expected string or table, got " .. type(obj) .. ")", 2)
		end
	end,
	__len = function(self)
		local sum = 0
		local fmt = ""
		for _, v in ipairs(self) do
			if type(v.type) == "string" then
				fmt = fmt .. v.type
			else
				if #fmt > 0 then
					sum, fmt = sum + fmt:packsize(), ""
				end
				sum = sum + #v.type
			end
		end
		if #fmt > 0 then
			sum, fmt = sum + fmt:packsize(), ""
		end
		return sum
	end,
}

local union_mt = {
	__call = function(self, obj, pos)
		if type(obj) == "table" then
			local res = ""
			local name = next(obj)
			local max = 0
			if not name or next(obj, name) then
				error("bad argument #1 (union table must contain exactly one entry)", 2)
			end
			for _, v in ipairs(self) do
				if type(v.type) == "string" then
					if v.name == name then
						res = v.type:pack(obj[v.name])
					end
					max = math.max(max, v.type:packsize())
				else
					if v.name == name then
						res = v.type(obj[v.name])
					end
					max = math.max(max, #v.type)
				end
			end
			return res .. ("\0"):rep(max - #res)
		elseif type(obj) == "string" then
			pos = pos or 1
			local res = {}
			local max = pos
			for _, v in ipairs(self) do
				local np
				if type(v.type) == "string" then
					res[v.name], np = v.type:unpack(obj, pos)
				else
					res[v.name], np = v.type(obj, pos)
				end
				max = math.max(max, np)
			end
			return res, max
		elseif obj == nil then
			return {}
		else
			error("bad argument #1 (expected string or table, got " .. type(obj) .. ")", 2)
		end
	end,
	__len = function(self)
		local max = 0
		for _, v in ipairs(self) do
			if type(v.type) == "string" then
				max = math.max(max, v.type:packsize())
			else
				max = math.max(max, #v.type)
			end
		end
		return max
	end,
}

function struct(tokens, pos, types)
	local s = {}
	while tokens[pos] ~= symbols["}"] do
		if not tokens[pos] then
			error("syntax error: expected '}' near <eof>", 2)
		end
		local ent = {}
		s[#s + 1] = ent
		local tl = {}
		while type(tokens[pos]) == "table" and tokens[pos][1] < 10 do
			if tokens[pos] ~= keywords.const then
				tl[#tl + 1] = tokens[pos]
			end
			pos = pos + 1
		end
		if #tl == 0 then
			if type(tokens[pos]) == "string" then
				ent.type = types[tokens[pos]]
				if not ent.type then
					error("compile error: undefined type " .. tostring(tokens[pos]), 3)
				end
				pos = pos + 1
			elseif tokens[pos] == keywords.struct then
				pos = pos + 1
				if type(tokens[pos]) == "string" then
					ent.type = types.struct[tokens[pos]]
					if not ent.type then
						error("compile error: undefined struct type " .. tostring(tokens[pos]), 3)
					end
					pos = pos + 1
				elseif tokens[pos] == symbols["{"] then
					ent.type, pos = struct(tokens, pos + 1, types)
				else
					error("syntax error near 'struct " .. tostring(tokens[pos]) .. "'", 3)
				end
			elseif tokens[pos] == keywords.union then
				pos = pos + 1
				if type(tokens[pos]) == "string" then
					ent.type = types.union[tokens[pos]]
					if not ent.type then
						error("compile error: undefined union type " .. tostring(tokens[pos]), 3)
					end
					pos = pos + 1
				elseif tokens[pos] == symbols["{"] then
					ent.type, pos = union(tokens, pos + 1, types)
				else
					error("syntax error near 'union " .. tostring(tokens[pos]) .. "'", 3)
				end
			elseif tokens[pos] == keywords.enum then
				ent.type = types.int
				assert(
					type(tokens[pos + 1]) == "string",
					"syntax error near 'enum " .. tostring(tokens[pos + 1]) .. "'"
				)
				pos = pos + 2
			else
				error("syntax error near '" .. tostring(tokens[pos]) .. "'" .. pos .. #s, 3)
			end
		else
			ent.type = types[mktype(table.unpack(tl))]
			if not ent.type then
				error("syntax error: invalid type combination '" .. table.concat(tl, " ") .. "'", 3)
			end
		end
		local basetype = ent.type
		if basetype == "b" and tokens[pos] == symbols["*"] then
			ent.type, pos = "z", pos + 1
		end
		if type(tokens[pos]) ~= "string" then
			error("syntax error near " .. tostring(tokens[pos]), 3)
		end
		ent.name = tokens[pos]
		pos = pos + 1
		if tokens[pos] == symbols["["] then
			local array = {}
			while tokens[pos] == symbols["["] do
				pos = pos + 1
				if type(tokens[pos]) ~= "number" then
					error("syntax error near '[" .. tostring(tokens[pos]) .. "]'", 3)
				end
				array[#array + 1] = tokens[pos]
				pos = pos + 1
				if tokens[pos] ~= symbols["]"] then
					error("syntax error near '[" .. array[#array] .. tostring(tokens[pos]) .. "'", 3)
				end
				pos = pos + 1
			end
			if ent.type == "b" and #array == 1 then
				ent.type = "c" .. array[1]
			else
				for i = #array, 1, -1 do
					ent.type = setmetatable({ type = ent.type, size = array[i] }, array_mt)
				end
			end
		end
		while tokens[pos] == symbols[","] do
			local e = { type = basetype }
			s[#s + 1] = e
			pos = pos + 1
			if basetype == "b" and tokens[pos] == symbols["*"] then
				e.type, pos = "z", pos + 1
			end
			if type(tokens[pos]) ~= "string" then
				error("syntax error near " .. tostring(tokens[pos]), 3)
			end
			e.name = tokens[pos]
			pos = pos + 1
			if tokens[pos] == symbols["["] then
				local array = {}
				while tokens[pos] == symbols["["] do
					pos = pos + 1
					if type(tokens[pos]) ~= "number" then
						error("syntax error near '[" .. tostring(tokens[pos]) .. "]'", 3)
					end
					array[#array + 1] = tokens[pos]
					pos = pos + 1
					if tokens[pos] ~= symbols["]"] then
						error("syntax error near '[" .. array[#array] .. tostring(tokens[pos]) .. "'", 3)
					end
					pos = pos + 1
				end
				if e.type == "b" and #array == 1 then
					e.type = "c" .. array[1]
				else
					for i = #array, 1, -1 do
						e.type = setmetatable({ type = e.type, size = array[i] }, array_mt)
					end
				end
			end
		end
		if tokens[pos] ~= symbols[";"] then
			error("syntax error: expected ';' near '" .. tostring(tokens[pos]) .. "'", 3)
		end
		pos = pos + 1
	end
	return setmetatable(s, struct_mt), pos + 1
end

function union(tokens, pos, types)
	local s = {}
	while tokens[pos] ~= symbols["}"] do
		if not tokens[pos] then
			error("syntax error: expected '}' near <eof>", 2)
		end
		local ent = {}
		s[#s + 1] = ent
		local tl = {}
		while type(tokens[pos]) == "table" and tokens[pos][1] < 10 do
			if tokens[pos] ~= keywords.const then
				tl[#tl + 1] = tokens[pos]
			end
			pos = pos + 1
		end
		if #tl == 0 then
			if type(tokens[pos]) == "string" then
				ent.type = types[tokens[pos]]
				if not ent.type then
					error("compile error: undefined type " .. tostring(tokens[pos]), 3)
				end
				pos = pos + 1
			elseif tokens[pos] == keywords.struct then
				pos = pos + 1
				if type(tokens[pos]) == "string" then
					ent.type = types.struct[tokens[pos]]
					if not ent.type then
						error("compile error: undefined struct type " .. tostring(tokens[pos]), 3)
					end
					pos = pos + 1
				elseif tokens[pos] == symbols["{"] then
					ent.type, pos = struct(tokens, pos + 1, types)
				else
					error("syntax error near 'struct " .. tostring(tokens[pos]) .. "'", 3)
				end
			elseif tokens[pos] == keywords.union then
				pos = pos + 1
				if type(tokens[pos]) == "string" then
					ent.type = types.union[tokens[pos]]
					if not ent.type then
						error("compile error: undefined union type " .. tostring(tokens[pos]), 3)
					end
					pos = pos + 1
				elseif tokens[pos] == symbols["{"] then
					ent.type, pos = union(tokens, pos + 1, types)
				else
					error("syntax error near 'union " .. tostring(tokens[pos]) .. "'", 3)
				end
			elseif tokens[pos] == keywords.enum then
				ent.type = types.int
				assert(
					type(tokens[pos + 1]) == "string",
					"syntax error near 'enum " .. tostring(tokens[pos + 1]) .. "'"
				)
				pos = pos + 2
			else
				error("syntax error near '" .. tostring(tokens[pos]) .. "'", 3)
			end
		else
			ent.type = types[mktype(table.unpack(tl))]
			if not ent.type then
				error("syntax error: invalid type combination '" .. table.concat(tl, " ") .. "'", 3)
			end
		end
		local basetype = ent.type
		if basetype == "b" and tokens[pos] == symbols["*"] then
			error("compiler error: C strings are not allowed in unions")
		end
		if type(tokens[pos]) ~= "string" then
			error("syntax error near " .. tostring(tokens[pos]), 3)
		end
		ent.name = tokens[pos]
		pos = pos + 1
		if tokens[pos] == symbols["["] then
			local array = {}
			while tokens[pos] == symbols["["] do
				pos = pos + 1
				if type(tokens[pos]) ~= "number" then
					error("syntax error near '[" .. tostring(tokens[pos]) .. "]'", 3)
				end
				array[#array + 1] = tokens[pos]
				pos = pos + 1
				if tokens[pos] ~= symbols["]"] then
					error("syntax error near '[" .. array[#array] .. tostring(tokens[pos]) .. "'", 3)
				end
				pos = pos + 1
			end
			if ent.type == "b" and #array == 1 then
				ent.type = "c" .. array[1]
			else
				for i = #array, 1, -1 do
					ent.type = setmetatable({ type = ent.type, size = array[i] }, array_mt)
				end
			end
		end
		while tokens[pos] == symbols[","] do
			local e = { type = basetype }
			s[#s + 1] = e
			pos = pos + 1
			if basetype == "b" and tokens[pos] == symbols["*"] then
				error("compiler error: C strings are not allowed in unions")
			end
			if type(tokens[pos]) ~= "string" then
				error("syntax error near " .. tostring(tokens[pos]), 3)
			end
			e.name = tokens[pos]
			pos = pos + 1
			if tokens[pos] == symbols["["] then
				local array = {}
				while tokens[pos] == symbols["["] do
					pos = pos + 1
					if type(tokens[pos]) ~= "number" then
						error("syntax error near '[" .. tostring(tokens[pos]) .. "]'", 3)
					end
					array[#array + 1] = tokens[pos]
					pos = pos + 1
					if tokens[pos] ~= symbols["]"] then
						error("syntax error near '[" .. array[#array] .. tostring(tokens[pos]) .. "'", 3)
					end
					pos = pos + 1
				end
				if e.type == "b" and #array == 1 then
					e.type = "c" .. array[1]
				else
					for i = #array, 1, -1 do
						e.type = setmetatable({ type = e.type, size = array[i] }, array_mt)
					end
				end
			end
		end
		if tokens[pos] ~= symbols[";"] then
			error("syntax error: expected ';' near '" .. tostring(tokens[pos]) .. "'", 3)
		end
		pos = pos + 1
	end
	return setmetatable(s, union_mt), pos + 1
end

local function tokenize(str)
	local pos = str:find("%S")
	local tokens = {}
	while pos <= #str do
		local m, p = str:match("^([A-Za-z_][A-Za-z0-9_]*)()", pos)
		if m then
			tokens[#tokens + 1], pos = keywords[m] or m, p
		else
			m, p = str:match("^([%*%[%]{};,=])()", pos)
			if m then
				tokens[#tokens + 1], pos = symbols[m], p
			else
				m, p = str:match("^0([0-7]+)[Uu]?[Ll]?()", pos)
				if m then
					tokens[#tokens + 1], pos = tonumber(m, 8), p
				else
					m, p = str:match("^0x(%x+)[Uu]?[Ll]?()", pos)
					if m then
						tokens[#tokens + 1], pos = tonumber(m, 16), p
					else
						m, p = str:match("^0b([01]+)[Uu]?[Ll]?()", pos)
						if m then
							tokens[#tokens + 1], pos = tonumber(m, 1), p
						else
							m, p = str:match("^(%d+)[Uu]?[Ll]?()", pos)
							if m then
								tokens[#tokens + 1], pos = tonumber(m, 10), p
							else
								error("syntax error near '" .. str:sub(pos, pos + 5) .. "'", 3)
							end
						end
					end
				end
			end
		end
		pos = str:find("%S", pos)
		if not pos then
			break
		end
	end
	return tokens
end

return function(def, types)
	if type(def) ~= "string" then
		error("bad argument #1 (expected string, got " .. type(def) .. ")", 2)
	end
	if types ~= nil and type(types) ~= "table" then
		error("bad argument #2 (expected table, got " .. type(types) .. ")", 2)
	end
	types = types or { struct = {}, union = {} }
	if not types.struct then
		types.struct = {}
	end
	if not types.union then
		types.union = {}
	end
	setmetatable(types, { __index = base_types })
	local tokens = tokenize(def)
	local pos = 1
	local last
	while pos < #tokens do
		if tokens[pos] == keywords.typedef then
			pos = pos + 1
			local tl = {}
			local tt
			while type(tokens[pos]) == "table" and tokens[pos][1] < 10 do
				if tokens[pos] ~= keywords.const then
					tl[#tl + 1] = tokens[pos]
				end
				pos = pos + 1
			end
			if #tl == 0 then
				if type(tokens[pos]) == "string" then
					tt = types[tokens[pos]]
					if not tt then
						error("compile error: undefined type " .. tostring(tokens[pos]), 2)
					end
					pos = pos + 1
				elseif tokens[pos] == keywords.struct then
					pos = pos + 1
					if type(tokens[pos]) == "string" then
						tt = types.struct[tokens[pos]]
						if not tt then
							local name = tokens[pos]
							pos = pos + 1
							if tokens[pos] == symbols["{"] then
								tt, pos = struct(tokens, pos + 1, types)
							else
								error("compile error: undefined struct type " .. name, 2)
							end
							types.struct[name] = tt
						else
							pos = pos + 1
						end
					elseif tokens[pos] == symbols["{"] then
						tt, pos = struct(tokens, pos + 1, types)
					else
						error("syntax error near 'struct " .. tostring(tokens[pos]) .. "'", 2)
					end
				elseif tokens[pos] == keywords.union then
					pos = pos + 1
					if type(tokens[pos]) == "string" then
						tt = types.union[tokens[pos]]
						if not tt then
							local name = tokens[pos]
							pos = pos + 1
							if tokens[pos] == symbols["{"] then
								tt, pos = union(tokens, pos + 1, types)
							else
								error("compile error: undefined union type " .. name, 2)
							end
							types.union[name] = tt
						else
							pos = pos + 1
						end
						pos = pos + 1
					elseif tokens[pos] == symbols["{"] then
						tt, pos = union(tokens, pos + 1, types)
					else
						error("syntax error near 'union " .. tostring(tokens[pos]) .. "'", 2)
					end
				elseif tokens[pos] == keywords.enum then
					tt = types.int
					assert(
						type(tokens[pos + 1]) == "string",
						"syntax error near 'enum " .. tostring(tokens[pos + 1]) .. "'"
					)
					pos = pos + 2
				else
					error("syntax error near '" .. tostring(tokens[pos]) .. "'", 2)
				end
			else
				tt = types[mktype(table.unpack(tl))]
				if not tt then
					error("syntax error: invalid type combination '" .. table.concat(tl, " ") .. "'", 2)
				end
			end
			local basett = tt
			if tt == "b" and tokens[pos] == symbols["*"] then
				tt, pos = "z", pos + 1
			end
			if type(tokens[pos]) ~= "string" then
				error("syntax error near " .. tostring(tokens[pos]), 2)
			end
			local name = tokens[pos]
			pos = pos + 1
			if tokens[pos] == symbols["["] then
				local array = {}
				while tokens[pos] == symbols["["] do
					pos = pos + 1
					if type(tokens[pos]) ~= "number" then
						error("syntax error near '[" .. tostring(tokens[pos]) .. "]'", 3)
					end
					array[#array + 1] = tokens[pos]
					pos = pos + 1
					if tokens[pos] ~= symbols["]"] then
						error("syntax error near '[" .. array[#array] .. tostring(tokens[pos]) .. "'", 3)
					end
					pos = pos + 1
				end
				if tt == "b" and #array == 1 then
					tt = "c" .. array[1]
				else
					for i = #array, 1, -1 do
						tt = setmetatable({ type = tt, size = array[i] }, array_mt)
					end
				end
			end
			types[name] = tt
			while tokens[pos] == symbols[","] do
				local tt2 = basett
				pos = pos + 1
				if tt2 == "b" and tokens[pos] == symbols["*"] then
					tt2, pos = "z", pos + 1
				end
				if type(tokens[pos]) ~= "string" then
					error("syntax error near " .. tostring(tokens[pos]), 2)
				end
				local name2 = tokens[pos]
				pos = pos + 1
				if tokens[pos] == symbols["["] then
					local array = {}
					while tokens[pos] == symbols["["] do
						pos = pos + 1
						if type(tokens[pos]) ~= "number" then
							error("syntax error near '[" .. tostring(tokens[pos]) .. "]'", 3)
						end
						array[#array + 1] = tokens[pos]
						pos = pos + 1
						if tokens[pos] ~= symbols["]"] then
							error("syntax error near '[" .. array[#array] .. tostring(tokens[pos]) .. "'", 3)
						end
						pos = pos + 1
					end
					if tt2 == "b" and #array == 1 then
						tt2 = "c" .. array[1]
					else
						for i = #array, 1, -1 do
							tt2 = setmetatable({ type = tt2, size = array[i] }, array_mt)
						end
					end
				end
				types[name2] = tt2
			end
			if tokens[pos] ~= symbols[";"] then
				error("syntax error: expected ';' near '" .. tostring(tokens[pos]) .. "'", 2)
			end
			last = tt
			pos = pos + 1
		elseif tokens[pos] == keywords.struct then
			pos = pos + 1
			if type(tokens[pos]) == "string" then
				local name = tokens[pos]
				pos = pos + 1
				if tokens[pos] == symbols["{"] then
					last, pos = struct(tokens, pos + 1, types)
				else
					error("syntax error: expected '{' near '" .. tostring(tokens[pos]) .. "}", 2)
				end
				types.struct[name] = last
			elseif tokens[pos] == symbols["{"] then
				last, pos = struct(tokens, pos + 1, types)
			else
				error("syntax error near 'struct " .. tostring(tokens[pos]) .. "'", 3)
			end
		elseif tokens[pos] == keywords.union then
			pos = pos + 1
			if type(tokens[pos]) == "string" then
				local name = tokens[pos]
				pos = pos + 1
				if tokens[pos] == symbols["{"] then
					last, pos = union(tokens, pos + 1, types)
				else
					error("syntax error: expected '{' near '" .. tostring(tokens[pos]) .. "}", 2)
				end
				types.union[name] = last
			elseif tokens[pos] == symbols["{"] then
				last, pos = union(tokens, pos + 1, types)
			else
				error("syntax error near 'struct " .. tostring(tokens[pos]) .. "'", 3)
			end
		elseif tokens[pos] == keywords.enum then
			while tokens[pos] ~= symbols["}"] do
				pos = pos + 1
				if not tokens[pos] then
					error("syntax error: expected '}' near <eof>", 2)
				end
			end
		else
			error("compiler error: unexpected token " .. tostring(tokens[pos]), 2)
		end
	end
	return last
end
