#!/usr/bin/env node
// Host-side test runner for CloverOS.
//
// Runs tests/host/main.lua inside a Lua VM (fengari) against an in-memory
// CraftOS environment, so the runtime modules can be tested without
// CraftOS-PC. The repository files are passed into the VM verbatim.
//
// Usage:
//   NODE_PATH=<dir containing fengari> node tests/host/run.js [suite]
//
// Suites: all (default) | hash | manifest | syntax | install | install_tasks
//         | module | shell2 | gnome | gui | boot | boot_text
//
// One-time setup of the Lua VM (any prefix works):
//   npm install --prefix /tmp/luatool fengari
// then:
//   NODE_PATH=/tmp/luatool/node_modules node tests/host/run.js
//
// This runner is a development tool; the authoritative test suite for the
// platform remains tests/run_tests.sh (CraftOS-PC).

"use strict";

const fs = require("fs");
const path = require("path");

let fengari;
try {
	fengari = require("fengari");
} catch (e) {
	try {
		fengari = require(process.env.FENGARI_PATH || "fengari");
	} catch (e2) {
		console.error("fengari not found. Install it with:");
		console.error("  npm install --prefix /tmp/luatool fengari");
		console.error("then run:");
		console.error("  NODE_PATH=/tmp/luatool/node_modules node tests/host/run.js");
		process.exit(2);
	}
}

const { lua, lauxlib, lualib, to_luastring } = fengari;
const crypto = require("crypto");

// CC:Tweaked exposes a native `hash.sha256` that returns the raw 32-byte
// digest; the shim models it with Node's crypto so runtime/hash.lua exercises
// its production path on the host.
function nativeSha256(L) {
	const input = lua.lua_tojsstring(L, 1);
	const digest = crypto.createHash("sha256").update(Buffer.from(input, "utf8")).digest();
	lua.lua_pushlstring(L, new Uint8Array(digest), digest.length);
	return 1;
}

function pushArg(L, a) {
	if (typeof a === "string") lua.lua_pushstring(L, to_luastring(a));
	else if (typeof a === "number") lua.lua_pushnumber(L, a);
	else if (typeof a === "boolean") lua.lua_pushboolean(L, a);
	else if (a == null) lua.lua_pushnil(L);
	else throw new Error("unsupported argument type");
}
let luaparse;
try {
	luaparse = require("luaparse");
} catch (e) {
	luaparse = null;
}

const REPO = path.resolve(__dirname, "..", "..");

// Directories and files that make up the tested surface. Boot path, runtime,
// commands, apps, config, and the test suites themselves.
const INCLUDE = [
	"startup.lua", "install.lua", "netinstall.lua", "CloverOS_OS.lua",
	"boot", "runtime", "libs", "bin", "apps", "etc", "tests",
];
const EXCLUDE_DIRS = new Set([".git", "node_modules", ".freebuff", "Phoenix", "experimental"]);

function walk(rel, out) {
	const abs = path.join(REPO, rel);
	let st;
	try {
		st = fs.statSync(abs);
	} catch (e) {
		return;
	}
	if (st.isDirectory()) {
		if (EXCLUDE_DIRS.has(path.basename(abs))) return;
		for (const name of fs.readdirSync(abs)) {
			walk(path.join(rel, name).replace(/\\/g, "/"), out);
		}
	} else if (st.isFile()) {
		out[rel.replace(/\\/g, "/")] = fs.readFileSync(abs, "utf8");
	}
}

const files = {};
for (const entry of INCLUDE) walk(entry, files);

// Lua 5.2 syntax gate: CC:Tweaked runs a Lua 5.2-level interpreter, so any
// accidental 5.3+ syntax (bit operators, integer division) must be caught.
if (luaparse) {
	let bad = 0;
	for (const [rel, content] of Object.entries(files)) {
		if (!rel.endsWith(".lua")) continue;
		try {
			luaparse.parse(content, { luaVersion: "5.2" });
		} catch (e) {
			bad++;
			console.error(`5.2 syntax error in ${rel}: ${e.message}`);
		}
	}
	if (bad > 0) {
		console.error(`Lua 5.2 gate failed for ${bad} file(s)`);
		process.exit(1);
	}
}

// Build a Lua chunk holding the repository contents. Every special byte is
// emitted as a decimal \ddd escape (always three digits, so no ambiguity with
// following digits); plain printable bytes stay literal.
function luaString(s) {
	const bytes = Buffer.from(s, "utf8");
	let out = '"';
	for (const b of bytes) {
		if (b >= 32 && b <= 126 && b !== 34 && b !== 92) {
			out += String.fromCharCode(b);
		} else {
			out += "\\" + String(b).padStart(3, "0");
		}
	}
	return out + '"';
}

let chunk = "return {\n";
for (const [rel, content] of Object.entries(files)) {
	chunk += `\t[${luaString(rel)}] = ${luaString(content)},\n`;
}
chunk += "}\n";

const suite = process.argv[2] || "all";

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function runChunk(source, name, ...args) {
	if (lauxlib.luaL_loadstring(L, to_luastring(source)) !== lua.LUA_OK) {
		throw new Error(`load error in ${name}: ${lua.lua_tojsstring(L, -1)}`);
	}
	for (const a of args) {
		pushArg(L, a);
	}
	lua.lua_call(L, args.length, 0);
}

try {
	if (lauxlib.luaL_loadstring(L, to_luastring(chunk)) !== lua.LUA_OK) {
		throw new Error(`load error in <repo files>: ${lua.lua_tojsstring(L, -1)}`);
	}
	lua.lua_call(L, 0, 1); // keep the repo files table on the stack
	const repoTableIndex = lua.lua_gettop(L);

	const mainSrc = fs.readFileSync(path.join(__dirname, "main.lua"), "utf8");
	if (lauxlib.luaL_loadstring(L, to_luastring(mainSrc)) !== lua.LUA_OK) {
		throw new Error(`load error in main.lua: ${lua.lua_tojsstring(L, -1)}`);
	}
	// hand the shim a real SHA-256 so it can expose CraftOS's `hash` library
	lua.lua_pushjsfunction(L, nativeSha256);
	lua.lua_setglobal(L, to_luastring("__nativeSha256"));
	lua.lua_pushvalue(L, repoTableIndex); // arg 1: repo files table
	pushArg(L, suite); // arg 2: suite name
	lua.lua_call(L, 2, 0);
} catch (e) {
	const msg = (e && e.message) || String(e);
	if (/HOST TESTS FAILED/.test(msg)) {
		process.exit(1); // failures already reported above
	} else if (/SHUTDOWN|os\.shutdown/.test(msg)) {
		// expected: a suite ended via os.shutdown()
	} else {
		console.error(e && e.stack || e);
		process.exit(1);
	}
}
