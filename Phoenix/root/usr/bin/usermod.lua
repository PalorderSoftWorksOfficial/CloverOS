local a=require"usermgr"local b=require"system.filesystem"local c=require"system.process"local d=require"system.util"local e=[[
Usage: useradd [options] LOGIN
       useradd -D
       useradd -D [options]
Options:
  -c, --comment COMMENT    new full name of the account
  -d, --home HOME_DIR      new home directory of the account
  -h, --help               display this help message and exit
  -m, --move-home          move the user's home directory
  -s, --shell SHELL        new login shell of the account
]]local f=assert(d.argparse({c=true,comment="@c",d=true,home="@d",h=false,help="@h",m=false,["move-home"]="@m",s=true,shell="@s"},...))if f.h then print(e)return end;if not f[1]then io.stderr:write(e.."\n")return false end;local g=c.getuser()if g~="root"and g~=f[1]then error("usermod: Permission denied.")end;local h=a.getUserInfo(f[1])if not h then error("usermod: User does not exist.")end;if f.s==""then f.s="/bin/cash"end;assert(a.editUser(f[1],{fullName=f.c,home=f.d,shell=f.s}),"usermod: Could not modify user.")if f.m and f.d and h.home~=f.d then b.move(h.home,f.d)end
