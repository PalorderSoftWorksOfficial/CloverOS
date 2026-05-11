local struct = require("struct")

local types = {}
struct(
	[[
    typedef struct {
        char ei_magic[4];
        uint8_t ei_class;
        uint8_t ei_data;
        uint8_t ei_version;
        uint8_t ei_osabi;
        uint8_t ei_abiversion;
        uint8_t ei_pad[7];
        uint16_t e_type;
        uint16_t e_machine;
        uint32_t e_version;
        uint32_t e_entry;
        uint32_t e_phoff;
        uint32_t e_shoff;
        uint32_t e_flags;
        uint16_t e_ehsize;
        uint16_t e_phentsize;
        uint16_t e_phnum;
        uint16_t e_shentsize;
        uint16_t e_shnum;
        uint16_t e_shstrndx;
    } elf_file_header_t;
    
    typedef struct {
        uint32_t p_type;
        uint32_t p_offset;
        uint32_t p_vaddr;
        uint32_t p_paddr;
        uint32_t p_filesz;
        uint32_t p_memsz;
        uint32_t p_flags;
        uint32_t p_align;
    } elf_program_header_t;
    
        typedef struct {
            uint32_t sh_name;
            uint32_t sh_type;
            uint32_t sh_flags;
            uint32_t sh_addr;
            uint32_t sh_offset;
            uint32_t sh_size;
            uint32_t sh_link;
            uint32_t sh_info;
            uint32_t sh_addralign;
            uint32_t sh_entsize;
        } elf_section_header_t;
    
    typedef struct {
        uint32_t st_name;
        uint32_t st_value;
        uint32_t st_size;
        uint8_t st_info;
        uint8_t st_other;
        uint16_t st_shndx;
    } elf_symbol_table_entry_t;
    
    typedef struct {
        uint32_t r_offset;
        uint32_t r_info;
    } elf_relocation_t;
    
    typedef struct {
        uint32_t r_offset;
        uint32_t r_info;
        int32_t r_addend;
    } elf_relocation_addend_t;
]],
	types
)

local objectTypes = {
	[0] = "NONE",
	"REL",
	"EXEC",
	"DYN",
	"CORE",
}

local phTypes = {
	[0] = "NULL",
	"LOAD",
	"DYNAMIC",
	"INTERP",
	"NOTE",
	"SHLIB",
	"PHDR",
	"TLS",
	[0x6474e550] = "GNU_EH_FRAME",
	[0x6474e551] = "GNU_STACK",
	[0x6474e552] = "GNU_RELRO",
	[0x70000003] = "RISCV_ATTRIBUTES",
}

local shTypes = {
	[0] = "NULL",
	"PROGBITS",
	"SYMTAB",
	"STRTAB",
	"RELA",
	"HASH",
	"DYNAMIC",
	"NOTE",
	"NOBITS",
	"REL",
	"SHLIB",
	"DYNSYM",
	nil,
	nil,
	"INIT_ARRAY",
	"FINI_ARRAY",
	"PREINIT_ARRAY",
	"GROUP",
	"SYMTAB_SHNDX",
	[0x70000003] = "RISCV_ATTRIBUTES",
}

local bindTypes = {
	[0] = "LOCAL",
	"GLOBAL",
	"WEAK",
}

local symbolTypes = {
	[0] = "NOTYPE",
	"OBJECT",
	"FUNC",
	"SECTION",
	"FILE",
}

local dynamicTypes = {
	[0] = "NULL",
	"NEEDED",
	"PLTRELSZ",
	"PLTGOT",
	"HASH",
	"STRTAB",
	"SYMTAB",
	"RELA",
	"RELASZ",
	"RELAENT",
	"STRSZ",
	"SYMENT",
	"INIT",
	"FINI",
	"SONAME",
	"RPATH",
	"SYMBOLIC",
	"REL",
	"RELSZ",
	"RELENT",
	"PLTREL",
	"DEBUG",
	"TEXTREL",
	"JMPREL",
	"BIND_NOW",
	"INIT_ARRAY",
	"FINI_ARRAY",
	"INIT_ARRAYSZ",
	"FINI_ARRAYSZ",
	"RUNPATH",
	"FLAGS",
	"ENCODING",
	"PREINIT_ARRAY",
	"PREINIT_ARRAYSZ",
	"SYMTAB_SHNDX",
	[0x70000001] = "RISCV_VARIANT_CC",
}

local function readelf(data)
	local fileHeader = types.elf_file_header_t(data)
	if
		fileHeader.ei_magic ~= "\x7FELF"
		or fileHeader.ei_class ~= 1
		or fileHeader.ei_data ~= 1
		or fileHeader.ei_version ~= 1
		or fileHeader.e_version ~= 1
	then
		error("Not a supported ELF file", 2)
	end
	local elf = {
		is64Bit = false,
		littleEndian = true,
		osABI = fileHeader.ei_osabi,
		abiVersion = fileHeader.ei_abiversion,
		type = objectTypes[fileHeader.e_type] or fileHeader.e_type,
		machine = fileHeader.e_machine,
		entrypoint = fileHeader.e_entry,
		flags = fileHeader.e_flags,
		segments = {},
		sections = {},
	}
	local pos = fileHeader.e_phoff + 1
	for i = 1, fileHeader.e_phnum do
		local programHeader = types.elf_program_header_t(data, pos)
		pos = pos + fileHeader.e_phentsize
		elf.segments[i] = {
			type = phTypes[programHeader.p_type] or programHeader.p_type,
			address = programHeader.p_vaddr,
			physicalAddress = programHeader.p_paddr,
			flags = programHeader.p_flags,
			alignment = programHeader.p_align,
			data = data:sub(programHeader.p_offset + 1, programHeader.p_offset + programHeader.p_filesz),
		}
		if programHeader.p_memsz > programHeader.p_filesz then
			elf.segments[i].data = elf.segments[i].data .. ("\0"):rep(programHeader.p_memsz - programHeader.p_filesz)
		end
	end
	local sectionList = {}
	pos = fileHeader.e_shoff + 1
	for i = 1, fileHeader.e_shnum do
		local sectionHeader = types.elf_section_header_t(data, pos)
		pos = pos + fileHeader.e_shentsize
		local section = {
			nameidx = sectionHeader.sh_name,
			type = shTypes[sectionHeader.sh_type] or sectionHeader.sh_type,
			flags = sectionHeader.sh_flags,
			address = sectionHeader.sh_addr,
			link = sectionHeader.sh_link,
			info = sectionHeader.sh_info,
			align = sectionHeader.sh_addralign,
			data = sectionHeader.sh_type == 8 and ("\0"):rep(sectionHeader.sh_size)
				or data:sub(sectionHeader.sh_offset + 1, sectionHeader.sh_offset + sectionHeader.sh_size),
		}
		if sectionHeader.sh_type == 3 then -- STRTAB
			function section.string(index)
				return section.data:match("^[^%z]*", index + 1)
			end
		elseif sectionHeader.sh_type == 2 or sectionHeader.sh_type == 11 then -- SYMTAB
			section.symbols = {}
			local p, j = 1, 1
			while p + 15 <= #section.data do
				local symbolData
				symbolData, p = types.elf_symbol_table_entry_t(section.data, p)
				section.symbols[j] = {
					nameidx = symbolData.st_name,
					value = symbolData.st_value,
					size = symbolData.st_size,
					binding = bindTypes[bit32.extract(symbolData.st_info, 4, 4)]
						or bit32.extract(symbolData.st_info, 4, 4),
					type = symbolTypes[bit32.band(symbolData.st_info, 0x0F)] or bit32.band(symbolData.st_info, 0x0F),
					other = symbolData.st_other,
					shndx = symbolData.st_shndx,
				}
				j = j + 1
			end
		elseif sectionHeader.sh_type == 4 or sectionHeader.sh_type == 9 then -- REL/RELA
			section.relocations = {}
			local t = sectionHeader.sh_type == 9 and types.elf_relocation_t or types.elf_relocation_addend_t
			local p, j = 1, 1
			while p < #section.data do
				local relData
				relData, p = t(section.data, p)
				section.relocations[j] = {
					offset = relData.r_offset,
					type = bit32.band(relData.r_info, 0xFF),
					symbolidx = bit32.rshift(relData.r_info, 8),
					addend = relData.r_addend,
				}
				j = j + 1
			end
		elseif sectionHeader.sh_type == 6 then -- DYNAMIC
			section.dynamic = {
				needed = {},
			}
			local p = 1
			repeat
				local tag, value
				tag, value, p = ("<i4I4"):unpack(section.data, p)
				section.dynamic[#section.dynamic + 1] = { type = dynamicTypes[tag] or tag, value = value }
			until tag == 0
			elf.dynamic = section.dynamic
		end
		sectionList[i] = section
	end
	local getstr_name = sectionList[fileHeader.e_shstrndx + 1].string
	for i, v in ipairs(sectionList) do
		v.name, v.nameidx = getstr_name(v.nameidx), nil
		elf.sections[v.name] = v
		if v.type == "SYMTAB" or v.type == "DYNSYM" then
			local getstr_sym = sectionList[v.link + 1].string
			for _, s in ipairs(v.symbols) do
				s.name, s.nameidx = getstr_sym(s.nameidx), nil
				s.section, s.shndx = sectionList[s.shndx + 1], nil
			end
		elseif v.type == "DYNAMIC" then
			local getstr_dyn = sectionList[v.link + 1].string
			for _, d in ipairs(v.dynamic) do
				if d.type == "NEEDED" then
					v.dynamic.needed[#v.dynamic.needed + 1] = getstr_dyn(d.value)
				end
			end
		elseif v.relocations then
			v.section = sectionList[v.info + 1]
			local symtab = sectionList[v.link + 1].symbols
			for _, r in ipairs(v.relocations) do
				r.symbol, r.symbolidx = r.symbolidx > 0 and symtab[r.symbolidx + 1] or nil, nil
			end
		end
	end
	return elf
end

return readelf
