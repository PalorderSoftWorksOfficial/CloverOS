local a=require"system.network"return function(b)local c,d=a.getData(b)if c and d==200 then return c elseif c then return nil,"HTTP status "..d else return nil,d end end
