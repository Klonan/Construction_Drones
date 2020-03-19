util = require "data/tf_util/tf_util"
names = require("shared")

for k, character in pairs(data.raw["character"]) do
  if character.collision_mask then
    table.insert(character.collision_mask, "not-colliding-with-itself")
  else
    character.collision_mask = util.ground_unit_collision_mask()
  end
end
