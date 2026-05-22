local a=require"system.filesystem"local b=require"system.process"local c=require"dpkg"local d=require"dpkg.divert"local e=require"dpkg.query"local f=require"dpkg.trigger"local function g(h)return a.combine(c.admindir,h)end;local function i(j,k)local l=a.open(j,"w")l.write(k)l.close()end;local function m(n,o)return({string.match(n.Status,"(%S+) (%S+) (%S+)")})[o]end;local function p(n,o,q)local r={string.match(n.Status,"(%S+) (%S+) (%S+)")}r[o]=q;n.Status=table.concat(r," ")return n.Status end;local function s(t)local b=io.popen("/bin/less","w")b:write(t)b:close()end;local u=[[Usage: dpkg [<option> ...] <command>

Commands:
    -i|--install       <.deb file name> ... | -R|--recursive <directory> ...
    --unpack           <.deb file name> ... | -R|--recursive <directory> ...
    -A|--record-avail  <.deb file name> ... | -R|--recursive <directory> ...
    --configure        <package> ... | -a|--pending
    --triggers-only    <package> ... | -a|--pending
    -r|--remove        <package> ... | -a|--pending
    -P|--purge         <package> ... | -a|--pending
    -V|--verify <package> ...        Verify the integrity of package(s).
    --get-selections [<pattern> ...] Get list of selections to stdout.
    --set-selections                 Set package selections from stdin.
    --clear-selections               Deselect every non-essential package.
    --update-avail [<Packages-file>] Replace available packages info.
    --merge-avail [<Packages-file>]  Merge with info from file.
    --clear-avail                    Erase existing available info.
    --forget-old-unavail             Forget uninstalled unavailable pkgs.
    -s|--status <package> ...        Display package status details.
    -p|--print-avail <package> ...   Display available version details.
    -L|--listfiles <package> ...     List files 'owned' by package(s).
    -l|--list [<pattern> ...]        List packages concisely.
    -S|--search <pattern> ...        Find package(s) owning file(s).
    -C|--audit [<package> ...]       Check for broken package(s).
    --yet-to-unpack                  Print packages selected for installation.
    --predep-package                 Print pre-dependencies to unpack.
    --add-architecture <arch>        Add <arch> to the list of architectures.
    --remove-architecture <arch>     Remove <arch> from the list of architectures.
    --print-architecture             Print dpkg architecture.
    --print-foreign-architectures    Print allowed foreign architectures.
    --assert-<feature>               Assert support for the specified feature.
    --validate-<thing> <string>      Validate a <thing>'s <string>.
    --compare-versions <a> <op> <b>  Compare version numbers - see below.
    --force-help                     Show help on forcing.
    -Dh|--debug=help                 Show help on debugging.

    -?, --help                       Show this help message.
        --version                    Show the version.

Assertable features: support-predepends, working-epoch, long-filenames,
    multi-conrep, multi-arch, versioned-provides.

Validatable things: pkgname, archname, trigname, version.

Use dpkg with -b, --build, -c, --contents, -e, --control, -I, --info,
    -f, --field, -x, --extract, -X, --vextract, --ctrl-tarfile, --fsys-tarfile
on archives (type dpkg-deb --help).

Options:
    --admindir=<directory>     Use <directory> instead of /var/lib/dpkg.
    --root=<directory>         Install on a different root directory.
    --instdir=<directory>      Change installation dir without changing admin dir.
    --path-exclude=<pattern>   Do not install paths which match a shell pattern.
    --path-include=<pattern>   Re-include a pattern after a previous exclusion.
    -O|--selected-only         Skip packages not selected for install/upgrade.
    -E|--skip-same-version     Skip packages whose same version is installed.
    -G|--refuse-downgrade      Skip packages with earlier version than installed.
    -B|--auto-deconfigure      Install even if it would break some other package.
    --[no-]triggers            Skip or force consequential trigger processing.
    --verify-format=<format>   Verify output format (supported: 'rpm').
    --no-debsig                Do not try to verify package signatures.
    --no-act|--dry-run|--simulate
                               Just say what we would do - don't do it.
    -D|--debug=<octal>         Enable debugging (see -Dhelp or --debug=help).
    --status-fd <n>            Send status change updates to file descriptor <n>.
    --status-logger=<command>  Send status change updates to <command>'s stdin.
    --log=<filename>           Log status changes and actions to <filename>.
    --ignore-depends=<package>,...
                               Ignore dependencies involving <package>.
    --force-...                Override problems (see --force-help).
    --no-force-...|--refuse-...
                               Stop when problems encountered.
    --abort-after <n>          Abort after encountering <n> errors.

Comparison operators for --compare-versions are:
    lt le eq ne ge gt       (treat empty version as earlier than any version);
    lt-nl le-nl ge-nl gt-nl (treat empty version as later than any version);
    < << <= = >= >> >       (only for compatibility with control file syntax).

Use 'apt' or 'aptitude' for user-friendly package management.]]local v={}local w=nil;local x=false;local y=false;local z=nil;local A,B;local C,D;for E,F in ipairs({...})do if w~=nil then table.insert(v,F)elseif string.match(F,"^%-[^-]")then local G=string.sub(F,2,2)if G=='i'then w=0 elseif G=='r'then w=4 elseif G=='P'then w=5 elseif G=='V'then w=6 elseif G=='C'then w=7 elseif G=='?'then if c.options.pager then s(u)else print(u)end;return elseif G=='D'then elseif G=='b'or G=='c'or G=='e'or G=='x'or G=='X'or G=='f'or G=='I'then w=13 elseif G=='l'or G=='s'or G=='L'or G=='S'or G=='p'then w=14 elseif G=='B'then c.options.auto_deconfigure=true elseif G=='R'then x=true elseif G=='G'then c.force.downgrade=false elseif G=='O'then y=true elseif G=='E'then c.options.skip_same_version=true end else local H;if string.find(F,"=")then F,H=string.match(F,"^(.+)=(.+)$")end;if F=="--install"then w=0 elseif F=="--unpack"then w=1 elseif F=="--configure"then w=2 elseif F=="--triggers-only"then w=3 elseif F=="--remove"then w=4 elseif F=="--purge"then w=5 elseif F=="--verify"then w=6 elseif F=="--audit"then w=7 elseif F=="--get-selections"then w=8 elseif F=="--set-selections"then w=9 elseif F=="--clear-selections"then w=10 elseif F=="--print-architecture"then print("phoenix")return elseif string.match(F,"^%-%-assert%-")then if F=="--assert-support-predepends"then return 0 elseif F=="--assert-working-epoch"then return 0 elseif F=="--assert-long-filenames"then return 0 elseif F=="--assert-multi-conrep"then return 1 elseif F=="--assert-multi-arch"then return 1 elseif F=="--assert-versioned-provides"then return 0 else return 2 end elseif string.match(F,"^%-%-validate%-")then w=11;z=string.match(F,"^%-%-validate%-(.+)")elseif F=="--compare-verisons"then w=12 elseif F=="--help"then if c.options.pager then s(u)else print(u)end;return elseif F=="--force-help"then(c.options.pager and s or print)([[dpkg forcing options - control behaviour when problems found:
warn but continue:  --force-<thing>,<thing>,...
stop with error:    --refuse-<thing>,<thing>,... | --no-force-<thing>,...
Forcing things:
[!] all                Set all force options
[*] downgrade          Replace a package with a lower version
    configure-any      Configure any package which may help this one
    hold               Process incidental packages even when on hold
    bad-verify         Install a package even if it fails authenticity check
    bad-version        Process even packages with wrong versions
    overwrite          Overwrite a file from one package with another
    overwrite-diverted Overwrite a diverted file with an undiverted version
[!] overwrite-dir      Overwrite one package's directory with another's file
[!] confnew            Always use the new config files, don't prompt
[!] confold            Always use the old config files, don't prompt
[!] confdef            Use the default option for new config files if one
                        is available, don't prompt. If no default can be found,
                        you will be prompted unless one of the confold or
                        confnew options is also given
[!] confmiss           Always install missing config files
[!] confask            Offer to replace config files with no new versions
[!] architecture       Process even packages with wrong or no architecture
[!] breaks             Install even if it would break another package
[!] conflicts          Allow installation of conflicting packages
[!] depends            Turn all dependency problems into warnings
[!] depends-version    Turn dependency version problems into warnings
[!] remove-reinstreq   Remove packages which require installation
[!] remove-essential   Remove an essential package

WARNING - use of options marked [!] can seriously damage your installation.
Forcing options marked [*] are enabled by default.]])return elseif F=="--build"or F=="--contents"or F=="--control"or F=="--extract"or F=="--vextract"or F=="--field"or F=="--ctrl-tarfile"or F=="--fsys-tarfile"or F=="--info"then w=13 elseif F=="--list"or F=="--status"or F=="--listfiles"or F=="--search"or F=="--print-avail"then w=14 elseif F=="--auto-deconfigure"then c.options.auto_deconfigure=true elseif F=="--debug"then elseif string.match(F,"^%-%-force%-")or string.match(F,"^%-%-no%-force%-")or string.match(F,"^%-%-refuse%-")then local I=string.match(F,"^%-%-force%-")~=nil;local J=F:gsub("^%-%-force%-",""):gsub("^%-%-no%-force%-",""):gsub("^%-%-refuse%-","")if J=="downgrade"then c.force.downgrade=I elseif J=="configure-any"then c.force.configure_any=I elseif J=="hold"then c.force.hold=I elseif J=="remove-reinstreq"then c.force.remove_reinstreq=I elseif J=="remove-essential"then c.force.remove_essential=I elseif J=="depends"then c.force.depends=I elseif J=="depends-version"then c.force.depends_version=I elseif J=="breaks"then c.force.breaks=I elseif J=="conflicts"then c.force.conflicts=I elseif J=="confmiss"then c.force.confmiss=I elseif J=="confnew"and c.force.confmode~=2 then c.force.confmode=0 elseif J=="confold"and c.force.confmode~=2 then c.force.confmode=1 elseif J=="confdef"then c.force.confmode=2 elseif J=="confask"and c.force.confmode==nil then c.force.confmode=nil elseif J=="overwrite"then c.force.overwrite=I elseif J=="overwrite-dir"then c.force.overwrite_dir=I elseif J=="overwrite-diverted"then c.force.overwrite_diverted=I elseif J=="architecture"then c.force.architecture=I elseif J=="bad-version"then c.force.bad_version=I elseif J=="bad-verify"then c.force.bad_verify=I end elseif F=="--ignore-depends"then for E,F in ipairs(split(H,","))do c.options.ignore_depends[F]=true end elseif F=="--no-act"or F=="--dry-run"or F=="--simulate"then c.options.dry_run=true elseif F=="--recursive"then x=true elseif F=="--admindir"then c.admindir,d.admindir,e.admindir,f.admindir=H,H,H,H elseif F=="--root"then c.rootdir=H elseif F=="--selected-only"then y=true elseif F=="--skip-same-verison"then c.options.skip_same_version=true elseif F=="--pre-invoke"then A=H elseif F=="--post-invoke"then B=H elseif F=="--path-exclude"then C=H elseif F=="--path-include"then D=H elseif F=="--no-pager"then c.options.pager=false elseif F=="--no-triggers"then c.options.triggers=false elseif F=="--triggers"then c.options.triggers=true end end end;local function K(t)c.error(t)print([[

Type dpkg --help for help about installing and deinstalling packages [*];
Use 'apt' or 'aptitude' for user-friendly package management;
Type dpkg -Dhelp for a list of dpkg debug flag values;
Type dpkg --force-help for a list of forcing options;
Type dpkg-deb --help for help about manipulating *.deb files;

Options marked [*] produce a lot of output !]])return 2 end;if w==nil then K("need an action option")end;if not a.exists(g(""))then a.mkdir(g("info"))a.mkdir(g("triggers"))i(g("status"),"")i(g("triggers/Unincorp"),"")i(g("triggers/File"),"")end;if w==0 or w==1 then if#v==0 then K((w==0 and"--install"or"--unpack").." needs at least one package archive file argument")end;local L={}for E,F in ipairs(v)do if not a.exists(F)then c.error("cannot access archive '"..F.."': No such file or directory")return 2 end;if x then if not a.isDir(F)then c.error("cannot access directory '"..F.."': Not a directory")return 2 end;local function M(g)for E,N in ipairs(a.list(g))do if a.isDir(a.combine(g,N))then M(a.combine(g,N))elseif N:match("^.*%.deb$")then c.print("Loading "..F.." (this may take a while) ...")local O,P=pcall(c.package,N)if not O then c.error("cannot access archive '"..a.combine(g,N).."': "..P)return 2 end;table.insert(L,P)end end end;M(F)else c.print("Loading "..F.." (this may take a while) ...")local O,P=pcall(c.package,F)if not O then c.error("cannot access archive '"..F.."': "..P)return 2 end;table.insert(L,P)end end;if#L==0 then c.error("searched, but found no packages (files matching *.deb)")return 2 end;local Q={}for E,F in ipairs(L)do c.print("Selecting previously unselected package "..F.name..".")if c.package.packagedb==nil then c.readDatabase()end;c.package.packagedb[F.name]=c.package.packagedb[F.name]or{Status="unknown ok not-installed"}p(c.package.packagedb[F.name],1,"install")if not F.unpack()or w==0 and not F.configure()then table.insert(Q,F.name)end end;if c.options.triggers then for R,F in pairs(c.package.packagedb)do if F["Triggers-Pending"]then c.print("Processing triggers for "..R.." ("..F.Version..") ...")f.commit(R,c.package.triggerdb,c.package.packagedb)end end end;e.writeDatabase(c.package.packagedb)if#Q>0 then c.print("dpkg: error processing "..table.concat(Q,", "))return 2 else return 0 end elseif w==2 then if x then c.warn("--recursive specified, but this flag is ineffective with --configure")end;if#v==0 then K("--configure needs at least one package name argument")end;c.readDatabase()local Q={}if v[1]=="--pending"or v[1]=="-a"then for R,F in pairs(c.package.packagedb)do if e.status.needs_configure(m(F,3))then local O,P=pcall(c.package,R)if not O or not P.configure()then table.insert(Q,R)end end end else for E,R in ipairs(v)do if e.status.needs_configure(m(c.package.packagedb[R],3))then local O,P=pcall(c.package,R)if not O or not P.configure()then table.insert(Q,R)end end end end;e.writeDatabase(c.package.packagedb)if#Q>0 then c.print("dpkg: error processing "..table.concat(Q,", "))return 2 else return 0 end elseif w==3 then if x then c.warn("--recursive specified, but this flag is ineffective with --triggers-only")end;if#v==0 then K("--triggers-only needs at least one package name argument")end;c.readDatabase()local Q={}if v[1]=="--pending"or v[1]=="-a"then if c.options.triggers then for R,F in pairs(c.package.packagedb)do if F["Triggers-Pending"]then c.print("Processing triggers for "..R.." ("..F.Version..") ...")f.commit(R,c.package.triggerdb,c.package.packagedb)end end end else if c.options.triggers then for E,R in ipairs(v)do if c.package.packagedb[R]["Triggers-Pending"]then c.print("Processing triggers for "..R.." ("..c.package.packagedb[R].Version..") ...")f.commit(R,c.package.triggerdb,c.package.packagedb)end end end end;e.writeDatabase(c.package.packagedb)if#Q>0 then c.print("dpkg: error processing "..table.concat(Q,", "))return 2 else return 0 end elseif w==4 then if x then c.warn("--recursive specified, but this flag is ineffective with --remove")end;if#v==0 then K("--remove needs at least one package name argument")end;c.readDatabase()local Q={}for E,R in ipairs(v)do local O,P=pcall(c.package,R)if O then p(c.package.packagedb[R],1,"deinstall")end;if not O or not P.remove(false)then table.insert(Q,R)end end;e.writeDatabase(c.package.packagedb)if#Q>0 then c.print("dpkg: error processing "..table.concat(Q,", "))return 2 else return 0 end elseif w==5 then if x then c.warn("--recursive specified, but this flag is ineffective with --purge")end;if#v==0 then K("--purge needs at least one package name argument")end;c.readDatabase()local Q={}for E,R in ipairs(v)do local O,P=pcall(c.package,R)if O then p(c.package.packagedb[R],1,"purge")end;if not O or not P.remove(true)then table.insert(Q,R)end end;e.writeDatabase(c.package.packagedb)if#Q>0 then c.print("dpkg: error processing "..table.concat(Q,", "))return 2 else return 0 end elseif w==6 then if x then c.warn("--recursive specified, but this flag is ineffective with --verify")end;c.readDatabase()local Q={}if#v==0 then for R in pairs(c.package.packagedb)do local O,P=pcall(c.package,R)if not O or not P.verify()then table.insert(Q,R)end end else for E,R in ipairs(v)do local O,P=pcall(c.package,R)if not O or not P.verify()then table.insert(Q,R)end end end;e.writeDatabase(c.package.packagedb)if#Q>0 then c.print("dpkg: error verifying "..table.concat(Q,", "))return 2 else return 0 end elseif w==7 then c.readDatabase()if#v==0 then for R,F in pairs(c.package.packagedb)do if not a.exists(g("info/"..R..".list"))then c.warn("package "..R.." is missing a file list\nTo fix this issue: reinstall the package")end;if not a.exists(g("info/"..R..".md5sums"))then c.warn("package "..R.." is missing an md5sum list\nTo fix this issue: reinstall the package")end;if m(F,1)=="install"then if m(F,3)=="half-installed"or m(F,2)=="reinstreq"then c.warn("package "..R.." is not installed properly\nTo fix this issue: reinstall the package")elseif m(F,3)=="not-installed"or m(F,3)=="config-files"then c.warn("package "..R.." is marked for installation, but it is not installed\nTo fix this issue: install the package")elseif m(F,3)~="installed"then c.warn("package "..R.." is not configured\nTo fix this issue: configure the package")end elseif m(F,1)=="deinstall"then if m(F,3)=="not-installed"then c.warn("package "..R.." is marked for removal of non-config files, but config files are not installed\nTo fix this issue: reinstall package then remove properly")elseif m(F,3)=="installed"or m(F,3)=="triggers-pending"or m(F,3)=="triggers-awaited"then c.warn("package "..R.." is marked for removal, but the package hasn't been removed\nTo fix this issue: remove the package")elseif m(F,3)~="config-files"then c.warn("package "..R.." was not removed properly\nTo fix this issue: remove the package")end elseif m(F,1)=="purge"then if m(F,3)=="config-files"then c.warn("package "..R.." is marked for purge, but config files are still installed\nTo fix this issue: purge the package")elseif m(F,3)=="installed"or m(F,3)=="triggers-pending"or m(F,3)=="triggers-awaited"then c.warn("package "..R.." is marked for purge, but the package hasn't been removed\nTo fix this issue: remove the package")elseif m(F,3)~="config-files"then c.warn("package "..R.." was not purged properly\nTo fix this issue: remove the package")end elseif m(F,1)=="unknown"then c.warn("package "..R.." is in an unknown status\nTo fix this issue: (re)install the package")end end else for E,R in ipairs(v)do local F=c.package.packagedb[R]if not F then c.warn("package "..R.." not found")else if not a.exists(g("info/"..R..".list"))then c.warn("package "..R.." is missing a file list\nTo fix this issue: reinstall the package")end;if not a.exists(g("info/"..R..".md5sums"))then c.warn("package "..R.." is missing an md5sum list\nTo fix this issue: reinstall the package")end;if m(F,1)=="install"then if m(F,3)=="half-installed"or m(F,2)=="reinstreq"then c.warn("package "..R.." is not installed properly\nTo fix this issue: reinstall the package")elseif m(F,3)=="not-installed"or m(F,3)=="config-files"then c.warn("package "..R.." is marked for installation, but it is not installed\nTo fix this issue: install the package")elseif m(F,3)~="installed"then c.warn("package "..R.." is not configured\nTo fix this issue: configure the package")end elseif m(F,1)=="deinstall"then if m(F,3)=="not-installed"then c.warn("package "..R.." is marked for removal of non-config files, but config files are not installed\nTo fix this issue: reinstall package then remove properly")elseif m(F,3)=="installed"or m(F,3)=="triggers-pending"or m(F,3)=="triggers-awaited"then c.warn("package "..R.." is marked for removal, but the package hasn't been removed\nTo fix this issue: remove the package")elseif m(F,3)~="config-files"then c.warn("package "..R.." was not removed properly\nTo fix this issue: remove the package")end elseif m(F,1)=="purge"then if m(F,3)=="config-files"then c.warn("package "..R.." is marked for purge, but config files are still installed\nTo fix this issue: purge the package")elseif m(F,3)=="installed"or m(F,3)=="triggers-pending"or m(F,3)=="triggers-awaited"then c.warn("package "..R.." is marked for purge, but the package hasn't been removed\nTo fix this issue: remove the package")elseif m(F,3)~="config-files"then c.warn("package "..R.." was not purged properly\nTo fix this issue: remove the package")end elseif m(F,1)=="unknown"then c.warn("package "..R.." is in an unknown status\nTo fix this issue: (re)install the package")end end end end elseif w==8 then c.readDatabase()local S={}if#v==0 then for R,F in pairs(c.package.packagedb)do if m(F,3)~="not-installed"then table.insert(S,{R,m(F,1)})end end else for E,R in ipairs(v)do table.insert(S,{R,m(c.package.packagedb[R],1)})end end;textutils.tabulate(table.unpack(S))elseif w==9 then elseif w==10 then c.readDatabase()for R,F in pairs(c.package.packagedb)do if F.Priority~="essential"and F.Priority~="required"then p(F,1,"deinstall")end end;e.writeDatabase(c.package.packagedb)return 0 elseif w==11 then if z=="pkgname"then return string.match(v[1],"^%w[%w+-.]+$")and 0 or 2 elseif z=="trigname"then return string.match(v[1],"^%w[%w+-.]+$")and 0 or 2 elseif z=="archname"then return(v[1]=="all"or v[1]=="any"or v[1]=="phoenix"or v[1]=="source")and 0 or((v[1]=="i386"or v[1]=="amd64"or v[1]=="powerpc"or v[1]=="armv7h"or v[1]=="aarch64"or v[1]=="ppc64el"or v[1]=="ia64"or v[1]=="s390x"or v[1]=="mips"or v[1]=="mipsel"or v[1]=="mips64el"or v[1]=="armv7el")and 1 or 2)elseif z=="version"then return c.compareVersions(v[1],"1")and 0 or 2 else K("unknown option --validate-"..z)end elseif w==12 then if#v<3 then K("--compare-versions takes three arguments: <version> <relation> <version>")end;local T=c.findRelationship("a",v[1],"a ("..v[2].." "..v[3]..")")if T==nil then return 2 elseif T==true then return 0 else return 1 end elseif w==13 then return b.run("/usr/bin/dpkg-deb",...)elseif w==14 then return b.run("/usr/bin/dpkg-query",...)end
