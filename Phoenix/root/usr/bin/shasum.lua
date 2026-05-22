local a=require"sha2"local b=require"system.util"local c=assert(b.argparse({a=true,algorithm="@a",b=false,binary="@b",c=false,check="@c",tag=false,t=false,text="@t",U=false,UNIVERSAL="@U",["0"]=false,["01"]="@0",["ignore-missing"]=false,q=false,quiet="@q",s=false,status="@s",strict=false,w=false,warn="@w",h=false,help="@h",v=false,version="@v"},...))if c.h then print[[
Usage: shasum [OPTION]... [FILE]...
Print or check SHA checksums.
With no FILE, or when FILE is -, read standard input.

    -a, --algorithm   1 (default), 224, 256, 384, 512, 512224, 512256
    -b, --binary      read in binary mode
    -c, --check       read SHA sums from the FILEs and check them
        --tag         create a BSD-style checksum
    -t, --text        read in text mode (default)
    -U, --UNIVERSAL   read in Universal Newlines mode
                        produces same digest on Windows/Unix/Mac
    -0, --01          read in BITS mode
                        ASCII '0' interpreted as 0-bit,
                        ASCII '1' interpreted as 1-bit,
                        all other characters ignored

The following five options are useful only when verifying checksums:
        --ignore-missing  don't fail or report status for missing files
    -q, --quiet           don't print OK for each successfully verified file
    -s, --status          don't output anything, status code shows success
        --strict          exit non-zero for improperly formatted checksum lines
    -w, --warn            warn about improperly formatted checksum lines

    -h, --help        display this help and exit
    -v, --version     output version information and exit

When verifying SHA-512/224 or SHA-512/256 checksums, indicate the
algorithm explicitly using the -a option, e.g.

    shasum -a 512224 -c checksumfile

The sums are computed as described in FIPS PUB 180-4.  When checking,
the input should be a former output of this program.  The default
mode is to print a line with checksum, a character indicating type
(`*' for binary, ` ' for text, `U' for UNIVERSAL, `^' for BITS),
and name for each FILE.  The line starts with a `\' character if the
FILE name contains either newlines or backslashes, which are then
replaced by the two-character sequences `\n' and `\\' respectively.
]]return elseif c.v then print("1.0")return end;c[1]=c[1]or"-"for d,e in ipairs(c)do local f=e=="-"and io.stdin or assert(io.open(e,c.b and not c.t and"rb"or"r"))local g;if c.a=="1"or not c.a then g=a.sha1()elseif c.a=="224"then g=a.sha224()elseif c.a=="256"then g=a.sha256()elseif c.a=="384"then g=a.sha384()elseif c.a=="512"then g=a.sha512()elseif c.a=="512224"then g=a.sha512_224()elseif c.a=="512256"then g=a.sha512_256()else error("shasum: invalid algorithm "..c.a)end;local h;repeat local i=f:read("*L")if i and c["0"]then i=i:gsub("[^01]",""):gsub("........",function(j)return string.char(tonumber(j,2))end)end;h=g(i)until not i;if f~=io.stdin then f:close()end;if c.tag then print("SHA"..(c.a or"1"):gsub("(...)(...)","%1/%2").." ("..e..") = "..h)else print(h.."  "..e)end end
