local lib = {}

lib.on_init = function()
  if not remote.interfaces["freeplay"] then return end
  local created_items = remote.call("freeplay", "get_created_items")
  created_items[names.units.construction_drone] = 10
  remote.call("freeplay", "set_created_items", created_items)
end

return lib
