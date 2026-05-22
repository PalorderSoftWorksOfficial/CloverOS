local a=require"system.pretty"local b=require"system.terminal"local c=require"system.util"local d=assert(c.argparse({h=false,help=false,e=true,l=true,i=false,v=false},...))for e,f in ipairs(d)do if f=="--"then table.remove(d,e)break end end;if d.h then print[=[
usage: lua [options] [script [args]].
Available options are:
  -e stat  execute string 'stat'
  -l name  require library 'name'
  -i       enter interactive mode after executing 'script'
  -v       show version information
  --       stop handling options
  -        execute stdin and stop handling options
]=]return 0 elseif d.v then print(_VERSION,"Copyright (C) 2021 JackMacWindows")return 0 end;if d.l then _ENV[d.l]=require(d.l)end;if d.e then assert(load(d.e,"=(command line)","t"))()end;if d[1]then local g;if d[1]=="-"then g=assert(load(function()return io.stdin:read("*L")end,"=stdin"))else g=assert(load(d[1],"@"..d[1]))end;g(table.unpack(d,2,#d))if not d.i then return 0 end end;exit=setmetatable({},{__tostring=function()return"Press Ctrl+D or Ctrl+C to exit"end})quit=exit;print(_VERSION,"Copyright (C) 2021 JackMacWindows")local h={}while true do local i=""local g,j;repeat if i==""then io.stdout:write("> ")else io.stdout:write(">> ")end;local k=b.readline2(h)if not k then print()return 0 end;i=i..k.."\n"g,j=load("return "..i,"=stdin")if not g then g,j=load(i,"=stdin")end until g or not j:match("<eof>")if g then local l=table.pack(pcall(g))if l[1]then for e=2,l.n do a.print(a.pretty(l[e],{function_source=true,function_args=true}))end else io.stderr:write(l[2].."\n")end else io.stderr:write(j.."\n")end;table.insert(h,1,i:sub(1,-2))end
