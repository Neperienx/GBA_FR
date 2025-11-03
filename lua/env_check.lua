-- env_check.lua
console.clear()
console.log("Lua: ".._VERSION)
console.log("Has 'comm'? "..tostring(comm ~= nil))
if comm then
  for k,v in pairs(comm) do
    if k:match("^socket") then console.log("comm."..k.." = "..type(v)) end
  end
end
