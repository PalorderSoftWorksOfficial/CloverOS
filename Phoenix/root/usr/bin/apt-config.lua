local a=require"system.util"local b=require"apt.config"local c=assert(a.argparse({empty=false,["no-empty"]=false,format=true,h=false,help="@h",v=false,version="@v",c=true,["config-file"]="@c",o="multiple",option="@o"},...))if c.v then print("apt-config 1.0")return end;if not c[1]or c.h then print[[
Usage: apt-config [options] command

apt-config is an interface to the configuration settings used by
all APT tools, mainly intended for debugging and shell scripting.

Most used commands:
  shell - get configuration values via shell evaluation
  dump - show the active configuration setting

See apt-config(8) for more information about the available commands.
Configuration options and syntax is detailed in apt.conf(5).
Information about how to configure sources can be found in sources.list(5).
Package and version choices can be expressed via apt_preferences(5).
Security details are available in apt-secure(8).
]]return end;b:load()if c.c then local d=assert(io.open(c.c,"r"))local e=d:read("*a")d:close()b:append(e)end;if c.o then for f,g in ipairs(c.o)do local h,i=g:match("^([A-Za-z0-9/%-:%._+])=(.*)$")if not h then error("Invalid option: "..g)end;local j={}for k in h:match("[^:]+")do j[#j+1]=k end;local l=b;for m=1,#j-1 do local k=j[m]:lower()if not l[k]then l[k]={}end;l=l[k]end;l[j[#j]]=i end end;if c[1]=="dump"then local n=c.f or'%f "%v";%n'local function o(p,h,i)return{["%f"]=p..h,["%t"]=h,["%v"]=i,["%n"]="\n",["%%"]="%"}end;local function q(p,r)for k,g in pairs(r)do if type(g)=="table"then local s=g._ or""if not c["no-empty"]or s~=""then local t=n:gsub("%%%a",o(p,k,s))io.write(t)end;q(p..k.."::",g)elseif type(g)=="string"and(not c["no-empty"]or g~="")then local t=n:gsub("%%%a",o(p,k,g))io.write(t)end end end;q("",b)else error("Unknown command '"..c[1].."'")end
