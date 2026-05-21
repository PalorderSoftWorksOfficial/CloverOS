local a=require"usermgr"local b=require"system.filesystem"local c=require"system.process"local d=require"system.util"local e=[[
Usage: userdel [options] LOGIN
Options:
  -f, --force   force some actions that would fail otherwise
                e.g. removal of user still logged in
                or files, even if not owned by the user
  -h, --help    display this help message and exit
  -r, --remove  remove home directory
]]local f=assert(d.argparse({f=false,force="@f",h=false,help="@h",r=false,remove="@r"},...))if f.h then print(e)return end;if not f[1]then io.stdout:write(e.."\n")return false end;if c.getuser()~="root"then error("userdel: Permission denied.")end;local g=a.getUserInfo(f[1])if not g then error("userdel: User does not exist.")end;if not f.f then local h=c.getplist()for i,j in ipairs(h)do if c.getpinfo(j).user==f[1]then error("userdel: User is currently logged in.")end end end;assert(a.removeUser(f[1]),"userdel: Could not delete user.")if f.r and g.home then b.remove(g.home)end
