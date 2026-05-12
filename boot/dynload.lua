local readelf = require("elf")
local function symbol(modules, baseAddress, sym)
	if not sym then
		return 0
	elseif sym.shndx == 0 or sym.value == 0 then -- UNDEF
		local name = sym.name
		--print(name)
		for _, m in pairs(modules) do
			for k, v in pairs(m.symbols) do
				if k == name or k:match("^([^@]+)@@") == name or k:gsub("@", "@@") == name then
					--print(k)
					return v
				end
			end
		end
		if sym.binding == "WEAK" then
			return 0
		end
		error("unresolved symbol '" .. name .. "'")
	else
		return baseAddress + sym.value
	end
end

local function dynload(self, modules, name, baseAddress)
	baseAddress = baseAddress or 0
	local file = assert(io.open(shell.resolve and shell.resolve(name) or name, "rb"))
	local data = file:read("*a")
	file:close()
	local elf = readelf(data)
	if elf.machine ~= 0xF3 then
		error("Incompatible binary")
	end
	if not elf.dynamic then
		error("No dynamic section")
	end
	-- 1. Copy segments to memory
	local endAddr = baseAddress
	local tlsAddr
	for _, v in ipairs(elf.segments) do
		if v.type == "LOAD" then
			self.fficopy(self.mem + baseAddress + v.address, v.data)
			endAddr = math.max(endAddr, baseAddress + v.address + #v.data)
			if v.type == "TLS" then
				tlsAddr = baseAddress + v.address
			end
		end
	end
	for _, v in ipairs(elf.segments) do
		if v.type == "TLS" then
			self.fficopy(self.mem + endAddr, v.data)
			tlsAddr = endAddr
			endAddr = endAddr + #v.data
		end
	end
	local tlsOffset = 0
	if tlsAddr then
		tlsOffset = self.mem32[0x800200] + 1
		self.mem32[0x800200] = tlsOffset
		self.mem32[0x800200 + tlsOffset] = tlsAddr
		tlsOffset = tlsOffset * 4
	end
	-- 2. Load dependencies
	for _, v in ipairs(elf.dynamic.needed) do
		if not modules[v] then
			endAddr = dynload(self, modules, v, math.ceil(endAddr / 0x1000) * 0x1000)
		end
	end
	-- 3. Process relocations
	for _, v in pairs(elf.sections) do
		if v.relocations then
			for _, r in ipairs(v.relocations) do
				local addr = baseAddress + r.offset
				--print(name, r.type, r.offset, r.addend, r.symbol and r.symbol.name)
				if r.type == 1 then -- R_RISCV_32
					self.mem32[addr / 4] = symbol(modules, baseAddress, r.symbol) + r.addend
				elseif r.type == 3 then -- R_RISCV_RELATIVE
					self.mem32[addr / 4] = baseAddress + r.addend
				elseif r.type == 5 then -- R_RISCV_JUMP_SLOT
					self.mem32[addr / 4] = symbol(modules, baseAddress, r.symbol)
					--print(("%08x %08x"):format(addr, self.mem32[addr / 4]))
				elseif r.type == 6 then -- R_RISCV_TLS_DTPMOD32
					self.mem32[addr / 4] = tlsOffset
				elseif r.type == 8 then -- R_RISCV_TLS_DTPREL32
					self.mem32[addr / 4] = symbol(modules, baseAddress, r.symbol) + r.addend - 0x800
				elseif r.type == 10 then -- R_RISCV_TLS_TPREL32
					local a = symbol(modules, baseAddress, r.symbol) + r.addend + (tlsAddr - 0x2000800)
					if a < 0 then
						a = a + 0x100000000
					end
					--print(("%s %08x %04x -> %08x"):format(name, addr, r.addend, (a + 0x2000800) % 0x100000000)) sleep(1)
					self.mem32[addr / 4] = a
				--elseif r.type == 12 then -- R_RISCV_TLSDESC
				else
					error("Unimplemented relocation type " .. r.type)
				end
			end
		end
	end
	-- 3.5. Copy TLS data again, now with relocations
	for _, v in ipairs(elf.segments) do
		if v.type == "TLS" then
			self.fficopy(self.mem + tlsAddr, self.mem + baseAddress + v.address, #v.data)
		end
	end
	-- 4. Run array initializers
	local init, initsz
	for _, v in ipairs(elf.dynamic) do
		if v.type == "INIT_ARRAY" then
			init = v.value
		elseif v.type == "INIT_ARRAYSZ" then
			initsz = v.value
		end
	end
	if init and initsz then
		for addr = baseAddress + init, baseAddress + init + initsz - 1, 4 do
			self:call(self.mem32[addr / 4])
		end
	end
	-- 5. Create exported symbol table and return
	local symbols = {}
	for _, v in ipairs(elf.sections[".dynsym"].symbols) do
		if v.binding ~= "LOCAL" and v.shndx ~= 0 and v.value ~= 0 then
			symbols[v.name] = baseAddress + v.value
		end
	end
	modules[name] = {
		baseAddress = baseAddress,
		size = endAddr - baseAddress,
		elf = elf,
		symbols = symbols,
	}
	return endAddr
end

return dynload
