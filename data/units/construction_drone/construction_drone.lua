local path = util.path("data/units/construction_drone/")
local name = names.units.construction_drone

local scale = 1

local animation =
{
  layers =
  {
    walk =
    {
      filename = path.."drone_walk.png",
      line_length = 16,
      width = 78,
      height = 104,
      frame_count = 1,
      direction_count = 32,
      axially_symmetrical = false,
      scale = 0.33,
      shift = util.by_pixel(0, -14),
    },
    walk_shadow =
    {
      filename = path.."drone_shadow.png",
      width = 142,
      height = 56,
      line_length = 1,
      frame_count = 1,
      direction_count = 32,
      axially_symmetrical = false,
      shift = util.by_pixel(10.5, -8.5),
      draw_as_shadow = true,
      scale = 0.33,
    }
  }
}

local unit = {
  type = "unit",
  name = name,
  localised_name = name,
  icon = path.."construction_drone_icon.png",
  icon_size = 64,
  flags = {"placeable-player", "placeable-enemy", "placeable-off-grid"},
  map_color = {r = 0, g = 1, b = 1, a = 1},
  max_health = 45,
  order = "b-b-a",
  subgroup="enemies",
  has_belt_immunity = false,
  can_open_gates = true,
  affected_by_tiles = true,
  collision_box = {{-0.12, -0.12 }, {0.12, 0.12}},
  selection_box = {{-0.6 * scale, -1.0 * scale}, {0.6 * scale, 0.4 * scale}},
  collision_mask = util.ground_unit_collision_mask(),
  attack_parameters =
  {
    type = "beam",
    range = 16,
    min_attack_distance = 12,
    cooldown = 100,
    cooldown_deviation = 0.2,
    ammo_category = "melee",
    ammo_type =
    {
      category = "melee",
      target_type = "entity",
      action =
      {
        type = "direct",
        action_delivery =
        {
          type = "beam",
          beam = names.beams.attack,
          max_length = 40,
          duration = 45
        }
      }
    },
    sound = nil,
    animation = animation
  },
  vision_distance = 10,
  movement_speed = 0.1,
  distance_per_frame = 0.1,
  pollution_to_join_attack = 20000000,
  distraction_cooldown = 30000000,
  min_pursue_time = 0,
  max_pursue_distance = 0,
  corpse = nil,
  dying_explosion = "explosion",
  --dying_sound =  make_biter_dying_sounds(0.4),
  working_sound =
  {
    sound = {
      {filename = path.."construction_drone_1.ogg"},
      {filename = path.."construction_drone_2.ogg"},
      {filename = path.."construction_drone_3.ogg"},
      {filename = path.."construction_drone_4.ogg"},
      {filename = path.."construction_drone_5.ogg"},
      {filename = path.."construction_drone_6.ogg"},
      {filename = path.."construction_drone_7.ogg"},
      {filename = path.."construction_drone_8.ogg"},
      {filename = path.."construction_drone_9.ogg"},
      {filename = path.."construction_drone_10.ogg"},
      {filename = path.."construction_drone_11.ogg"},
      {filename = path.."construction_drone_12.ogg"},
      {filename = path.."construction_drone_13.ogg"}
    },
    probability = 1 / (8 * 60),
    volume = 0.5
  },
  run_animation = animation,
  minable = {result = name, mining_time = 1},
  ai_settings =
  {
    destroy_when_commands_fail = false,
    allow_try_return_to_spawner = false,
    do_separation = true,
    path_resolution_modifier = -2
  }
}


local item = {
  type = "item",
  name = name,
  localised_name = name,
  icon = unit.icon,
  icon_size = unit.icon_size,
  flags = {},
  subgroup = data.raw.item["construction-robot"].subgroup,
  order = "a-"..name,
  stack_size= 10,
  place_result = nil --name
}

local recipe = {
  type = "recipe",
  name = name,
  localised_name = name,
  category = data.raw.recipe["construction-robot"].category,
  enabled = false,
  ingredients =
  {
    {"iron-plate", 5},
    {"iron-gear-wheel", 5},
    {"electronic-circuit", 10},
  },
  energy_required = 1,
  result = name
}

local shoo =
{
  type = "sound",
  name = "shoo",
  filename = path.."shoo.ogg"
}

--Sticker time!

local background = "__core__/graphics/entity-info-dark-background.png"

local shift = {0, -0.3}

local item_types =
{
  "item",
  "rail-planner",
  "item-with-entity-data",
  "blueprint-item",
  "upgrade-item",
  "deconstruction-item",
  "ammo",
  "gun",
  "tool",
  "repair-tool",
  "copy-paste-tool",
  "module",
  "armor",
  "item-with-inventory",
  "item-with-label",
  "item-with-tags",
  "capsule"
}

for k, item_type in pairs(item_types) do
  for name, prototype in pairs (data.raw[item_type] or {}) do
    if prototype.icon then
      local sticker =
      {
        type = "sticker",
        name = prototype.name.." Drone Sticker",
        flags = {},
        animation =
        {
          layers =
          {
            {
              filename = background,
              width = 53,
              height = 53,
              scale = 0.5,
              frame_count = 1,
              shift = shift
            },
            {
              filename = prototype.icon,
              priority = "extra-high",
              width = prototype.icon_size,
              height = prototype.icon_size,
              scale = (32 / prototype.icon_size) / 2,
              frame_count = 1,
              animation_speed = 1,
              shift = shift
            }
          }
        },
        duration_in_ticks = 2 ^ 31,
        target_movement_modifier = 1,
        force_visibility = "same",
        single_particle = true
      }
      data:extend{sticker}
    end
  end
end

local simple_storage_chest_name = names.entities.simple_storage_chest
local simple_storage_chest = util.copy(data.raw["logistic-container"]["logistic-chest-storage"])
simple_storage_chest.name =simple_storage_chest_name
simple_storage_chest.minable.result = simple_storage_chest_name
simple_storage_chest.localised_name = simple_storage_chest_name
simple_storage_chest.inventory_size = 19
simple_storage_chest.picture =
{
  filename = path.."simple-storage-chest.png",
  priority = "extra-high",
  width = 48,
  height = 34,
  shift = {0.1875, 0}
}
simple_storage_chest.animation = nil

local simple_storage_chest_item = {
  type = "item",
  name = simple_storage_chest_name,
  localised_name = simple_storage_chest_name,
  icon = path.."simple-storage-chest.png",
  icon_size = 32,
  flags = {},
  subgroup = data.raw.item["logistic-chest-storage"].subgroup,
  order = "c-"..simple_storage_chest_name,
  stack_size= 50,
  place_result = simple_storage_chest_name
}

local simple_storage_chest_recipe = {
  type = "recipe",
  name = simple_storage_chest_name,
  localised_name = simple_storage_chest_name,
  category = data.raw.recipe["logistic-chest-storage"].category,
  enabled = false,
  ingredients =
  {
    {"iron-chest", 1},
    {"electronic-circuit", 5},
  },
  energy_required = 0.5,
  result = simple_storage_chest_name
}

local simple_provider_chest_name = names.entities.simple_provider_chest
local simple_provider_chest = util.copy(data.raw["logistic-container"]["logistic-chest-passive-provider"])
simple_provider_chest.name = simple_provider_chest_name
simple_provider_chest.localised_name = simple_provider_chest_name
simple_provider_chest.minable.result = simple_provider_chest_name
simple_provider_chest.inventory_size = 19
simple_provider_chest.picture =
{
  filename = path.."simple-provider-chest.png",
  priority = "extra-high",
  width = 48,
  height = 34,
  shift = {0.1875, 0}
}
simple_provider_chest.animation = nil

local simple_provider_chest_item = {
  type = "item",
  name = simple_provider_chest_name,
  localised_name = simple_provider_chest_name,
  icon = path.."simple-provider-chest.png",
  icon_size = 32,
  flags = {},
  subgroup = data.raw.item["logistic-chest-passive-provider"].subgroup,
  order = "d-"..simple_provider_chest_name,
  stack_size= 50,
  place_result = simple_provider_chest_name
}

local simple_provider_chest_recipe = {
  type = "recipe",
  name = simple_provider_chest_name,
  localised_name = simple_provider_chest_name,
  category = data.raw.recipe["logistic-chest-passive-provider"].category,
  enabled = false,
  ingredients =
  {
    {"iron-chest", 1},
    {"electronic-circuit", 5},
  },
  energy_required = 0.5,
  result = simple_provider_chest_name
}

--[[

  local equipment_grid_name = "tiny-equipment-grid"
  for k, armor in pairs (data.raw.armor) do
    armor.equipment_grid = armor.equipment_grid or equipment_grid_name
  end
  ]]

local equipment_category = {
  type = "equipment-category",
  name = "drone"
}

local equipment_grid =
{
  type = "equipment-grid",
  name = equipment_grid_name,
  localised_name = equipment_grid_name,
  width = 1,
  height = 1,
  equipment_categories = {"drone"}
}

local equipment_name = names.equipment.drone_port

local equipment =
{
  type = "roboport-equipment",
  name = equipment_name,
  localised_name = equipment_name,
  take_result = equipment_name,
  sprite =
  {
    filename = "__base__/graphics/equipment/personal-roboport-equipment.png",
    width = 64,
    height = 64,
    priority = "medium"
  },
  shape =
  {
    width = 1,
    height = 1,
    type = "full"
  },
  energy_source =
  {
    type = "electric",
    buffer_capacity = "0MJ",
    input_flow_limit = "0KW",
    usage_priority = "secondary-input"
  },
  charging_energy = "0kW",

  robot_limit = 0,
  construction_radius = 50,
  spawn_and_station_height = 0,
  charge_approach_distance = 0,

  recharging_animation =
  {
    filename = "__base__/graphics/entity/roboport/roboport-recharging.png",
    priority = "high",
    width = 37,
    height = 35,
    frame_count = 16,
    scale = 1.5,
    animation_speed = 0.5
  },
  recharging_light = {intensity = 0.4, size = 5},
  stationing_offset = {0, -0.6},
  charging_station_shift = {0, 0},
  charging_station_count = 0,
  charging_distance = 0,
  charging_threshold_distance = 0,
  categories = {"drone"}
}

local equipment_item = {
  type = "item",
  name = equipment_name,
  localised_name = equipment_name,
  icon = "__base__/graphics/equipment/personal-roboport-equipment.png",
  icon_size = 64,
  flags = {},
  subgroup = data.raw.item["personal-roboport-equipment"].subgroup,
  order = "a-"..equipment_name,
  stack_size = 1,
  placed_as_equipment_result = equipment_name,
}

local equipment_recipe = {
  type = "recipe",
  name = equipment_name,
  localised_name = equipment_name,
  category = data.raw.recipe["personal-roboport-equipment"].category,
  enabled = false,
  ingredients =
  {
    {"iron-plate", 10},
    {"iron-gear-wheel", 15},
    {"electronic-circuit", 25},
  },
  energy_required = 1,
  result = equipment_name
}

local technology_name = names.technologies.construction_drone_system
local technology = {
  type = "technology",
  name = technology_name,
  localised_name = technology_name,
  localised_description = "Unlocked construction drones",
  icon = path.."construction_drone_technology.png",
  icon_size = 150,
  effects =
  {
    {
      type = "unlock-recipe",
      recipe = name
    },
    --[[

      {
        type = "unlock-recipe",
        recipe = names.entities.logistic_beacon
      },
      {
        type = "unlock-recipe",
        recipe = simple_storage_chest_name
      },
      {
        type = "unlock-recipe",
        recipe = simple_provider_chest_name
      },
      {
        type = "unlock-recipe",
        recipe = equipment_name
      },
      ]]
      {
        type = "ghost-time-to-live",
        modifier = 60 * 60 * 60 * 24 * 7
      }
    },
    unit =
    {
      count = 200,
      ingredients = {
        {"automation-science-pack", 1},
      --{"logistic-science-pack", 1},
    },
    time = 30
  },
  prerequisites = {"electronics"},
  order = "y-a"
}

local proxy_chest_name = names.entities.construction_drone_proxy_chest
local proxy_chest = util.copy(data.raw.container["wooden-chest"])
proxy_chest.name = proxy_chest_name
proxy_chest.localised_name = proxy_chest_name
proxy_chest.collision_box = nil
proxy_chest.inventory_size = 1
proxy_chest.order = "nnov"

local beam_blend_mode = "additive"
local beam_base =
{
  type = "beam",
  flags = {"not-on-map"},
  damage_interval = 1000,
  width = 0.5,
  random_target_offset = true,
  target_offset_y = -0.3,
  head =
  {
    filename = path.."beams/".."beam-head.png",
    line_length = 16,
    width = 45,
    height = 39,
    frame_count = 16,
    animation_speed = 0.5,
    blend_mode = beam_blend_mode
  },
  tail =
  {
    filename = path.."beams/".."beam-tail.png",
    line_length = 16,
    width = 45,
    height = 39,
    frame_count = 16,
    blend_mode = beam_blend_mode
  },
  body =
  {
    {
      filename = path.."beams/".."beam-body-1.png",
      line_length = 16,
      width = 45,
      height = 39,
      frame_count = 16,
      blend_mode = beam_blend_mode
    },
    {
      filename = path.."beams/".."beam-body-2.png",
      line_length = 16,
      width = 45,
      height = 39,
      frame_count = 16,
      blend_mode = beam_blend_mode
    },
    {
      filename = path.."beams/".."beam-body-3.png",
      line_length = 16,
      width = 45,
      height = 39,
      frame_count = 16,
      blend_mode = beam_blend_mode
    },
    {
      filename = path.."beams/".."beam-body-4.png",
      line_length = 16,
      width = 45,
      height = 39,
      frame_count = 16,
      blend_mode = beam_blend_mode
    },
    {
      filename = path.."beams/".."beam-body-5.png",
      line_length = 16,
      width = 45,
      height = 39,
      frame_count = 16,
      blend_mode = beam_blend_mode
    },
    {
      filename = path.."beams/".."beam-body-6.png",
      line_length = 16,
      width = 45,
      height = 39,
      frame_count = 16,
      blend_mode = beam_blend_mode
    }
  }
}

local beams = names.beams

local build_beam = util.copy(beam_base)
util.recursive_hack_tint(build_beam, {g = 1})
build_beam.name = beams.build
build_beam.localised_name = beams.build
build_beam.action = nil

local deconstruct_beam = util.copy(beam_base)
util.recursive_hack_tint(deconstruct_beam, {r = 1})
deconstruct_beam.name = beams.deconstruction
deconstruct_beam.localised_name = beams.deconstruction
deconstruct_beam.action = nil

local pickup_beam = util.copy(beam_base)
util.recursive_hack_tint(pickup_beam, {g = 1, b = 1})
pickup_beam.name = beams.pickup
pickup_beam.localised_name = beams.pickup
pickup_beam.action = nil

local attack_beam = util.copy(beam_base)
util.recursive_hack_tint(attack_beam, {r = 1, b = 1})
attack_beam.name = beams.attack
attack_beam.localised_name = beams.attack
attack_beam.damage_interval = 20
attack_beam.action =
{
  type = "direct",
  action_delivery =
  {
    type = "instant",
    target_effects =
    {
      {
        type = "damage",
        damage = { amount = 5, type = util.damage_type(name)}
      }
    }
  }
}

data:extend
{
  unit,
  item,
  recipe,
  --shoo,
  technology,
  --simple_provider_chest,
  --simple_provider_chest_item,
  --simple_provider_chest_recipe,
  --simple_storage_chest,
  --simple_storage_chest_item,
  --simple_storage_chest_recipe,
  --equipment,
  --equipment_grid,
  --equipment_item,
  --equipment_recipe,
  --equipment_category,
  proxy_chest,
  build_beam,
  deconstruct_beam,
  pickup_beam,
  attack_beam
}