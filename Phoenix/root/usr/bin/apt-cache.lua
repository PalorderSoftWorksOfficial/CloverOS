local a=require"system.filesystem"local b=require"system.util"local c=require"apt.config"local d=require"apt.cache"local e=require"muxzcat"local f=require"LibDeflate"local g=assert(b.argparse({p=true,["pkg-cache"]="@p",s=true,["src-cache"]="@s",q=false,quiet="@q",i=false,important="@i",["no-pre-depends"]=false,["no-depends"]=false,["no-recommends"]=false,["no-suggests"]=false,["no-conflictss"]=false,["no-breaks"]=false,["no-replaces"]=false,["no-enhances"]=false,implicit=false,f=false,full="@f",a=false,["all-versions"]="@a",g=false,generate="@g",["no-generate"]=false,n=false,["names-only"]="@n",["all-names"]=false,recurse=false,installed=false,["with-source"]=true,h=false,help="@h",v=false,version="@v",c=true,["config-file"]="@c",o="multiple",option="@o"},...))if g.v then print("apt-cache 1.0")return end;if not g[1]or g.h then print[[
Usage: apt-cache [options] command
       apt-cache [options] show pkg1 [pkg2 ...]

apt-cache queries and displays available information about installed
and installable packages. It works exclusively on the data acquired
into the local cache via the 'update' command of e.g. apt-get. The
displayed information may therefore be outdated if the last update was
too long ago, but in exchange apt-cache works independently of the
availability of the configured sources (e.g. offline).

Most used commands:
  showsrc - Show source records
  search - Search the package list for a regex pattern
  depends - Show raw dependency information for a package
  rdepends - Show reverse dependency information for a package
  show - Show a readable record for the package
  pkgnames - List the names of all packages in the system
  policy - Show policy settings

See apt-cache(8) for more information about the available commands.
Configuration options and syntax is detailed in apt.conf(5).
Information about how to configure sources can be found in sources.list(5).
Package and version choices can be expressed via apt_preferences(5).
Security details are available in apt-secure(8).
]]return end;c:load()if g.c then local h=assert(io.open(g.c,"r"))local i=h:read("*a")h:close()c:append(i)end;if g.o then for j,k in ipairs(g.o)do local l,m=k:match("^([A-Za-z0-9/%-:%._+])=(.*)$")if not l then error("Invalid option: "..k)end;local n={}for o in l:match("[^:]+")do n[#n+1]=o end;local p=c;for q=1,#n-1 do local o=n[q]:lower()if not p[o]then p[o]={}end;p=p[o]end;p[n[#n]]=m end end;if g[1]=="gencaches"then d:generate()elseif g[1]=="showpkg"then if not g["no-generate"]then d:generate()end;d:load()for q=2,#g do local r=d:get(g[q])if r then print("Package: "..r.name)print("Versions:")print(r.version)print("Reverse Depends:")for j,k in ipairs(r.depended)do print("  "..k.package..","..r.name.." "..(k.version or""))end;print("Dependencies:")io.write(r.version.." - ")for j,k in ipairs(r.depends)do io.write(k.package.." ("..(k.relation or"0").." "..(k.version or"(null)")..") ")end;print()print("Provides:")io.write(r.version.." - ")for j,k in ipairs(r.provides)do io.write(k.package.."(= "..(k.version or"(null)")..") ")end;print()end end elseif g[1]=="stats"then elseif g[1]=="showsrc"then elseif g[1]=="dump"then elseif g[1]=="dumpavail"then elseif g[1]=="unmet"then elseif g[1]=="show"then if not g["no-generate"]then d:generate()end;d:load()for q=2,#g do local r=d:get(g[q])if r then local s=assert(d:getRepo(r.repoIndex))local t=c:get("Acquire","IndexTargets","deb","Packages","MetaKey"):gsub("%$%(COMPONENT%)",s.component):gsub("%$%(ARCHITECTURE%)",s.architecture)local u=a.combine(s.url:gsub("^.-://",""),"dists",s.suite,t):gsub("[/:]","_")local v=a.combine(c:getPath("State","lists"),u)local i;local h=io.open(v,"r")if h then i=h:read("*a")h:close()else h=io.open(v..".xz","rb")if h then local w=h:read("*a")h:close()i=e.DecompressXzOrLzmaString(w)else h=io.open(v..".gz","rb")if h then local x=h:read("*a")h:close()i=f:DecompressGzip(x)end end end;if i then print(i:match("(Package: "..r.name..".-)\n\n")or i:match("(Package: "..r.name..".-)$")or"Could not find package in Packages list.")else error("Could not find Packages file for owner repository.")end end end elseif g[1]=="search"then if not g["no-generate"]then d:generate()end;d:load(true)local y={}for o,k in pairs(d.db.packagesByName)do if o:find(g[2],1,true)then local s=d:getRepo(k.repoIndex)y[#y+1]=o.."/"..s.suite.." "..k.version.." "..s.architecture end end;table.sort(y)for j,k in ipairs(y)do print(k)end elseif g[1]=="depends"then elseif g[1]=="rdepends"then elseif g[1]=="pkgnames"then else error("Unknown command '"..g[1].."'")end
