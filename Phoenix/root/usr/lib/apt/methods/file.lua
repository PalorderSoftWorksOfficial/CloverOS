return function(a)local b,c=io.open(a:gsub("^file://",""):gsub("^[^/]","/%0"),"rb")if not b then return nil,c end;local d=b:read("*a")b:close()return d end
