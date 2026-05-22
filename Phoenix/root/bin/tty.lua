local a=require"system.process"local b=a.getpinfo(a.getpid())if b.stdout then print("tty"..b.stdout)end
