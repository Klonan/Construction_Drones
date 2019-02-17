if not remote.interfaces["freeplay"] then return {} end

local created_items = function()
  return
  {
    ["iron-plate"] = 100,
    ["pistol"] = 1,
    ["firearm-magazine"] = 50,
    ["burner-mining-drill"] = 40,
    ["stone-furnace"] = 40,
    ["light-armor"] = 1,
    [names.equipment.drone_port] = 1,
    [names.units.construction_drone] = 10
  }
end

local respawn_items = function()
  return
  {
    ["pistol"] = 1,
    ["firearm-magazine"] = 50,
    ["light-armor"] = 1,
    [names.equipment.drone_port] = 1,
    [names.units.construction_drone] = 10
  }
end

local register_remote = function()
  remote.call("freeplay", "set_skip_intro", true)
  remote.call("freeplay", "set_respawn_items", respawn_items())
  remote.call("freeplay", "set_created_items", created_items())
end

local lib = {}
lib.on_init = register_remote
lib.get_events = function() return {} end
return lib
