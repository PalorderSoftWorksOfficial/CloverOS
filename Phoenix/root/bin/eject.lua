if not...then error("Usage: eject <drive>")end;return assert(coroutine.yield("syscall","devcall",...,"eject"))
