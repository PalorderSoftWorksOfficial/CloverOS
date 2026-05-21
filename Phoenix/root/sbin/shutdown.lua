local a=require"startmgr"local b=require"system.log"local c=require"system.process"local d=require"system.util"local e=assert(d.argparse({P=false,poweroff="@P",H="@P",halt="@P",h="@P",r=false,reboot="@r",c=false,show=false,help=false},...))if e.help then print[[
Usage: shutdown [OPTIONS] [TIME]
Options:
  --help          Show this help
  -H, --halt      Equivalent to -P
  -P, --poweroff  Power off the machine
  -r, --reboot    Reboot the machine
  -h              Equivalent to -P
  -c              Cancel a pending shutdown
  --show          Show pending shutdown
]]end;local f={31,28,31,30,31,30,31,31,30,31,30,31}local function g(h)return h%4==0 and(h%100~=0 or h%400==0)end;if e.c then return a.remove("shutdown-timer","root")elseif e.show then local i=a.status("shutdown-timer","root")if i then else print("No scheduled shutdown.")end else local j=e[1]or"+1"if j=="+0"or j=="now"then if e.r and not e.P then assert(a.reboot())else assert(a.shutdown())end else local k;if j:match"^%+%d+$"then k=tonumber(j:match"^%+(%d+)$")*60 elseif j:match"^%d+:%d+$"then local l,m=j:match"^(%d+):(%d+)$"l,m=tonumber(l),tonumber(m)if l<0 or l>23 or m<0 or m>59 then error("shutdown: Invalid argument")end;local n=os.date("!*t")if l<n.hour or l==n.hour and m<n.min then n.day=n.day+1;n.wday=(n.wday+1)%7;n.yday=(n.yday+1)%(g(n.year)and 366 or 365)if n.day>f[n.month]or n.month==2 and g(n.year)and n.day>29 then n.day=1;n.month=n.month+1;if n.month>12 then n.month=1;n.year=n.year+1 end end end;n.hour,n.min,n.sec=l,m,0;k=os.time(n)-os.time()else error("shutdown: Invalid argument")end;assert(a.add([[
name = "shutdown-timer"
unit.description = "Shutdown Timer"
function trigger()
    startmgr.]]..(e.r and not e.P and"reboot"or"shutdown")..[[()
end
timer.loadTime = ]]..k,"root"))b.notice("System is going down in "..k/60 .." minutes.")end end
