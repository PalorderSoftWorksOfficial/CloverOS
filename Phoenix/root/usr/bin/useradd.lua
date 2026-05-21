local a=require"usermgr"local b=require"system.filesystem"local c=require"system.process"local d=require"system.util"local e=[[
Usage: useradd [options] LOGIN
       useradd -D
       useradd -D [options]
Options:
  -b, --base-dir BASE_DIR  base directory for the home directory of the new account
  -c, --comment COMMENT    full name of the new account
  -d, --home-dir HOME_DIR  home directory of the new account
  -D, --defaults           print or change default useradd configuration
  -f, --inactive INACTIVE  password inactivity period of the new account
  -h, --help               display this help message and exit
  -k, --skel SKEL_DIR      use this alternative skeleton directory
  -K, --key KEY=VALUE      override /etc/login.defs defaults
  -m, --create-home        create the user's home directory
  -M, --no-create-home     do not create the user's home directory
  -p, --password PASSWORD  password of the new account
  -s, --shell SHELL        login shell of the new account
]]local f=assert(d.argparse({b=true,["base-dir"]="@b",c=true,comment="@c",d=true,["home-dir"]="@d",D=false,defaults="@D",f="number",inactive="@f",h=false,help="@h",k=true,skel="@k",K="multiple",key="@K",m=false,["create-home"]="@m",M=false,["no-create-home"]="@M",p=true,password="@p",s=true,shell="@s"},...))if f.h then print(e)return end;local g={HOME="/home",INACTIVE=-1,SHELL="/bin/cash",SKEL="/etc/skel"}do local h=io.open("/etc/default/useradd","r")if h then for i in h:lines()do local j,k=i:gsub("#.*$",""):match"^([^=]+)=(.*)$"if j and k then g[j]=type(g[j])=="number"and tonumber(k)or k end end;h:close()end end;for l,i in ipairs(f.K or{})do local j,k=i:match"^([^=]+)=(.*)$"if j and k then g[j]=type(g[j])=="number"and tonumber(k)or k end end;if f.D then if f.b or f.f or f.s then if c.getuser()~="root"then error("useradd: Permission denied.")end;if f.b then g.HOME=f.b end;if f.f then g.INACTIVE=f.f end;if f.s then g.SHELL=f.s end;local h=assert(io.open("/etc/default/useradd","w"))for m,n in pairs(g)do h:write(m.."="..n.."\n")end;h:close()else for m,n in pairs(g)do print(m.."="..n)end end;return end;if not f[1]then io.stderr:write(e.."\n")return false end;if c.getuser()~="root"then error("useradd: Permission denied.")end;local o=f.d or b.combine(f.b or g.HOME,f[1])local p=f.f or g.INACTIVE;if p<0 then p=nil end;assert(a.addUser(f[1],f.p,{fullName=f.c,home=o,shell=f.s or g.SHELL,lockTime=p}))if f.m and not f.M then b.mkdir(o)b.chmod(o,f[1],"rwx")b.chmod(o,nil,"r-x")b.chown(o,f[1])local q=f.k or g.SKEL;if q and b.isDir(q)then local function r(s)local t=b.stat(s,true)if t.permissions[t.owner]then b.chmod(s,f[1],t.permissions[t.owner])end;b.chown(s,f[1])if t.type=="directory"then for l,n in ipairs(b.list(s))do r(b.combine(s,n))end end end;for l,n in ipairs(b.list(q))do b.copy(b.combine(q,n),b.combine(o,n),true)r(b.combine(o,n))end end end
