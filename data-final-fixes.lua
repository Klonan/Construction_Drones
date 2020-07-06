util = require "data/tf_util/tf_util"
names = require("shared")

local remove_from_list = function(list, value)
  for k, v in pairs (list) do
    if v == value then
      table.remove(list, k)
      return
    end
  end
end

for k, rail in pairs (data.raw["straight-rail"]) do
  rail.collision_mask = rail.collision_mask or {"water-tile", "floor-layer", "item-layer"}
  remove_from_list(rail.collision_mask, "item-layer")
  remove_from_list(rail.collision_mask, "floor-layer")
  table.insert(rail.collision_mask, "floor-layer")
end

for k, rail in pairs (data.raw["curved-rail"]) do
  rail.collision_mask = rail.collision_mask or {"water-tile", "floor-layer", "item-layer"}
  remove_from_list(rail.collision_mask, "item-layer")
  remove_from_list(rail.collision_mask, "floor-layer")
  table.insert(rail.collision_mask, "floor-layer")
end

for k, gate in pairs (data.raw.gate) do
  gate.opened_collision_mask = gate.opened_collision_mask or {"object-layer", "item-layer", "floor-layer", "water-tile"}
  remove_from_list(gate.opened_collision_mask, "item-layer")
end



local name = names.units.construction_drone
data.raw.unit[name].collision_mask = {"not-colliding-with-itself", "doodad-layer", "item-layer", "consider-tile-transitions"}
