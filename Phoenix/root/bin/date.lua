local a=false;local b="%c"for c,d in ipairs{...}do if d=="-u"then a=true elseif d:sub(1,1)=="+"then b=d:sub(2)end end;if a then b="!"..b end;print(os.date(b))
