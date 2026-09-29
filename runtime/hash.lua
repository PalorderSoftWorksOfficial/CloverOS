-- CloverOS hashing: SHA-256 plus salted password digests.
-- Shared by runtime/users.lua (authentication), runtime/packages.lua
-- (payload checksums) and install.lua (installation manifest).
-- No external dependencies; works on Lua 5.1-5.4.
--
-- Platform note: CC:Tweaked provides a native `hash.sha256` API and is used
-- through it whenever present; CraftOS-PC runs Lua 5.3+ with native bit
-- operators. Interpreters without either (or JS-hosted Lua with signed
-- 32-bit integers) fall back to pure-Lua bit twiddling on 16-bit halves,
-- which every interpreter can do because the values stay below 2^16.
local M = {}

local MOD = 4294967296 -- 2^32
local HALF = 65536 -- 2^16

-- ---------- 32-bit primitives ----------
local bxor32, band32

local function compile(expr)
	local ok, fn = pcall(load, expr)
	if ok and type(fn) == "function" then
		return fn
	end
	return nil
end

if type(bit32) == "table" and type(bit32.bxor) == "function" then
	bxor32 = bit32.bxor
	band32 = bit32.band
else
	local bx = compile("local a, b = ... return a ~ b")
	local ba = compile("local a, b = ... return a & b")
	-- some interpreters (e.g. JS-hosted Lua with signed 32-bit integers)
	-- cannot bitwise-operate on values at or above 2^31; probe with an
	-- integral FLOAT in that range, exactly like the SHA state produces
	local big = 2147483647.0 + 2.0
	local probe = bx and ba and pcall(bx, big, 1) and pcall(ba, big, 1)
	if probe then
		bxor32, band32 = bx, ba
	else
		-- Decompose every 32-bit word into two 16-bit halves. A native
		-- `~`/`&` on 16-bit values is always representable, so the slow
		-- per-bit path is only needed when the interpreter has no bitwise
		-- operators at all (plain Lua 5.1).
		local bxor16, band16
		if bx and ba then
			bxor16, band16 = bx, ba
		else
			local function bitOf(n, i)
				return math.floor(n / 2 ^ i) % 2
			end
			bxor16 = function(a, b)
				local out, place = 0, 1
				for i = 0, 15 do
					if bitOf(a, i) ~= bitOf(b, i) then
						out = out + place
					end
					place = place * 2
				end
				return out
			end
			band16 = function(a, b)
				local out, place = 0, 1
				for i = 0, 15 do
					if bitOf(a, i) == 1 and bitOf(b, i) == 1 then
						out = out + place
					end
					place = place * 2
				end
				return out
			end
		end
		bxor32 = function(a, b)
			return bxor16(math.floor(a / HALF) % HALF, math.floor(b / HALF) % HALF) * HALF
				+ bxor16(a % HALF, b % HALF)
		end
		band32 = function(a, b)
			return band16(math.floor(a / HALF) % HALF, math.floor(b / HALF) % HALF) * HALF
				+ band16(a % HALF, b % HALF)
		end
	end
end

local function shr32(x, n)
	if n <= 0 then
		return x % MOD
	end
	return math.floor(x / 2 ^ n) % MOD
end

local function rotr32(x, n)
	x = x % MOD
	if n <= 0 then
		return x
	end
	-- (x >>> n) | (x << (32-n)), done with exact arithmetic (no 2^64 products)
	local low = x % (2 ^ n)
	return (math.floor(x / 2 ^ n) + low * 2 ^ (32 - n)) % MOD
end

local HEX = "0123456789abcdef"

-- 8-digit hex of a 32-bit value, without string.format("%x") (which some
-- interpreters refuse for values outside signed 32-bit integers)
local function hex8(n)
	n = n % MOD
	local out = {}
	for i = 7, 0, -1 do
		local nib = math.floor(n / 16 ^ i) % 16
		out[#out + 1] = HEX:sub(nib + 1, nib + 1)
	end
	return table.concat(out)
end

-- ---------- SHA-256 ----------
local K = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

-- returns the 32-byte binary digest as a lowercase hex string
--
-- This is the portable implementation. It runs directly wherever the host has
-- no native `hash` API, and is exported as M.pureSha256hex so the installer
-- and the test suite can exercise it even on a host that does have one.
function M.pureSha256hex(data)
	data = tostring(data or "")
	local msg = { data:byte(1, #data) }
	local bitLen = #data * 8
	msg[#msg + 1] = 0x80
	while #msg % 64 ~= 56 do
		msg[#msg + 1] = 0
	end
	-- 64-bit big-endian length; inputs stay far below 2^32 bits
	local hi = math.floor(bitLen / MOD)
	local lo = bitLen % MOD
	for _, b in ipairs({ math.floor(hi / 16777216) % 256, math.floor(hi / 65536) % 256, math.floor(hi / 256) % 256, hi % 256,
		math.floor(lo / 16777216) % 256, math.floor(lo / 65536) % 256, math.floor(lo / 256) % 256, lo % 256 }) do
		msg[#msg + 1] = b
	end

	local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
	local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19

	for chunk = 1, #msg, 64 do
		local w = {}
		for i = 0, 15 do
			local j = chunk + i * 4
			w[i] = ((msg[j] * 16777216) + (msg[j + 1] * 65536) + (msg[j + 2] * 256) + msg[j + 3]) % MOD
		end
		for i = 16, 63 do
			local s0 = bxor32(bxor32(rotr32(w[i - 15], 7), rotr32(w[i - 15], 18)), shr32(w[i - 15], 3))
			local s1 = bxor32(bxor32(rotr32(w[i - 2], 17), rotr32(w[i - 2], 19)), shr32(w[i - 2], 10))
			w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % MOD
		end

		local a, b, c, d = h0, h1, h2, h3
		local e, f, g, h = h4, h5, h6, h7

		for i = 0, 63 do
			local S1 = bxor32(bxor32(rotr32(e, 6), rotr32(e, 11)), rotr32(e, 25))
			local ch = bxor32(band32(e, f), band32(bxor32(e, 0xffffffff), g))
			local temp1 = (h + S1 + ch + K[i + 1] + w[i]) % MOD
			local S0 = bxor32(bxor32(rotr32(a, 2), rotr32(a, 13)), rotr32(a, 22))
			local maj = bxor32(bxor32(band32(a, b), band32(a, c)), band32(b, c))
			local temp2 = (S0 + maj) % MOD

			h = g
			g = f
			f = e
			e = (d + temp1) % MOD
			d = c
			c = b
			b = a
			a = (temp1 + temp2) % MOD
		end

		h0 = (h0 + a) % MOD
		h1 = (h1 + b) % MOD
		h2 = (h2 + c) % MOD
		h3 = (h3 + d) % MOD
		h4 = (h4 + e) % MOD
		h5 = (h5 + f) % MOD
		h6 = (h6 + g) % MOD
		h7 = (h7 + h) % MOD
	end

	return hex8(h0) .. hex8(h1) .. hex8(h2) .. hex8(h3)
		.. hex8(h4) .. hex8(h5) .. hex8(h6) .. hex8(h7)
end

-- ---------- host dispatch ----------
-- CC:Tweaked ships a native `hash` library. When it is available the digest
-- comes straight from the host, which matters because install.lua hashes every
-- installed file for the manifest.
local function bytesToHex(raw)
	local out = {}
	for i = 1, #raw do
		local b = raw:byte(i)
		out[#out + 1] = HEX:sub(math.floor(b / 16) + 1, math.floor(b / 16) + 1)
		out[#out + 1] = HEX:sub(b % 16 + 1, b % 16 + 1)
	end
	return table.concat(out)
end

function M.nativeSha256hex(data)
	if type(hash) ~= "table" or type(hash.sha256) ~= "function" then
		return nil
	end
	local ok, raw = pcall(hash.sha256, tostring(data or ""))
	if not ok or type(raw) ~= "string" then
		return nil
	end
	-- CC:Tweaked returns the 32 raw digest bytes; some builds hand back the
	-- 64-character hex text instead. Accept both, or a hex-returning host
	-- silently falls back to the slow pure path and the installer crawls.
	if #raw == 64 and raw:lower():match("^%x+$") then
		return raw:lower()
	end
	if #raw ~= 32 then
		return nil
	end
	return bytesToHex(raw)
end

function M.sha256hex(data)
	return M.nativeSha256hex(data) or M.pureSha256hex(data)
end

-- ---------- password digests ----------
-- Documented platform limitation: CC:Tweaked has no key-stretching
-- primitives and no secret storage, so this is a salted SHA-256 digest.
-- It keeps passwords out of the database in readable form but is not a
-- security boundary against an attacker with filesystem access.
function M.hashPassword(password, salt)
	salt = tostring(salt or "")
	return "sha256$" .. salt .. "$" .. M.sha256hex("cloveros/v2|" .. salt .. "|" .. tostring(password or ""))
end

function M.verifyPassword(password, stored)
	if type(stored) ~= "string" then
		return false
	end
	local salt = stored:match("^sha256%$([^%$]*)%$")
	if not salt then
		return false
	end
	return M.hashPassword(password, salt) == stored
end

return M
