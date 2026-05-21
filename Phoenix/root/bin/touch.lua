for a,b in ipairs{...}do if b:sub(1,1)~="-"then assert(io.open(b,"a")):close()end end
