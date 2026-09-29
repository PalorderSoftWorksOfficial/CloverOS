-- Compatibility shim: network install now delegates to the canonical installer.
-- Usage: netinstall
shell.run("install", "--net")
