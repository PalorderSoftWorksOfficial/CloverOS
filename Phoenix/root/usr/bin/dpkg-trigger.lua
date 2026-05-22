local a=require"dpkg.query"local b=require"dpkg.trigger"local c={}local d=_ENV.DPKG_MAINTSCRIPT_PACKAGE;local e=true;local f=true;local g;for h,i in ipairs({...})do if g then if g==0 then b.admindir=i;a.admindir=i elseif g==1 then d=i end;g=nil elseif i=="--check-supported"then return 0 elseif i=="-?"or i=="--help"then print([[Usage: dpkg-trigger [<options> ...] <trigger-name>
       dpkg-trigger [<options> ...] <command>

Commands:
  --check-supported                Check if the running dpkg supports triggers.

  -?, --help                       Show this help message.
      --version                    Show the version.

Options:
  --admindir=<directory>           Use <directory> instead of /var/lib/dpkg.
  --by-package=<package>           Override trigger awaiter (normally set
                                   by dpkg).
  --await                          Package needs to await the processing.
  --no-await                       No package needs to await the processing.
  --no-act                         Just test - don't actually change anything.
 ]])return 0 elseif i=="--version"then print([[Debian dpkg-trigger package trigger utility version 1.19.0.5 (Phoenix).]])return 0 elseif i=="--admindir"then g=0 elseif string.match(i,"^--admindir=")then b.admindir=string.sub(i,12)a.admindir=string.sub(i,12)elseif i=="--by-package"then g=1 elseif string.match(i,"^--by-package=")then d=string.sub(i,14)elseif i=="--await"then e=true elseif i=="--no-await"then e=false elseif i=="--no-act"then f=false else table.insert(c,i)end end;if c[1]==nil then error([[error: takes one argument, the trigger name

Type dpkg-trigger --help for help about this utility.]])end;if d==nil then error([[error: must be called from a maintainer script (or with a --by-package option)

Type dpkg-trigger --help for help about this utility.]])end;b.log=function(j)print("\x1b[31m"..j.."\x1b[0m")end;if f then b.activate(c[1],d,e)end;return 0
