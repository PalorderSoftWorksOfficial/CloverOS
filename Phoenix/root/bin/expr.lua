print(assert(load(table.concat({...}," "):gsub("&"," and "):gsub("|"," or "),"=expr","t",{}))())
