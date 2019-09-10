util = require "data/tf_util/tf_util"
names = require("shared")
--require "data/hotkeys"
require "data/units/units"
require "data/entities/entities"

--data.raw["character"]["character"].collision_mask = util.ground_unit_collision_mask()
local mask = data.raw["character"]["character"].collision_mask
table.insert(mask, "not-colliding-with-itself")
data.raw.unit[names.units.construction_drone].collision_mask = mask
