util = require "data/tf_util/tf_util"
names = require("shared")
local mask = data.raw["character"]["character"].collision_mask
if mask then
  table.insert(mask, "not-colliding-with-itself")
else
  mask = util.ground_unit_collision_mask()
  data.raw["character"]["character"].collision_mask = mask
end

data.raw.unit[names.units.construction_drone].collision_mask = mask
