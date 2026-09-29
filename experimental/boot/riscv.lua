-- Licensed under GPLv2
-- Standalone RV32 emulator core with buffer-backed memory.
-- No dynload, no luastate, no external module loader.

local bit32 = bit32
if not bit32 then
	error("bit32 is required")
end

local band = bit32.band
local bor = bit32.bor
local bxor = bit32.bxor
local lshift = bit32.lshift
local rshift = bit32.rshift
local extract = bit32.extract

local function u32(x)
	return band(x, 0xFFFFFFFF)
end

local function s32(x)
	x = u32(x)
	if x >= 0x80000000 then
		return x - 0x100000000
	end
	return x
end

local function sext(value, bits)
	value = band(value, (bits == 32) and 0xFFFFFFFF or (2 ^ bits - 1))
	if bits == 32 then
		return s32(value)
	end
	local sign = 2 ^ (bits - 1)
	if band(value, sign) ~= 0 then
		return value - 2 ^ bits
	end
	return value
end

local function decodeR(inst)
	return {
		inst = inst,
		opcode = extract(inst, 0, 7),
		rd = extract(inst, 7, 5),
		funct3 = extract(inst, 12, 3),
		rs1 = extract(inst, 15, 5),
		rs2 = extract(inst, 20, 5),
		funct7 = extract(inst, 25, 7),
	}
end

local function decodeI(inst)
	local imm = extract(inst, 20, 12)
	return {
		inst = inst,
		opcode = extract(inst, 0, 7),
		rd = extract(inst, 7, 5),
		funct3 = extract(inst, 12, 3),
		rs1 = extract(inst, 15, 5),
		imm = imm,
		simm = sext(imm, 12),
	}
end

local function decodeS(inst)
	local imm = bor(
		extract(inst, 7, 5),
		lshift(extract(inst, 25, 7), 5)
	)
	return {
		inst = inst,
		opcode = extract(inst, 0, 7),
		funct3 = extract(inst, 12, 3),
		rs1 = extract(inst, 15, 5),
		rs2 = extract(inst, 20, 5),
		imm = imm,
		simm = sext(imm, 12),
	}
end

local function decodeB(inst)
	local imm = bor(
		lshift(extract(inst, 7, 1), 11),
		lshift(extract(inst, 8, 4), 1),
		lshift(extract(inst, 25, 6), 5),
		lshift(extract(inst, 31, 1), 12)
	)
	return {
		inst = inst,
		opcode = extract(inst, 0, 7),
		funct3 = extract(inst, 12, 3),
		rs1 = extract(inst, 15, 5),
		rs2 = extract(inst, 20, 5),
		imm = imm,
		simm = sext(imm, 13),
	}
end

local function decodeU(inst)
	return {
		inst = inst,
		opcode = extract(inst, 0, 7),
		rd = extract(inst, 7, 5),
		imm = band(inst, 0xFFFFF000),
		simm = sext(band(inst, 0xFFFFF000), 32),
	}
end

local function decodeJ(inst)
	local imm = bor(
		lshift(extract(inst, 12, 8), 12),
		lshift(extract(inst, 20, 1), 11),
		lshift(extract(inst, 21, 10), 1),
		lshift(extract(inst, 31, 1), 20)
	)
	return {
		inst = inst,
		opcode = extract(inst, 0, 7),
		rd = extract(inst, 7, 5),
		imm = imm,
		simm = sext(imm, 21),
	}
end

local opcode_modes = {
	[0x37] = decodeU, -- LUI
	[0x17] = decodeU, -- AUIPC
	[0x6F] = decodeJ, -- JAL
	[0x67] = decodeI, -- JALR
	[0x63] = decodeB, -- branches
	[0x03] = decodeI, -- loads
	[0x23] = decodeS, -- stores
	[0x13] = decodeI, -- imm arith
	[0x33] = decodeR, -- reg arith
	[0x0F] = decodeI, -- fence
	[0x73] = decodeI, -- system
	[0x2F] = decodeR, -- atomics
}

local RISCV = {
	reg = {},
	pc = 0,
	mem = nil,
	memSize = 0,
	syscalls = {},
	halt = false,
	branches = 0,
	branchesLimit = 0,
	atomic_rs = {},
	sysdata = {},
}

for i = 1, 31 do
	RISCV.reg[i] = 0
end

setmetatable(RISCV.reg, {
	__index = function()
		return 0
	end,
	__newindex = function(t, k, v)
		if k == 0 then
			return
		end
		rawset(t, k, u32(v))
	end,
})

function RISCV.newMemory(size)
	local mem = {
		size = size or 0x2010000,
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
		local a0 = self:read8(addr)
		local a1 = self:read8(addr + 1)
		return bor(a0, lshift(a1, 8))
	end

	function mem:write16(addr, val)
		self:write8(addr, band(val, 0xFF))
		self:write8(addr + 1, band(rshift(val, 8), 0xFF))
	end

	function mem:read32(addr)
		local b0 = self:read8(addr)
		local b1 = self:read8(addr + 1)
		local b2 = self:read8(addr + 2)
		local b3 = self:read8(addr + 3)
		return u32(b0 + b1 * 256 + b2 * 65536 + b3 * 16777216)
	end

	function mem:write32(addr, val)
		self:write8(addr, band(val, 0xFF))
		self:write8(addr + 1, band(rshift(val, 8), 0xFF))
		self:write8(addr + 2, band(rshift(val, 16), 0xFF))
		self:write8(addr + 3, band(rshift(val, 24), 0xFF))
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
				local c = self:read8(addr + i)
				out[#out + 1] = string.char(c)
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

function RISCV:reset(memSize)
	for i = 1, 31 do
		self.reg[i] = 0
	end
	self.pc = 0
	self.memSize = memSize or 0x2010000
	self.mem = RISCV.newMemory(self.memSize)
	self.halt = false
	self.branches = 0
	self.branchesLimit = 0
	self.atomic_rs = {}
	self.sysdata = {}
end

function RISCV:loadBuffer(buf, addr)
	if not self.mem then
		self.mem = RISCV.newMemory(self.memSize > 0 and self.memSize or 0x2010000)
	end
	self.mem:loadBuffer(buf, addr or 0)
end

function RISCV:read8(addr)
	return self.mem:read8(addr)
end

function RISCV:read16(addr)
	return self.mem:read16(addr)
end

function RISCV:read32(addr)
	return self.mem:read32(addr)
end

function RISCV:write8(addr, val)
	self.mem:write8(addr, val)
end

function RISCV:write16(addr, val)
	self.mem:write16(addr, val)
end

function RISCV:write32(addr, val)
	self.mem:write32(addr, val)
end

local function sign32(x)
	return s32(x)
end

local function to_u32(x)
	return u32(x)
end

function RISCV:step()
	if self.halt then
		return true
	end

	local pc = self.pc
	if pc % 4 ~= 0 then
		error(("unaligned PC: %08X"):format(pc))
	end
	if pc < 0 or pc + 4 > self.mem.size then
		error(("pc out of bounds: %08X"):format(pc))
	end

	local inst = self.mem:read32(pc)
	if inst == 0x00100073 or inst == 0xC0001073 then
		self.halt = true
		return true
	end

	local nextpc = pc + 4
	local opcode = band(inst, 0x7F)
	local mode = opcode_modes[opcode]
	if not mode then
		error(("unknown opcode %02X at %08X"):format(opcode, pc))
	end

	inst = mode(inst)
	local rd = inst.rd or 0
	local rs1 = inst.rs1 or 0
	local rs2 = inst.rs2 or 0
	local funct3 = inst.funct3 or 0
	local funct7 = inst.funct7 or 0

	if opcode == 0x37 then
		self.reg[rd] = inst.imm

	elseif opcode == 0x17 then
		self.reg[rd] = to_u32(pc + inst.simm)

	elseif opcode == 0x6F then
		self.reg[rd] = nextpc
		self.pc = to_u32(pc + inst.simm)
		self.reg[0] = 0
		return false

	elseif opcode == 0x67 then
		local target = band(self.reg[rs1] + inst.simm, 0xFFFFFFFE)
		self.reg[rd] = nextpc
		self.pc = to_u32(target)
		self.reg[0] = 0
		return false

	elseif opcode == 0x63 then
		local a = self.reg[rs1]
		local b = self.reg[rs2]
		local take = false

		if funct3 == 0x0 then
			take = a == b -- BEQ
		elseif funct3 == 0x1 then
			take = a ~= b -- BNE
		elseif funct3 == 0x4 then
			take = sign32(a) < sign32(b) -- BLT
		elseif funct3 == 0x5 then
			take = sign32(a) >= sign32(b) -- BGE
		elseif funct3 == 0x6 then
			take = u32(a) < u32(b) -- BLTU
		elseif funct3 == 0x7 then
			take = u32(a) >= u32(b) -- BGEU
		else
			error(("unknown branch funct3 %d at %08X"):format(funct3, pc))
		end

		if take then
			self.pc = to_u32(pc + inst.simm)
		else
			self.pc = nextpc
		end
		self.reg[0] = 0
		return false

	elseif opcode == 0x03 then
		local addr = to_u32(self.reg[rs1] + inst.simm)

		if funct3 == 0x0 then
			local v = self.mem:read8(addr)
			self.reg[rd] = sext(v, 8)
		elseif funct3 == 0x1 then
			local v
			if addr % 2 ~= 0 then
				v = bor(self.mem:read8(addr), lshift(self.mem:read8(addr + 1), 8))
			else
				v = self.mem:read16(addr)
			end
			self.reg[rd] = sext(v, 16)
		elseif funct3 == 0x2 then
			local v
			if addr % 4 ~= 0 then
				v = bor(
					self.mem:read8(addr),
					lshift(self.mem:read8(addr + 1), 8),
					lshift(self.mem:read8(addr + 2), 16),
					lshift(self.mem:read8(addr + 3), 24)
				)
			else
				v = self.mem:read32(addr)
			end
			self.reg[rd] = v
		elseif funct3 == 0x4 then
			self.reg[rd] = self.mem:read8(addr)
		elseif funct3 == 0x5 then
			local v
			if addr % 2 ~= 0 then
				v = bor(self.mem:read8(addr), lshift(self.mem:read8(addr + 1), 8))
			else
				v = self.mem:read16(addr)
			end
			self.reg[rd] = v
		else
			error(("unknown load funct3 %d at %08X"):format(funct3, pc))
		end

	elseif opcode == 0x23 then
		local addr = to_u32(self.reg[rs1] + inst.simm)

		if funct3 == 0x0 then
			self.mem:write8(addr, self.reg[rs2])
		elseif funct3 == 0x1 then
			if addr % 2 ~= 0 then
				self.mem:write8(addr, band(self.reg[rs2], 0xFF))
				self.mem:write8(addr + 1, band(rshift(self.reg[rs2], 8), 0xFF))
			else
				self.mem:write16(addr, self.reg[rs2])
			end
		elseif funct3 == 0x2 then
			if addr % 4 ~= 0 then
				self.mem:write8(addr, band(self.reg[rs2], 0xFF))
				self.mem:write8(addr + 1, band(rshift(self.reg[rs2], 8), 0xFF))
				self.mem:write8(addr + 2, band(rshift(self.reg[rs2], 16), 0xFF))
				self.mem:write8(addr + 3, band(rshift(self.reg[rs2], 24), 0xFF))
			else
				self.mem:write32(addr, self.reg[rs2])
			end
		else
			error(("unknown store funct3 %d at %08X"):format(funct3, pc))
		end

	elseif opcode == 0x13 then
		local rs = self.reg[rs1]

		if funct3 == 0x0 then
			if rs1 == 0 then
				self.reg[rd] = inst.simm
			elseif inst.simm == 0 then
				self.reg[rd] = rs
			else
				self.reg[rd] = to_u32(rs + inst.simm)
			end
		elseif funct3 == 0x2 then
			self.reg[rd] = (sign32(rs) < inst.simm) and 1 or 0
		elseif funct3 == 0x3 then
			local imm = inst.simm
			if imm < 0 then
				imm = imm + 0x100000000
			end
			self.reg[rd] = (u32(rs) < imm) and 1 or 0
		elseif funct3 == 0x4 then
			self.reg[rd] = bxor(rs, inst.simm)
		elseif funct3 == 0x6 then
			self.reg[rd] = bor(rs, inst.simm)
		elseif funct3 == 0x7 then
			self.reg[rd] = band(rs, inst.simm)
		elseif funct3 == 0x1 then
			self.reg[rd] = lshift(rs, band(inst.imm, 0x1F))
		elseif funct3 == 0x5 then
			local shamt = band(inst.imm, 0x1F)
			if band(inst.imm, 0x400) ~= 0 then
				self.reg[rd] = s32(rs) >= 0 and to_u32(math.floor(s32(rs) / 2 ^ shamt)) or to_u32(math.floor((s32(rs) + 0x100000000) / 2 ^ shamt))
				self.reg[rd] = to_u32(bit32.arshift(rs, shamt))
			else
				self.reg[rd] = bit32.rshift(rs, shamt)
			end
		else
			error(("unknown imm funct3 %d at %08X"):format(funct3, pc))
		end

	elseif opcode == 0x33 then
		local a = self.reg[rs1]
		local b = self.reg[rs2]

		if funct3 == 0x0 then
			if band(funct7, 0x20) ~= 0 then
				self.reg[rd] = to_u32(a - b)
			else
				self.reg[rd] = to_u32(a + b)
			end
		elseif funct3 == 0x1 then
			self.reg[rd] = lshift(a, band(b, 0x1F))
		elseif funct3 == 0x2 then
			self.reg[rd] = (sign32(a) < sign32(b)) and 1 or 0
		elseif funct3 == 0x3 then
			self.reg[rd] = (u32(a) < u32(b)) and 1 or 0
		elseif funct3 == 0x4 then
			self.reg[rd] = bxor(a, b)
		elseif funct3 == 0x5 then
			if band(funct7, 0x20) ~= 0 then
				self.reg[rd] = to_u32(bit32.arshift(a, band(b, 0x1F)))
			else
				self.reg[rd] = bit32.rshift(a, band(b, 0x1F))
			end
		elseif funct3 == 0x6 then
			self.reg[rd] = bor(a, b)
		elseif funct3 == 0x7 then
			self.reg[rd] = band(a, b)
		elseif funct7 == 0x01 then
			if funct3 == 0x0 then
				self.reg[rd] = to_u32(s32(a) * s32(b))
			elseif funct3 == 0x1 then
				local ra, rb = s32(a), s32(b)
				local v = math.floor((ra * rb) / 0x100000000)
				if v < 0 then v = v + 0x100000000 end
				self.reg[rd] = to_u32(v)
			elseif funct3 == 0x2 then
				local ra = s32(a)
				local rb = u32(b)
				local v = math.floor((ra * rb) / 0x100000000)
				if v < 0 then v = v + 0x100000000 end
				self.reg[rd] = to_u32(v)
			elseif funct3 == 0x3 then
				self.reg[rd] = math.floor((u32(a) * u32(b)) / 0x100000000)
			elseif funct3 == 0x4 then
				if b == 0 then
					self.reg[rd] = 0xFFFFFFFF
				else
					local ra, rb = s32(a), s32(b)
					local q = ra / rb
					if q < 0 then
						self.reg[rd] = to_u32(math.ceil(q))
					else
						self.reg[rd] = to_u32(math.floor(q))
					end
				end
			elseif funct3 == 0x5 then
				if b == 0 then
					self.reg[rd] = 0xFFFFFFFF
				else
					self.reg[rd] = math.floor(u32(a) / u32(b))
				end
			elseif funct3 == 0x6 then
				if b == 0 then
					self.reg[rd] = u32(a)
				else
					local ra, rb = s32(a), s32(b)
					local v = ra % rb
					if v < 0 then v = v + 0x100000000 end
					self.reg[rd] = to_u32(v)
				end
			elseif funct3 == 0x7 then
				if b == 0 then
					self.reg[rd] = u32(a)
				else
					self.reg[rd] = u32(a) % u32(b)
				end
			else
				error(("unknown M-extension funct3 %d at %08X"):format(funct3, pc))
			end
		else
			error(("unknown R-type funct3 %d at %08X"):format(funct3, pc))
		end

	elseif opcode == 0x0F then
		-- FENCE: no-op

	elseif opcode == 0x73 then
		if inst.funct3 ~= 0 then
			-- CSR not implemented
		else
			if inst.imm == 0 then
				local n = self.syscalls[self.reg[17]]
				if n then
					self.reg[10] = n(self, table.unpack(self.reg, 10, 16))
				else
					self.reg[10] = 0xFFFFFFDA -- -38 ENOSYS
				end
				if self.halt then
					return true
				end
			elseif inst.imm == 0x302 then
				self.pc = self.reg[5]
				self.reg[0] = 0
				return false
			end
		end

	elseif opcode == 0x2F and funct3 == 2 then
		local addr = self.reg[rs1]
		if addr % 4 ~= 0 then
			error("unaligned AMO instruction at " .. string.format("%08X", pc))
		end

		local word = addr / 4
		local old = self.mem:read32(addr)
		local op = rshift(funct7, 2)

		if op == 0x02 then
			-- LR.W
			self.reg[rd] = old
			self.atomic_rs[word] = true

		elseif op == 0x03 then
			-- SC.W
			if self.atomic_rs[word] then
				self.mem:write32(addr, self.reg[rs2])
				self.reg[rd] = 0
			else
				self.reg[rd] = 1
			end
			self.atomic_rs[word] = nil

		elseif op == 0x00 then
			self.reg[rd] = old
			self.mem:write32(addr, to_u32(old + self.reg[rs2]))

		elseif op == 0x01 then
			self.reg[rd] = old
			self.mem:write32(addr, bxor(old, self.reg[rs2]))

		elseif op == 0x04 then
			self.reg[rd] = old
			self.mem:write32(addr, bor(old, self.reg[rs2]))

		elseif op == 0x0C then
			self.reg[rd] = old
			self.mem:write32(addr, band(old, self.reg[rs2]))

		elseif op == 0x10 then
			local a, b = s32(old), s32(self.reg[rs2])
			self.reg[rd] = old
			self.mem:write32(addr, (a < b) and old or self.reg[rs2])

		elseif op == 0x14 then
			local a, b = s32(old), s32(self.reg[rs2])
			self.reg[rd] = old
			self.mem:write32(addr, (a > b) and old or self.reg[rs2])

		elseif op == 0x18 then
			self.reg[rd] = old
			self.mem:write32(addr, (u32(old) < u32(self.reg[rs2])) and old or self.reg[rs2])

		elseif op == 0x1C then
			self.reg[rd] = old
			self.mem:write32(addr, (u32(old) > u32(self.reg[rs2])) and old or self.reg[rs2])

		else
			error(("unknown AMO funct5 %02X at %08X"):format(op, pc))
		end

	else
		error(("unhandled opcode %02X at %08X"):format(opcode, pc))
	end

	self.pc = nextpc
	self.reg[0] = 0
	return false
end

function RISCV:run(cycles)
	cycles = cycles or math.huge
	self.branches = 0
	self.branchesLimit = cycles

	local count = 0
	while not self.halt and count < cycles do
		self:step()
		count = count + 1
	end
end

function RISCV:call(addr, ...)
	local oldra = self.reg[1]
	local oldpc = self.pc
	local olda = {}
	local args = { ... }

	for i = 1, 8 do
		olda[i] = self.reg[9 + i]
		if args[i] ~= nil then
			self.reg[9 + i] = args[i]
		end
	end

	self.reg[1] = oldpc
	self.pc = addr
	while not self.halt and self.pc ~= oldpc do
		self:step()
	end

	local res = self.reg[10]
	self.reg[1] = oldra
	for i = 1, 8 do
		self.reg[9 + i] = olda[i]
	end
	return res
end

function RISCV.dump(cpu)
	local out = {}
	out[#out + 1] = ("pc=%08x"):format(cpu.pc)
	for i = 0, 31 do
		if i % 4 == 0 then
			out[#out + 1] = ""
		end
		out[#out + 1] = ("x%d=%08x "):format(i, cpu.reg[i] or 0)
	end
	return table.concat(out, "\n")
end
return RISCV