util = require "data/tf_util/tf_util"
names = require("shared")

--[[
  ]]

  local mask = data.raw["character"]["character"].collision_mask
  if mask then
    table.insert(mask, "not-colliding-with-itself")
  else
    mask = util.ground_unit_collision_mask()
    data.raw["character"]["character"].collision_mask = mask
  end

--[[


  local drone_layer = "layer-14"
  local collide_list =
  {
    accumulator = true,
    ["ammo-turret"] = true,
    ["arithmetic-combinator"] = true,
    ["artillery-turret"] = true,
    ["assembling-machine"] = true,
    beacon = true,
    boiler = true,
    cliff = true,
    ["constant-combinator"] = true,
    container = true,
    ["decider-combinator"] = true,
    ["electric-energy-interface"] = true,
    ["electric-pole"] = true,
    ["electric-turret"] = true,
    ["fluid-turret"] = true,
    furnace = true,
    gate = true,
    generator = true,
    ["heat-interface"] = true,
    ["infinity-container"] = true,
    ["infinity-pipe"] = true,
    inserter = true,
    lab = true,
    lamp = true,
    ["logistic-container"] = true,
    market = true,
    ["mining-drill"] = true,
    ["offshore-pump"] = true,
    pipe = true,
    ["pipe-to-ground"] = true,
    ["player-port"] = true,
    ["power-switch"] = true,
    ["programmable-speaker"] = true,
    pump = true,
    radar = true,
    reactor = true,
    roboport = true,
    ["rocket-silo"] = true,
    ["simple-entity"] = true,
    ["simple-entity-with-force"] = true,
    ["simple-entity-with-owner"] = true,
    ["solar-panel"] = true,
    ["storage-tank"] = true,
    ["train-stop"] = true,
    tree = true,
    turret = true,
    ["unit-spawner"] = true,
    wall = true
  }

  local get_default_mask = function(type)
    return {"object-layer", "item-layer", "player-layer", "water-tile"}
  end

  for type, bool in pairs (collide_list) do
    for k, entity in pairs (data.raw[type]) do
      entity.collision_mask = entity.collision_mask or get_default_mask(type)
      table.insert(entity.collision_mask, drone_layer)
    end
  end

  local collides = function(mask)
    for k, v in pairs (mask) do
      if v == "water-tile" then
        return true
      end
    end
  end

  for k, tile in pairs (data.raw.tile) do
    if collides(tile.collision_mask) then
      table.insert(tile.collision_mask, drone_layer)
    end
  end

  data.raw.unit[names.units.construction_drone].collision_mask = {drone_layer, "not-colliding-with-itself"}
  --data.raw.character.character.collision_mask ={drone_layer, "not-colliding-with-itself"}



  --data.raw.unit[names.units.construction_drone].collision_mask = {"object-layer", "not-colliding-with-itself"}
  ]]