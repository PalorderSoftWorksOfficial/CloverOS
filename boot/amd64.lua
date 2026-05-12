-- amd64.lua
local shared = require("cpu_shared")
local bit32 = bit32
local band, bor, bxor, lshift, rshift = bit32.band, bit32.bor, bit32.bxor, bit32.lshift, bit32.rshift

local function u32(x) return shared.u32(x) end
local function s32(x) return shared.s32(x) end
local function sext(v, b) return shared.sext(v, b) end
local function qnew(lo, hi) return shared.qnew(lo, hi) end
local function qcopy(q) return shared.qcopy(q) end
local function qzero() return shared.qzero() end
local function qadd(a, b) return shared.qadd(a, b) end
local function qsub(a, b) return shared.qsub(a, b) end
local function qband(a, b) return shared.qband(a, b) end
local function qbor(a, b) return shared.qbor(a, b) end
local function qbxor(a, b) return shared.qbxor(a, b) end
local function qshl(a, n) return shared.qshl(a, n) end
local function qshr(a, n) return shared.qshr(a, n) end
local function qsar(a, n) return shared.qsar(a, n) end
local function newMemory(n) return shared.newMemory(n) end

local AMD64 = {}

local function create(opts)
	opts = opts or {}
	local cpu = {
		mode = "amd64",
		reg = {},
		rip = 0,
		rflags = 0x2,
		mem = newMemory(opts.memSize or 0x2000000),
		memSize = opts.memSize or 0x2000000,
		halt = false,
		syscalls = opts.syscalls or {},
	}

	for i = 0, 15 do
		cpu.reg[i] = qzero()
	end

	local methods = {}

	function methods:setFlag(mask, cond)
		if cond then
			self.rflags = bor(self.rflags, mask)
		else
			self.rflags = band(self.rflags, bit32.bnot(mask))
		end
	end

	function methods:getFlag(mask)
		return band(self.rflags, mask) ~= 0
	end

	function methods:setReg64(i, q)
		self.reg[i] = qnew(q.lo, q.hi)
	end

	function methods:getReg64(i)
		return self.reg[i] or qzero()
	end

	function methods:setReg32(i, v)
		self.reg[i] = qnew(u32(v), 0)
	end

	function methods:getReg32(i)
		return (self.reg[i] and self.reg[i].lo) or 0
	end

	function methods:loadBuffer(buf, addr)
		self.mem:loadBuffer(buf, addr or 0)
	end

	function methods:reset(memSize)
		self.memSize = memSize or self.memSize
		self.mem = newMemory(self.memSize)
		self.halt = false
		self.rip = 0
		self.rflags = 0x2
		for i = 0, 15 do
			self.reg[i] = qzero()
		end
	end

	function methods:fetch8()
		local b = self.mem:read8(self.rip)
		self.rip = u32(self.rip + 1)
		return b
	end

	function methods:fetch32()
		local v = self.mem:read32(self.rip)
		self.rip = u32(self.rip + 4)
		return v
	end

	function methods:fetch64()
		local lo = self:fetch32()
		local hi = self:fetch32()
		return qnew(lo, hi)
	end

	function methods:push64(v)
		self.reg[4] = qsub(self.reg[4], qnew(8, 0))
		self.mem:write64(self.reg[4].lo, v)
	end

	function methods:pop64()
		local v = self.mem:read64(self.reg[4].lo)
		self.reg[4] = qadd(self.reg[4], qnew(8, 0))
		return v
	end

	function methods:dump()
		local out = { ("rip=%08x rflags=%08x"):format(self.rip, self.rflags) }
		for i = 0, 15 do
			local q = self.reg[i] or qzero()
			out[#out + 1] = ("%s=%08x%08x"):format(
				({ "rax","rcx","rdx","rbx","rsp","rbp","rsi","rdi","r8","r9","r10","r11","r12","r13","r14","r15" })[i + 1],
				q.hi, q.lo
			)
		end
		return table.concat(out, "\n")
	end

	local function parity8(x)
		x = band(x, 0xFF)
		local p = 0
		for _ = 1, 8 do
			p = bxor(p, band(x, 1))
			x = rshift(x, 1)
		end
		return p == 0
	end

	local function updateLogic(cpu, result, width)
		local lo = (width == 64) and result.lo or result.lo
		cpu:setFlag(0x40, result.lo == 0 and result.hi == 0)
		cpu:setFlag(0x80, band((width == 64) and result.hi or result.lo, 0x80000000) ~= 0)
		cpu:setFlag(0x1, false)
		cpu:setFlag(0x800, false)
		cpu:setFlag(0x4, parity8(result.lo))
	end

	local function updateAdd(cpu, a, b, r, width)
		cpu:setFlag(0x40, r.lo == 0 and r.hi == 0)
		cpu:setFlag(0x80, band(r.hi, 0x80000000) ~= 0)
		cpu:setFlag(0x1, (r.lo < a.lo) or (r.hi < a.hi and r.lo == a.lo)) -- approximate carry
		cpu:setFlag(0x4, parity8(r.lo))
	end

	local function updateSub(cpu, a, b, r)
		cpu:setFlag(0x40, r.lo == 0 and r.hi == 0)
		cpu:setFlag(0x80, band(r.hi, 0x80000000) ~= 0)
		cpu:setFlag(0x1, a.hi < b.hi or (a.hi == b.hi and a.lo < b.lo))
		cpu:setFlag(0x4, parity8(r.lo))
	end

	local function cond(cpu, cc)
		local zf = band(cpu.rflags, 0x40) ~= 0
		local sf = band(cpu.rflags, 0x80) ~= 0
		local of = band(cpu.rflags, 0x800) ~= 0
		local cf = band(cpu.rflags, 0x1) ~= 0
		if cc == 0 then return of end
		if cc == 1 then return not of end
		if cc == 2 then return cf end
		if cc == 3 then return not cf end
		if cc == 4 then return zf end
		if cc == 5 then return not zf end
		if cc == 6 then return cf or zf end
		if cc == 7 then return not cf and not zf end
		if cc == 8 then return sf end
		if cc == 9 then return not sf end
		if cc == 10 then return of ~= sf end
		if cc == 11 then return of == sf end
		if cc == 12 then return zf or (sf ~= of) end
		if cc == 13 then return (not zf) and (sf == of) end
		if cc == 14 then return zf or (sf ~= of) end
		if cc == 15 then return (not zf) and (sf == of) end
		return false
	end

	function methods:getModRM()
		local b = self:fetch8()
		return bit32.rshift(b, 6), band(bit32.rshift(b, 3), 7), band(b, 7), b
	end

	function methods:readEA(mod, rm, rex_b)
		if mod == 3 then
			return nil, rm + ((rex_b and 8) or 0)
		end
		local disp = 0
		local base, index, scale = nil, nil, 1
		local riprel = false
		if rm == 4 then
			local sib = self:fetch8()
			scale = 2 ^ bit32.rshift(sib, 6)
			index = band(bit32.rshift(sib, 3), 7)
			base = band(sib, 7)
			if index == 4 then index = nil end
			if rex_b and base == 5 then base = 13 end
			if mod == 0 and base == 5 then
				base = nil
				disp = s32(self:fetch32())
			end
		else
			base = rm + ((rex_b and 8) or 0)
			if mod == 0 and rm == 5 then
				riprel = true
				disp = s32(self:fetch32())
			end
		end
		if mod == 1 then
			disp = disp + sext(self:fetch8(), 8)
		elseif mod == 2 then
			disp = disp + s32(self:fetch32())
		end
		local addr = disp
		if riprel then
			addr = addr + self.rip
		end
		if base then addr = addr + self:getReg64(base).lo end
		if index then addr = addr + self:getReg64(index).lo * scale end
		return u32(addr)
	end

	function methods:readOp(mod, rm)
		if mod == 3 then
			return self:getReg64(rm)
		end
		return self.mem:read64(self:readEA(mod, rm))
	end

	function methods:writeOp(mod, rm, value)
		if mod == 3 then
			self:setReg64(rm, value)
			return
		end
		self.mem:write64(self:readEA(mod, rm), value)
	end

	function methods:step()
		if self.halt then return true end
		local start = self.rip

		local op
		local rex_w, rex_r, rex_x, rex_b = false, false, false, false
		local prefix66, prefix67 = false, false

		op = self:fetch8()
		while op == 0x66 or op == 0x67 or op == 0xF0 or op == 0xF2 or op == 0xF3 do
			if op == 0x66 then prefix66 = true end
			if op == 0x67 then prefix67 = true end
			op = self:fetch8()
		end

		if op >= 0x40 and op <= 0x4F then
			rex_w = band(op, 0x8) ~= 0
			rex_r = band(op, 0x4) ~= 0
			rex_x = band(op, 0x2) ~= 0
			rex_b = band(op, 0x1) ~= 0
			op = self:fetch8()
		end

		if op == 0x90 then
			-- nop

		elseif op == 0xF4 then
			self.halt = true

		elseif op == 0xC3 then
			local target = self:pop64()
			self.rip = target.lo
			return false

		elseif op == 0xE8 then
			local rel = s32(self:fetch32())
			self:push64(qnew(self.rip, 0))
			self.rip = u32(self.rip + rel)
			return false

		elseif op == 0xE9 then
			self.rip = u32(self.rip + s32(self:fetch32()))
			return false

		elseif op == 0xEB then
			self.rip = u32(self.rip + sext(self:fetch8(), 8))
			return false

		elseif op >= 0x50 and op <= 0x57 then
			local idx = op - 0x50
			if rex_b then idx = idx + 8 end
			self:push64(self:getReg64(idx))

		elseif op >= 0x58 and op <= 0x5F then
			local idx = op - 0x58
			if rex_b then idx = idx + 8 end
			self:setReg64(idx, self:pop64())

		elseif op >= 0xB8 and op <= 0xBF then
			local idx = op - 0xB8
			if rex_b then idx = idx + 8 end
			if rex_w then
				self:setReg64(idx, self:fetch64())
			else
				self:setReg32(idx, self:fetch32())
			end

		elseif op == 0x0F then
			local op2 = self:fetch8()
			if op2 >= 0x80 and op2 <= 0x8F then
				local rel = s32(self:fetch32())
				if cond(self, op2 - 0x80) then
					self.rip = u32(self.rip + rel)
				end
				return false
			elseif op2 == 0x05 then
				local num = self:getReg64(0).lo
				local handler = self.syscalls[num]
				if handler then
					local ret = handler(
						self,
						self:getReg64(0),
						self:getReg64(1),
						self:getReg64(2),
						self:getReg64(3),
						self:getReg64(4),
						self:getReg64(5),
						self:getReg64(6)
					)
					if type(ret) == "number" then
						self:setReg64(0, qnew(ret, 0))
					elseif type(ret) == "table" and ret.lo then
						self:setReg64(0, ret)
					end
				else
					self:setReg64(0, qnew(0xFFFFFFFF, 0xFFFFFFFF))
				end
			else
				error(("unhandled 0F opcode %02X at %08X"):format(op2, start))
			end

		elseif op == 0xFF or op == 0x89 or op == 0x8B or op == 0x8D or op == 0x01 or op == 0x03 or op == 0x29 or op == 0x2B or op == 0x21 or op == 0x23 or op == 0x31 or op == 0x33 or op == 0x39 or op == 0x3B or op == 0x85 or op == 0x87 then
			local mod, reg, rm = self:getModRM()
			if rex_r then reg = reg + 8 end
			if rex_b then rm = rm + 8 end

			local function readOperand()
				if mod == 3 then
					return self:getReg64(rm)
				end
				return self.mem:read64(self:readEA(mod, rm, rex_b))
			end

			local function writeOperand(v)
				if mod == 3 then
					self:setReg64(rm, v)
				else
					self.mem:write64(self:readEA(mod, rm, rex_b), v)
				end
			end

			if op == 0x8D then
				self:setReg64(reg, qnew(self:readEA(mod, rm, rex_b), 0))
			elseif op == 0x89 then
				writeOperand(self:getReg64(reg))
			elseif op == 0x8B then
				self:setReg64(reg, readOperand())
			else
				local a = readOperand()
				local b = self:getReg64(reg)
				if op == 0x01 then
					writeOperand(qadd(a, b))
				elseif op == 0x03 then
					self:setReg64(reg, qadd(b, a))
				elseif op == 0x29 then
					writeOperand(qsub(a, b))
				elseif op == 0x2B then
					self:setReg64(reg, qsub(b, a))
				elseif op == 0x21 then
					writeOperand(qband(a, b))
				elseif op == 0x23 then
					self:setReg64(reg, qband(b, a))
				elseif op == 0x31 then
					writeOperand(qbxor(a, b))
				elseif op == 0x33 then
					self:setReg64(reg, qbxor(b, a))
				elseif op == 0x39 then
					local r = qsub(b, a)
					self:setFlag(0x40, r.lo == 0 and r.hi == 0)
					self:setFlag(0x1, shared.qslt(b, a))
				elseif op == 0x3B then
					local r = qsub(a, b)
					self:setFlag(0x40, r.lo == 0 and r.hi == 0)
					self:setFlag(0x1, shared.qslt(a, b))
				elseif op == 0x85 then
					local r = qband(a, b)
					self:setFlag(0x40, r.lo == 0 and r.hi == 0)
				elseif op == 0x87 then
					if mod == 3 then
						self.reg[rm], self.reg[reg] = self.reg[reg], self.reg[rm]
					else
						error("xchg memory form not implemented")
					end
				end
			end

		elseif op == 0x81 or op == 0x83 or op == 0xC7 then
			local mod, reg, rm = self:getModRM()
			if rex_b then rm = rm + 8 end
			if rex_r then reg = reg + 8 end
			local imm = (op == 0x83) and qnew(sext(self:fetch8(), 8), 0) or qnew(self:fetch32(), 0)
			if op == 0xC7 then
				imm = qnew(self:fetch32(), 0)
				reg = 0
			end
			local function readOperand()
				if mod == 3 then return self:getReg64(rm) end
				return self.mem:read64(self:readEA(mod, rm, rex_b))
			end
			local function writeOperand(v)
				if mod == 3 then self:setReg64(rm, v) else self.mem:write64(self:readEA(mod, rm, rex_b), v) end
			end

			if reg == 0 then
				writeOperand(qadd(readOperand(), imm))
			elseif reg == 5 then
				writeOperand(qsub(readOperand(), imm))
			elseif reg == 7 then
				local r = qsub(readOperand(), imm)
				self:setFlag(0x40, r.lo == 0 and r.hi == 0)
				self:setFlag(0x1, shared.qslt(readOperand(), imm))
			else
				error(("unhandled group1 reg=%d at %08X"):format(reg, start))
			end

		elseif op == 0xCD then
			local intno = self:fetch8()
			error(("interrupt %02X not implemented"):format(intno))

		else
			error(("unhandled AMD64 opcode %02X at %08X"):format(op, start))
		end

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

	return shared.newReadOnlyApi(cpu, "AMD64")
end

return create