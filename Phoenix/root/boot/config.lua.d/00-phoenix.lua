menuentry("Phoenix")({
	description("Boot Phoenix normally."),
	kernel(rootDirectory .. "/boot/kernel.lua"),
	args("init=/sbin/init " .. bootArgs),
})
menuentry("Phoenix (single)")({
	description("Boot Phoenix in single user mode."),
	kernel(rootDirectory .. "/boot/kernel.lua"),
	args("init=/bin/cash " .. bootArgs),
})
