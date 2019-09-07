
local created_items = function()
  return
  {
    ["iron-plate"] = 8,
    ["wood"] = 1,
    ["pistol"] = 1,
    ["firearm-magazine"] = 10,
    ["burner-mining-drill"] = 1,
    ["stone-furnace"] = 1,
    [names.units.construction_drone] = 10
  }
end

local respawn_items = function()
  return
  {
    ["pistol"] = 1,
    ["firearm-magazine"] = 10,
    [names.units.construction_drone] = 10
  }
end

local register_remote = function()
  if not remote.interfaces["freeplay"] then return {} end
  remote.call("freeplay", "set_skip_intro", true)
  remote.call("freeplay", "set_respawn_items", respawn_items())
  remote.call("freeplay", "set_created_items", created_items())
end

local lib = {}
lib.on_init = register_remote
lib.get_events = function() return {} end
return lib
