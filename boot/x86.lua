-- x86.lua
local shared = require("cpu_shared")
local bit32 = bit32
local band, bor, bxor, lshift, rshift = bit32.band, bit32.bor, bit32.bxor, bit32.lshift, bit32.rshift

local function u32(x) return shared.u32(x) end
local function s32(x) return shared.s32(x) end
local function sext(v, b) return shared.sext(v, b) end
local function newMemory(n) return shared.newMemory(n) end

local function parity8(x)
	x = band(x, 0xFF)
	local p = 0
	for _ = 1, 8 do
		p = bxor(p, band(x, 1))
		x = rshift(x, 1)
	end
	return p == 0
end

local X86 = {}

local function create(opts)
	opts = opts or {}
	local cpu = {
		mode = "i386",
		reg = {},
		eip = 0,
		eflags = 0x2,
		mem = newMemory(opts.memSize or 0x1000000),
		memSize = opts.memSize or 0x1000000,
		halt = false,
		syscalls = opts.syscalls or {},
	}

	for i = 0, 7 do
		cpu.reg[i] = 0
	end

	local methods = {}

	function methods:getReg(i)
		return self.reg[i] or 0
	end

	function methods:setReg(i, v)
		self.reg[i] = u32(v)
	end

	function methods:setFlag(mask, cond)
		if cond then
			self.eflags = bor(self.eflags, mask)
		else
			self.eflags = band(self.eflags, bit32.bnot(mask))
		end
	end

	function methods:getFlag(mask)
		return band(self.eflags, mask) ~= 0
	end

	function methods:updateLogicFlags(result, bits)
		result = u32(result)
		self:setFlag(0x40, result == 0)
		self:setFlag(0x80, band(result, 2 ^ (bits - 1)) ~= 0)
		self:setFlag(0x1, false)
		self:setFlag(0x800, false)
	end

	function methods:updateAddFlags(a, b, result, bits)
		local mask = 2 ^ bits
		local sign = 2 ^ (bits - 1)
		local ua = a % mask
		local ub = b % mask
		local ur = result % mask
		self:setFlag(0x1, result >= mask)
		self:setFlag(0x40, ur == 0)
		self:setFlag(0x80, band(ur, sign) ~= 0)
		self:setFlag(0x800, band(bit32.bxor(bit32.bxor(a, result), bit32.bxor(b, result)), sign) ~= 0)
		self:setFlag(0x4, parity8(ur))
	end

	function methods:updateSubFlags(a, b, result, bits)
		local mask = 2 ^ bits
		local sign = 2 ^ (bits - 1)
		local ua = a % mask
		local ub = b % mask
		local ur = result % mask
		self:setFlag(0x1, ua < ub)
		self:setFlag(0x40, ur == 0)
		self:setFlag(0x80, band(ur, sign) ~= 0)
		self:setFlag(0x800, band(bit32.bxor(a, b), bit32.bxor(a, result), sign) ~= 0)
		self:setFlag(0x4, parity8(ur))
	end

	function methods:fetch8()
		local b = self.mem:read8(self.eip)
		self.eip = u32(self.eip + 1)
		return b
	end

	function methods:fetch16()
		local v = self.mem:read16(self.eip)
		self.eip = u32(self.eip + 2)
		return v
	end

	function methods:fetch32()
		local v = self.mem:read32(self.eip)
		self.eip = u32(self.eip + 4)
		return v
	end

	function methods:loadBuffer(buf, addr)
		self.mem:loadBuffer(buf, addr or 0)
	end

	function methods:reset(memSize)
		self.memSize = memSize or self.memSize
		self.mem = newMemory(self.memSize)
		self.halt = false
		self.eip = 0
		self.eflags = 0x2
		for i = 0, 7 do self.reg[i] = 0 end
	end

	function methods:getModRM(stream)
		local b = stream:fetch8()
		return bit32.rshift(b, 6), band(bit32.rshift(b, 3), 7), band(b, 7), b
	end

	function methods:readEA32(mod, rm, fetchDisp)
		if mod == 3 then
			return nil, rm
		end
		local base = 0
		local index = 0
		local scale = 1
		local disp = 0
		if rm == 4 then
			local sib = self:fetch8()
			scale = 2 ^ bit32.rshift(sib, 6)
			index = band(bit32.rshift(sib, 3), 7)
			base = band(sib, 7)
			if index == 4 then index = nil end
			if mod == 0 and base == 5 then
				base = nil
				disp = s32(self:fetch32())
			end
		else
			base = rm
			if mod == 0 and rm == 5 then
				base = nil
				disp = s32(self:fetch32())
			end
		end
		if mod == 1 then
			disp = disp + sext(self:fetch8(), 8)
		elseif mod == 2 then
			disp = disp + s32(self:fetch32())
		end
		local addr = disp
		if base then addr = addr + self.reg[base] end
		if index then addr = addr + self.reg[index] * scale end
		return u32(addr)
	end

	function methods:readOp32(mod, rm)
		if mod == 3 then
			return self.reg[rm]
		end
		local addr = self:readEA32(mod, rm)
		return self.mem:read32(addr)
	end

	function methods:writeOp32(mod, rm, value)
		if mod == 3 then
			self.reg[rm] = u32(value)
			return
		end
		local addr = self:readEA32(mod, rm)
		self.mem:write32(addr, value)
	end

	function methods:push32(v)
		self.reg[4] = u32(self.reg[4] - 4)
		self.mem:write32(self.reg[4], v)
	end

	function methods:pop32()
		local v = self.mem:read32(self.reg[4])
		self.reg[4] = u32(self.reg[4] + 4)
		return v
	end

	function methods:dump()
		local out = { ("eip=%08x eflags=%08x"):format(self.eip, self.eflags) }
		for i = 0, 7 do
			out[#out + 1] = ("r%d=%08x"):format(i, self.reg[i] or 0)
		end
		return table.concat(out, "\n")
	end

	local function cond(cpu, cc)
		local zf = band(cpu.eflags, 0x40) ~= 0
		local sf = band(cpu.eflags, 0x80) ~= 0
		local of = band(cpu.eflags, 0x800) ~= 0
		local cf = band(cpu.eflags, 0x1) ~= 0
		if cc == 0 then return zf end -- O not used
		if cc == 1 then return not zf end -- NO not used
		if cc == 2 then return cf end
		if cc == 3 then return not cf end
		if cc == 4 then return zf end
		if cc == 5 then return not zf end
		if cc == 6 then return cf or zf end
		if cc == 7 then return not cf and not zf end
		if cc == 8 then return sf end
		if cc == 9 then return not sf end
		if cc == 10 then return of end
		if cc == 11 then return not of end
		if cc == 12 then return sf ~= of end
		if cc == 13 then return sf == of end
		if cc == 14 then return zf or (sf ~= of) end
		if cc == 15 then return (not zf) and (sf == of) end
		return false
	end

	function methods:step()
		if self.halt then return true end
		local start = self.eip

		local prefix66, prefix67 = false, false
		local op = self:fetch8()
		while op == 0x66 or op == 0x67 or op == 0xF0 or op == 0xF2 or op == 0xF3 do
			if op == 0x66 then prefix66 = true end
			if op == 0x67 then prefix67 = true end
			op = self:fetch8()
		end

		if op >= 0x50 and op <= 0x57 then
			self:push32(self.reg[op - 0x50])
		elseif op >= 0x58 and op <= 0x5F then
			self.reg[op - 0x58] = self:pop32()

		elseif op >= 0xB8 and op <= 0xBF then
			self.reg[op - 0xB8] = self:fetch32()

		elseif op == 0x90 then
			-- nop

		elseif op == 0xF4 then
			self.halt = true

		elseif op == 0xC3 then
			self.eip = self:pop32()
			return false

		elseif op == 0xE8 then
			local rel = s32(self:fetch32())
			self:push32(self.eip)
			self.eip = u32(self.eip + rel)
			return false

		elseif op == 0xE9 then
			self.eip = u32(self.eip + s32(self:fetch32()))
			return false

		elseif op == 0xEB then
			local rel = sext(self:fetch8(), 8)
			self.eip = u32(self.eip + rel)
			return false

		elseif op == 0x05 then
			local imm = self:fetch32()
			local a = self.reg[0]
			local r = u32(a + imm)
			self.reg[0] = r
			self:setFlag(0x1, (a + imm) >= 0x100000000)
			self:setFlag(0x40, r == 0)
			self:setFlag(0x80, band(r, 0x80000000) ~= 0)

		elseif op == 0x2D then
			local imm = self:fetch32()
			local a = self.reg[0]
			local r = u32(a - imm)
			self.reg[0] = r
			self:setFlag(0x1, a < imm)
			self:setFlag(0x40, r == 0)
			self:setFlag(0x80, band(r, 0x80000000) ~= 0)

		elseif op == 0x0F then
			local op2 = self:fetch8()
			if op2 >= 0x80 and op2 <= 0x8F then
				local rel = s32(self:fetch32())
				if cond(self, op2 - 0x80) then
					self.eip = u32(self.eip + rel)
				end
				return false
			else
				error(("unhandled 0F opcode %02X at %08X"):format(op2, start))
			end

		elseif op == 0x74 or op == 0x75 then
			local rel = sext(self:fetch8(), 8)
			local zf = band(self.eflags, 0x40) ~= 0
			if (op == 0x74 and zf) or (op == 0x75 and not zf) then
				self.eip = u32(self.eip + rel)
			end
			return false

		elseif op == 0x89 or op == 0x8B or op == 0x8D or op == 0x01 or op == 0x03 or op == 0x29 or op == 0x2B or op == 0x21 or op == 0x23 or op == 0x31 or op == 0x33 or op == 0x39 or op == 0x3B or op == 0x85 or op == 0x87 then
			local mod, reg, rm = self:getModRM(self)
			if op == 0x8D then
				self.reg[reg] = self:readEA32(mod, rm)
			else
				local src = self:readOp32(mod, rm)
				local dst = self.reg[reg]
				if op == 0x8B then
					self.reg[reg] = src
				elseif op == 0x89 then
					self:writeOp32(mod, rm, self.reg[reg])
				elseif op == 0x01 then
					self:writeOp32(mod, rm, u32(src + dst))
				elseif op == 0x03 then
					self.reg[reg] = u32(dst + src)
				elseif op == 0x29 then
					self:writeOp32(mod, rm, u32(src - dst))
				elseif op == 0x2B then
					self.reg[reg] = u32(dst - src)
				elseif op == 0x21 then
					self:writeOp32(mod, rm, band(src, dst))
				elseif op == 0x23 then
					self.reg[reg] = band(dst, src)
				elseif op == 0x31 then
					self:writeOp32(mod, rm, bxor(src, dst))
				elseif op == 0x33 then
					self.reg[reg] = bxor(dst, src)
				elseif op == 0x39 then
					self:setFlag(0x1, dst < src)
					self:setFlag(0x40, band(u32(dst - src), 0xFFFFFFFF) == 0)
				elseif op == 0x3B then
					self:setFlag(0x1, src < dst)
					self:setFlag(0x40, band(u32(src - dst), 0xFFFFFFFF) == 0)
				elseif op == 0x85 then
					local r = band(src, dst)
					self:setFlag(0x40, r == 0)
					self:setFlag(0x80, band(r, 0x80000000) ~= 0)
				elseif op == 0x87 then
					if mod == 3 then
						self.reg[rm], self.reg[reg] = self.reg[reg], self.reg[rm]
					else
						error("xchg memory form not implemented")
					end
				end
			end

		elseif op == 0x81 or op == 0x83 or op == 0xC7 then
			local mod, reg, rm = self:getModRM(self)
			local imm = (op == 0x83) and sext(self:fetch8(), 8) or self:fetch32()
			if op == 0xC7 then
				imm = self:fetch32()
				reg = 0
			end
			if reg == 0 then
				if mod == 3 then
					self.reg[rm] = u32(self.reg[rm] + imm)
				else
					local v = self:readOp32(mod, rm)
					self:writeOp32(mod, rm, u32(v + imm))
				end
			elseif reg == 5 then
				if mod == 3 then
					self.reg[rm] = u32(self.reg[rm] - imm)
				else
					local v = self:readOp32(mod, rm)
					self:writeOp32(mod, rm, u32(v - imm))
				end
			elseif reg == 7 then
				local v = (mod == 3) and self.reg[rm] or self:readOp32(mod, rm)
				self:setFlag(0x1, v < imm)
				self:setFlag(0x40, u32(v - imm) == 0)
			else
				error(("unhandled group1 reg=%d at %08X"):format(reg, start))
			end

		elseif op == 0xFF then
			local mod, reg, rm = self:getModRM(self)
			if reg == 2 then
				local target = (mod == 3) and self.reg[rm] or self:readOp32(mod, rm)
				self:push32(self.eip)
				self.eip = target
				return false
			elseif reg == 4 then
				self.eip = (mod == 3) and self.reg[rm] or self:readOp32(mod, rm)
				return false
			elseif reg == 6 then
				if mod == 3 then
					self.reg[rm] = u32(self.reg[rm] - 1)
				else
					self:writeOp32(mod, rm, u32(self:readOp32(mod, rm) - 1))
				end
			else
				error(("unhandled FF group reg=%d at %08X"):format(reg, start))
			end

		elseif op == 0xCD then
			local intno = self:fetch8()
			if intno == 0x80 then
				local h = self.syscalls[self.reg[0]]
				if h then
					self.reg[0] = h(self, self.reg[0], self.reg[1], self.reg[2], self.reg[3], self.reg[4], self.reg[5], self.reg[6])
				else
					self.reg[0] = 0xFFFFFFDA
				end
			else
				error(("software interrupt %02X not implemented"):format(intno))
			end

		else
			error(("unhandled x86 opcode %02X at %08X"):format(op, start))
		end

		self.eip = self.eip
		return self.halt
	end

	function methods:run(cycles)
		cycles = cycles or math.huge
		local count = 0

		while not self.halt and count < cycles do
			self:step()
			count = count + 1
		end
	end

	for k, v in pairs(methods) do
		cpu[k] = v
	end

	cpu.new = create
	cpu.Memory = shared.newMemory
	cpu.shared = shared

	return shared.newReadOnlyApi(cpu, "X86")
end

return create
