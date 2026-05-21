local a=require"sha2"local b=require"system.util"local c=assert(b.argparse({b=false,binary="@b",c=false,check="@c",l="number",length="@l",tag=false,t=false,text="@t",z=false,zero="@z",["ignore-missing"]=false,quiet=false,status=false,strict=false,w=false,warn="@w",h=false,help="@h",v=false,version="@v"},...))if c.h then print[[
Usage: b2sum [OPTION]... [FILE]...
Print or check BLAKE2b (512-bit) checksums.

With no FILE, or when FILE is -, read standard input.
  -b, --binary          read in binary mode
  -c, --check           read checksums from the FILEs and check them
  -l, --length=BITS     digest length in bits; must not exceed the max for
                          the blake2 algorithm and must be a multiple of 8
      --tag             create a BSD-style checksum
  -t, --text            read in text mode (default)
  -z, --zero            end each output line with NUL, not newline,
                          and disable file name escaping

The following five options are useful only when verifying checksums:
      --ignore-missing  don't fail or report status for missing files
      --quiet           don't print OK for each successfully verified file
      --status          don't output anything, status code shows success
      --strict          exit non-zero for improperly formatted checksum lines
  -w, --warn            warn about improperly formatted checksum lines

      --help        display this help and exit
      --version     output version information and exit

The sums are computed as described in RFC 7693.
When checking, the input should be a former output of this program.
The default mode is to print a line with: checksum, a space,
a character indicating input mode ('*' for binary, ' ' for text
or where binary is insignificant), and name for each FILE.
]]return elseif c.v then print("1.0")return end;c[1]=c[1]or"-"for d,e in ipairs(c)do local f=e=="-"and io.stdin or assert(io.open(e,c.b and not c.t and"rb"or"r"))local g=a.blake2b(nil,nil,nil,c.l and c.l/8)local h;repeat local i=f:read("*L")h=g(i)until not i;if f~=io.stdin then f:close()end;local j;if c.tag then j="BLAKE2b"..(c.l and"-"..c.l or"").." ("..e..") = "..h else j=h.."  "..e end;if c.z then io.stdout:write(j.."\0")else print(j)end end
