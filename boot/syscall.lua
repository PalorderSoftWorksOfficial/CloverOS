local syscalls = {}

local errno = {
	EPERM = 1,
	ENOENT = 2,
	EINTR = 4,
	EIO = 5,
	ENXIO = 6,
	E2BIG = 7,
	ENOEXEC = 8,
	EBADF = 9,
	EAGAIN = 11,
	EACCES = 13,
	EFAULT = 14,
	ENOTBLK = 15,
	EBUSY = 16,
	EEXIST = 17,
	ENOTDIR = 20,
	EISDIR = 21,
	EINVAL = 22,
	ENOSPC = 28,
	EROFS = 30,
	ENOSYS = 38,
}

local fds = {
	[0] = {
		type = "file",
		handle = io.stdin,
	},
	{
		type = "file",
		handle = io.stdout,
	},
	{
		type = "file",
		handle = io.stderr,
	},
}

function syscalls:mkdirat(dfd, _pathname, mode)
	local path = self.ffistring(self.mem + _pathname)
	if not path:match("^/") then
		if dfd == 4294967196 then -- -100
			path = fs.combine(shell and shell.dir() or "/", path)
		else
			local fd = fds[dfd]
			if not fd then
				return -errno.EBADF
			end
			if fd.type ~= "dir" then
				return -errno.ENOTDIR
			end
			path = fs.combine(fd.path, path)
		end
	end
	local ok, err = pcall(fs.makeDir, path)
	if not ok then
		return -errno.EIO
	end
	return 0
end

function syscalls:unlinkat(dfd, _pathname, flag)
	local path = self.ffistring(self.mem + _pathname)
	if not path:match("^/") then
		if dfd == 4294967196 then -- -100
			path = fs.combine(shell and shell.dir() or "/", path)
		else
			local fd = fds[dfd]
			if not fd then
				return -errno.EBADF
			end
			if fd.type ~= "dir" then
				return -errno.ENOTDIR
			end
			path = fs.combine(fd.path, path)
		end
	end
	if bit32.btest(flag, 0x200) then -- AT_REMOVEDIR
		if fs.isDir(path) then
			if #fs.list(path) == 0 then
				local ok, err = pcall(fs.delete, path)
				if not ok then
					if err:match("Permission denied") or err:match("Access denied") then
						return -errno.EROFS
					else
						return -errno.EIO
					end
				end
				return 0
			else
				return -errno.EEXIST
			end
		else
			return -errno.ENOTDIR
		end
	else
		if fs.isDir(path) then
			return -errno.EISDIR
		else
			local ok, err = pcall(fs.delete, path)
			if not ok then
				if err:match("Permission denied") or err:match("Access denied") then
					return -errno.EROFS
				else
					return -errno.EIO
				end
			end
			return 0
		end
	end
end

function syscalls:renameat(olddfd, _oldname, newdfd, _newname)
	local oldpath = self.ffistring(self.mem + _oldname)
	if not oldpath:match("^/") then
		if olddfd == 4294967196 then -- -100
			oldpath = fs.combine(shell and shell.dir() or "/", oldpath)
		else
			local fd = fds[olddfd]
			if not fd then
				return -errno.EBADF
			end
			if fd.type ~= "dir" then
				return -errno.ENOTDIR
			end
			oldpath = fs.combine(fd.path, oldpath)
		end
	end
	local newpath = self.ffistring(self.mem + _newname)
	if not newpath:match("^/") then
		if newdfd == 4294967196 then -- -100
			newpath = fs.combine(shell and shell.dir() or "/", newpath)
		else
			local fd = fds[newdfd]
			if not fd then
				return -errno.EBADF
			end
			if fd.type ~= "dir" then
				return -errno.ENOTDIR
			end
			newpath = fs.combine(fd.path, newpath)
		end
	end
	local ok, err = pcall(fs.rename, oldpath, newpath)
	if not ok then
		if err:match("Permission denied") or err:match("Access denied") then
			return -errno.EROFS
		else
			return -errno.EIO
		end
	end
	return 0
end

function syscalls:openat(dirfd, _path, flags)
	local path = self.ffistring(self.mem + _path)
	if not path:match("^/") then
		if dirfd == 4294967196 then -- -100
			path = fs.combine(shell and shell.dir() or "/", path)
		else
			local fd = fds[dirfd]
			if not fd then
				return -errno.EBADF
			end
			if fd.type ~= "dir" then
				return -errno.ENOTDIR
			end
			path = fs.combine(fd.path, path)
		end
	end
	print("openat: " .. path)
	if bit32.btest(flags, 65536) then
		if fs.isDir(path) then
			local fd = #fds + 1
			fds[fd] = {
				type = "dir",
				path = fs.combine(path),
				ents = fs.list(path),
				pos = 1,
			}
			return fd
		else
			return fs.exists(path) and -errno.ENOTDIR or -errno.ENOENT
		end
	end
	local mode
	local m = bit32.band(flags, 3)
	if m == 0 then
		mode = "r"
	elseif m == 1 then
		if bit32.btest(flags, 1024) then
			mode = "a"
		else
			mode = "w"
		end
	elseif m == 2 then
		if bit32.btest(flags, 1024) then
			mode = "a+"
		elseif bit32.btest(flags, 64) then
			mode = "w+"
		else
			mode = "r+"
		end
	else
		return -errno.EINVAL
	end
	local file, err = io.open(path, mode)
	if not file then
		if err:match("Access denied") then
			return -errno.EACCES
		elseif m ~= 0 and fs.isReadOnly(path) then
			return -errno.EROFS
		elseif m:match("No such file") then
			return -errno.ENOENT
		elseif m:match("Is a dir") then
			if m == 0 then
				local fd = #fds + 1
				fds[fd] = {
					type = "dir",
					path = fs.combine(path),
					ents = fs.list(path),
					pos = 1,
				}
				return fd
			else
				return -errno.EISDIR
			end
		else
			return -errno.EIO
		end
	end
	local fd = #fds + 1
	fds[fd] = {
		type = "file",
		path = fs.combine(path),
		handle = file,
	}
	return fd
end

function syscalls:close(fd)
	if not fds[fd] then
		return -errno.EBADF
	end
	if fds[fd].type == "file" then
		if not pcall(fds[fd].handle.close, fds[fd].handle) then
			return -errno.EIO
		end
	end
	fds[fd] = nil
	return 0
end

function syscalls:getdents64(fd, _dirp, count)
	--[[
        struct linux_dirent64 {
            ino64_t        d_ino;    /* 64-bit inode number */
            off64_t        d_off;    /* Not an offset; see getdents() */
            unsigned short d_reclen; /* Size of this dirent */
            unsigned char  d_type;   /* File type */
            char           d_name[]; /* Filename (null-terminated) */
        };
    ]]
	local dir = fds[fd]
	if not dir then
		return -errno.EBADF
	end
	if dir.type ~= "dir" then
		return -errno.ENOTDIR
	end
	local s = _dirp
	local e = _dirp + count
	while dir.pos <= #dir.ents and _dirp + #dir.ents[dir.pos] + 20 < e do
		-- ino
		self.mem[_dirp] = dir.pos
		self.mem[_dirp + 1] = 0
		self.mem[_dirp + 2] = 0
		self.mem[_dirp + 3] = 0
		self.mem[_dirp + 4] = 0
		self.mem[_dirp + 5] = 0
		self.mem[_dirp + 6] = 0
		self.mem[_dirp + 7] = 0
		-- off
		self.mem[_dirp + 8] = 0
		self.mem[_dirp + 9] = 0
		self.mem[_dirp + 10] = 0
		self.mem[_dirp + 11] = 0
		self.mem[_dirp + 12] = 0
		self.mem[_dirp + 13] = 0
		self.mem[_dirp + 14] = 0
		self.mem[_dirp + 15] = 0
		-- reclen
		self.mem[_dirp + 16] = bit32.band(#dir.ents[dir.pos] + 20, 0xFF)
		self.mem[_dirp + 17] = bit32.band(bit32.rshift(#dir.ents[dir.pos] + 20, 8), 0xFF)
		-- type
		self.mem[_dirp + 18] = fs.isDir(fs.combine(dir.path, dir.ents[dir.pos])) and 4 or 8
		-- name
		self.fficopy(self.mem + _dirp + 19, dir.ents[dir.pos])
		self.mem[_dirp + #dir.ents[dir.pos] + 19] = 0
		_dirp = _dirp + #dir.ents[dir.pos] + 20
		dir.pos = dir.pos + 1
	end
	return _dirp - s
end

function syscalls:lseek(fd, offset_high, offset_low, _result, whence)
	local file = fds[fd]
	if not file then
		return -errno.EBADF
	end
	if file.type ~= "file" then
		return -errno.EISDIR
	end
	local offset = offset_high * 0x100000000 + offset_low
	if whence == 0 then
		whence = "set"
	elseif whence == 1 then
		whence = "cur"
	elseif whence == 2 then
		whence = "end"
	else
		return -errno.EINVAL
	end
	local ok, pos = pcall(file.handle.seek, file.handle, offset, whence)
	if not ok then
		return -errno.EIO
	end
	self.mem[_result] = bit32.extract(pos, 0, 8)
	self.mem[_result + 1] = bit32.extract(pos, 8, 8)
	self.mem[_result + 2] = bit32.extract(pos, 16, 8)
	self.mem[_result + 3] = bit32.extract(pos, 24, 8)
	return 0
end

function syscalls:read(fd, _buf, count)
	local file = fds[fd]
	if not file then
		return -errno.EBADF
	end
	if file.type ~= "file" then
		return -errno.EISDIR
	end
	if not file.handle.read then
		return -errno.EINVAL
	end
	local ok, data = pcall(file.handle.read, file.handle, count)
	if not ok then
		return -errno.EIO
	end
	if data == nil then
		return 0
	end
	self.fficopy(self.mem + _buf, data)
	return #data
end

function syscalls:write(fd, _buf, count)
	local file = fds[fd]
	if not file then
		return -errno.EBADF
	end
	if file.type ~= "file" then
		return -errno.EISDIR
	end
	if not file.handle.write then
		return -errno.EINVAL
	end
	local data = self.ffistring(self.mem + _buf, count)
	local ok = pcall(file.handle.write, file.handle, data)
	if not ok then
		return -errno.EIO
	end
	return count
end

function syscalls:fsync(fd)
	local file = fds[fd]
	if not file then
		return -errno.EBADF
	end
	if file.type ~= "file" then
		return -errno.EISDIR
	end
	if not file.handle.flush then
		return -errno.EINVAL
	end
	file.handle:flush()
	return 0
end

function syscalls:statx(dirfd, _pathname, flags, mask, _statxbuf)
	local path = self.ffistring(self.mem + _pathname)
	if path == "" and bit32.btest(flags, 0x1000) then -- AT_EMPTY_PATH
		local fd = fds[dirfd]
		if not fd then
			return -errno.EBADF
		end
		path = fd.path
	elseif not path:match("^/") then
		if dirfd == 4294967196 then -- -100 (AT_FDCWD)
			path = fs.combine(shell and shell.dir() or "/", path)
		else
			local fd = fds[dirfd]
			if not fd then
				return -errno.EBADF
			end
			if fd.type ~= "dir" then
				return -errno.ENOTDIR
			end
			path = fs.combine(fd.path, path)
		end
	end
	local attr = fs.attributes(path)
	if not attr then
		return -errno.ENOENT
	end
	-- mask
	self.mem[_statxbuf + 0] = 0xFF
	self.mem[_statxbuf + 1] = 0xFF
	self.mem[_statxbuf + 2] = 0xFF
	self.mem[_statxbuf + 3] = 0xFF
	-- blksize
	self.mem[_statxbuf + 4] = 1
	self.mem[_statxbuf + 5] = 0
	self.mem[_statxbuf + 6] = 0
	self.mem[_statxbuf + 7] = 0
	-- attributes
	self.mem[_statxbuf + 8] = attr.isReadOnly and 0x10 or 0
	for i = 9, 27 do
		self.mem[_statxbuf + i] = 0
	end -- nlink, uid, gid
	-- mode
	self.mem[_statxbuf + 28] = 0xFF
	self.mem[_statxbuf + 29] = attr.isDir and 0x41 or 0x81
	-- alignment
	self.mem[_statxbuf + 30] = 0
	self.mem[_statxbuf + 31] = 0
	-- ino
	for i = 32, 39 do
		self.mem[_statxbuf + i] = 0
	end
	-- size
	self.mem[_statxbuf + 40] = bit32.band(attr.size, 0xFF)
	self.mem[_statxbuf + 41] = bit32.band(bit32.rshift(attr.size, 8), 0xFF)
	self.mem[_statxbuf + 42] = bit32.band(bit32.rshift(attr.size, 16), 0xFF)
	self.mem[_statxbuf + 43] = bit32.band(bit32.rshift(attr.size, 24), 0xFF)
	self.mem[_statxbuf + 44] = 0
	self.mem[_statxbuf + 45] = 0
	self.mem[_statxbuf + 46] = 0
	self.mem[_statxbuf + 47] = 0
	-- blocks
	local blocks = math.ceil(attr.size / 512)
	self.mem[_statxbuf + 48] = bit32.band(blocks, 0xFF)
	self.mem[_statxbuf + 49] = bit32.band(bit32.rshift(blocks, 8), 0xFF)
	self.mem[_statxbuf + 50] = bit32.band(bit32.rshift(blocks, 16), 0xFF)
	self.mem[_statxbuf + 51] = bit32.band(bit32.rshift(blocks, 24), 0xFF)
	self.mem[_statxbuf + 52] = 0
	self.mem[_statxbuf + 53] = 0
	self.mem[_statxbuf + 54] = 0
	self.mem[_statxbuf + 55] = 0
	-- attributes_mask
	self.mem[_statxbuf + 56] = 0x10
	for i = 57, 79 do
		self.mem[_statxbuf + i] = 0
	end
	-- btime
	local bsec, bnsec = math.floor(attr.created / 1000), (attr.created % 1000) * 1000000
	self.mem[_statxbuf + 80] = bsec % 0x100
	self.mem[_statxbuf + 81] = math.floor(bsec / 0x100) % 0x100
	self.mem[_statxbuf + 82] = math.floor(bsec / 0x10000) % 0x100
	self.mem[_statxbuf + 83] = math.floor(bsec / 0x1000000) % 0x100
	self.mem[_statxbuf + 84] = math.floor(bsec / 0x100000000) % 0x100
	self.mem[_statxbuf + 85] = math.floor(bsec / 0x10000000000) % 0x100
	self.mem[_statxbuf + 86] = math.floor(bsec / 0x1000000000000) % 0x100
	self.mem[_statxbuf + 87] = 0
	self.mem[_statxbuf + 88] = bit32.extract(bnsec, 0, 8)
	self.mem[_statxbuf + 89] = bit32.extract(bnsec, 8, 8)
	self.mem[_statxbuf + 90] = bit32.extract(bnsec, 16, 8)
	self.mem[_statxbuf + 91] = bit32.extract(bnsec, 24, 8)
	for i = 92, 111 do
		self.mem[_statxbuf + i] = 0
	end
	-- mtime
	local msec, mnsec = math.floor(attr.modified / 1000), (attr.modified % 1000) * 1000000
	self.mem[_statxbuf + 112] = msec % 0x100
	self.mem[_statxbuf + 113] = math.floor(msec / 0x100) % 0x100
	self.mem[_statxbuf + 114] = math.floor(msec / 0x10000) % 0x100
	self.mem[_statxbuf + 115] = math.floor(msec / 0x1000000) % 0x100
	self.mem[_statxbuf + 116] = math.floor(msec / 0x100000000) % 0x100
	self.mem[_statxbuf + 117] = math.floor(msec / 0x10000000000) % 0x100
	self.mem[_statxbuf + 118] = math.floor(msec / 0x1000000000000) % 0x100
	self.mem[_statxbuf + 119] = 0
	self.mem[_statxbuf + 120] = bit32.extract(mnsec, 0, 8)
	self.mem[_statxbuf + 121] = bit32.extract(mnsec, 8, 8)
	self.mem[_statxbuf + 122] = bit32.extract(mnsec, 16, 8)
	self.mem[_statxbuf + 123] = bit32.extract(mnsec, 24, 8)
	self.mem[_statxbuf + 124] = 0
	self.mem[_statxbuf + 125] = 0
	self.mem[_statxbuf + 126] = 0
	self.mem[_statxbuf + 127] = 0
	return 0
end

function syscalls:brk(brk)
	if not self.sysdata.brk then
		self.sysdata.brk = self.endAddr
	end
	local old = self.sysdata.brk
	self.sysdata.brk = math.min(brk, 0x1FF0000)
	return old
end

function syscalls:mmap2(addr, length, prot, flags, fd, pgoffset)
	if not self.sysdata.mmap then
		self.sysdata.mmap = { base = self.endAddr, mapped = { [0x1FFE] = true, [0x1FFF] = true, [0x2000] = true } }
		for a = 0, self.endAddr, 4096 do
			self.sysdata.mmap.mapped[a / 4096] = true
		end
	end
	if addr == 0 then
		addr = self.sysdata.mmap.base
	end
	addr = math.ceil(addr / 4096) * 4096
	while self.sysdata.mmap.mapped[addr / 4096] do
		addr = addr + 4096
	end
	for a = addr, addr + length - 1, 4096 do
		self.sysdata.mmap.mapped[a / 4096] = true
	end
	-- TODO: fd
	return addr
end

function syscalls:prlimit64(pid, resource, _new_rlim, _old_rlim)
	if resource == 1 then
		return fs.getCapacity("/")
	elseif resource == 6 then
		return 1
	elseif resource == 7 then
		return 128
	elseif resource == 9 then
		return 0x2000000
	elseif resource == 13 then
		return 39
	else
		return 0x7FFFFFFF
	end
end

function syscalls:getrandom(_buf, len, flags)
	for i = 0, len - 1 do
		self.mem[_buf + i] = math.random(0, 255)
	end
	return len
end

function syscalls:futex(_uaddr, futex_op, val, _timeout, _uaddr2, val3)
	print("futex", futex_op, self.mem32[_uaddr / 4], val)
	if self.mem32[_uaddr / 4] ~= val then
		return -errno.EAGAIN
	end
	return 0
end

local lua52 = require("lua52")
function syscalls:lua52(opt, ...)
	if not lua52[opt] then
		error("Unimplemented Lua call " .. opt)
	end
	--for k, v in pairs(lua52) do if k ~= opt and v == lua52[opt] then print(k) end end
	return lua52[opt](self, ...)
end

local syscall_list = {
	[34] = "mkdirat",
	[35] = "unlinkat",
	[38] = "renameat",
	[56] = "openat",
	[57] = "close",
	[61] = "getdents64",
	[62] = "lseek",
	[63] = "read",
	[64] = "write",
	[82] = "fsync",
	[83] = "fsync",
	[214] = "brk",
	[222] = "mmap2",
	[261] = "prlimit64",
	[291] = "statx",
	[278] = "getrandom",
	[422] = "futex",
	[0x1b52] = "lua52",
}
for k, v in pairs(syscall_list) do
	syscalls[k] = syscalls[v]
end

return syscalls
