-- cpu_shared.lua
-- Shared helpers for buffer-backed emulator cores.
local bit32 = bit32
if not bit32 then
	error("bit32 is required")
end

local M = {}

local band = bit32.band
local bor = bit32.bor
local bxor = bit32.bxor
local lshift = bit32.lshift
local rshift = bit32.rshift

function M.u32(x)
	return band(x, 0xFFFFFFFF)
end

function M.s32(x)
	x = band(x, 0xFFFFFFFF)
	if x >= 0x80000000 then
		return x - 0x100000000
	end
	return x
end

function M.sext(value, bits)
	local mask = 2 ^ bits - 1
	local sign = 2 ^ (bits - 1)
	value = band(value, mask)
	if band(value, sign) ~= 0 then
		return value - 2 ^ bits
	end
	return value
end

function M.qnew(lo, hi)
	return { lo = M.u32(lo or 0), hi = M.u32(hi or 0) }
end

function M.qcopy(a)
	return { lo = M.u32(a.lo), hi = M.u32(a.hi) }
end

function M.qzero()
	return { lo = 0, hi = 0 }
end

function M.qadd(a, b)
	local lo = a.lo + b.lo
	local carry = 0
	if lo >= 0x100000000 then
		lo = lo - 0x100000000
		carry = 1
	end
	local hi = a.hi + b.hi + carry
	return M.qnew(lo, hi)
end

function M.qsub(a, b)
	local lo = a.lo - b.lo
	local borrow = 0
	if lo < 0 then
		lo = lo + 0x100000000
		borrow = 1
	end
	local hi = a.hi - b.hi - borrow
	if hi < 0 then
		hi = hi + 0x100000000
	end
	return M.qnew(lo, hi)
end



function M.qslt(a, b)
	local ahi = a.hi
	local bhi = b.hi
	if ahi >= 0x80000000 then ahi = ahi - 0x100000000 end
	if bhi >= 0x80000000 then bhi = bhi - 0x100000000 end
	if ahi ~= bhi then
		return ahi < bhi
	end
	return a.lo < b.lo
end
function M.qband(a, b)
	return M.qnew(band(a.lo, b.lo), band(a.hi, b.hi))
end

function M.qbor(a, b)
	return M.qnew(bor(a.lo, b.lo), bor(a.hi, b.hi))
end

function M.qbxor(a, b)
	return M.qnew(bxor(a.lo, b.lo), bxor(a.hi, b.hi))
end

function M.qshl(a, n)
	n = n % 64
	if n == 0 then
		return M.qcopy(a)
	elseif n < 32 then
		return M.qnew(
			M.u32(lshift(a.lo, n)),
			M.u32(bor(lshift(a.hi, n), rshift(a.lo, 32 - n)))
		)
	elseif n == 32 then
		return M.qnew(0, a.lo)
	else
		return M.qnew(0, M.u32(lshift(a.lo, n - 32)))
	end
end

function M.qshr(a, n)
	n = n % 64
	if n == 0 then
		return M.qcopy(a)
	elseif n < 32 then
		return M.qnew(
			M.u32(bor(rshift(a.lo, n), lshift(a.hi, 32 - n))),
			rshift(a.hi, n)
		)
	elseif n == 32 then
		return M.qnew(a.hi, 0)
	else
		return M.qnew(rshift(a.hi, n - 32), 0)
	end
end

function M.qsar(a, n)
	n = n % 64
	local sign = band(a.hi, 0x80000000) ~= 0
	if n == 0 then
		return M.qcopy(a)
	elseif n < 32 then
		return M.qnew(
			M.u32(bor(rshift(a.lo, n), lshift(a.hi, 32 - n))),
			M.u32(bit32.arshift(a.hi, n))
		)
	elseif n == 32 then
		return M.qnew(a.hi, sign and 0xFFFFFFFF or 0)
	else
		return M.qnew(
			M.u32(bit32.arshift(a.hi, n - 32)),
			sign and 0xFFFFFFFF or 0
		)
	end
end

function M.newMemory(size)
	local mem = {
		size = size or 0x1000000,
		data = {},
	}

	local function check(addr, bytes)
		if addr < 0 or addr + bytes > mem.size then
			error(("memory access out of bounds: %08X"):format(addr))
		end
	end

	function mem:read8(addr)
		check(addr, 1)
		return self.data[addr] or 0
	end

	function mem:write8(addr, val)
		check(addr, 1)
		self.data[addr] = band(val, 0xFF)
	end

	function mem:read16(addr)
		return bor(self:read8(addr), lshift(self:read8(addr + 1), 8))
	end

	function mem:write16(addr, val)
		self:write8(addr, band(val, 0xFF))
		self:write8(addr + 1, band(rshift(val, 8), 0xFF))
	end

	function mem:read32(addr)
		return M.u32(
			self:read8(addr)
			+ self:read8(addr + 1) * 256
			+ self:read8(addr + 2) * 65536
			+ self:read8(addr + 3) * 16777216
		)
	end

	function mem:write32(addr, val)
		self:write8(addr, band(val, 0xFF))
		self:write8(addr + 1, band(rshift(val, 8), 0xFF))
		self:write8(addr + 2, band(rshift(val, 16), 0xFF))
		self:write8(addr + 3, band(rshift(val, 24), 0xFF))
	end

	function mem:read64(addr)
		return M.qnew(self:read32(addr), self:read32(addr + 4))
	end

	function mem:write64(addr, q)
		self:write32(addr, q.lo)
		self:write32(addr + 4, q.hi)
	end

	function mem:loadBuffer(buf, addr)
		addr = addr or 0
		if type(buf) == "string" then
			for i = 1, #buf do
				self:write8(addr + i - 1, buf:byte(i))
			end
		elseif type(buf) == "table" then
			for i = 1, #buf do
				self:write8(addr + i - 1, buf[i])
			end
		else
			error("loadBuffer expects a string or table")
		end
	end

	function mem:readString(addr, maxlen)
		local out = {}
		if maxlen then
			for i = 0, maxlen - 1 do
				out[#out + 1] = string.char(self:read8(addr + i))
			end
		else
			local i = 0
			while true do
				local c = self:read8(addr + i)
				if c == 0 then
					break
				end
				out[#out + 1] = string.char(c)
				i = i + 1
			end
		end
		return table.concat(out)
	end

	return mem
end

function M.readModRM(stream)
	local byte = stream:fetch8()
	return bit32.rshift(byte, 6), bit32.band(bit32.rshift(byte, 3), 7), bit32.band(byte, 7), byte
end

function M.newReadOnlyApi(api, name)
	return setmetatable(api, {
		__newindex = function()
			error(name .. " API is read-only")
		end,
	})
end

return M
