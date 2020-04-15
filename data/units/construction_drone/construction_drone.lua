local path = util.path("data/units/construction_drone/")
local name = names.units.construction_drone

local scale = 1

local animation =
{
  layers =
  {
    {
      filename = path.."drone_walk.png",
      line_length = 16,
      width = 78,
      height = 104,
      frame_count = 1,
      direction_count = 32,
      axially_symmetrical = false,
      scale = 0.4,
      shift = util.by_pixel(0, -14),
    },
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
      scale = 0.4,
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
  subgroup="logistic-network",
  has_belt_immunity = false,
  can_open_gates = true,
  affected_by_tiles = true,
  collision_box = {{-0.10, -0.10 }, {0.00, 0.00}},
  --collision_box = {{-0.2, -0.2}, {0.2, 0.2}},
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
  vision_distance = 100,
  not_controllable = true,
  movement_speed = 0.16,
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
    path_resolution_modifier = 0
  },
  light =
  {
    {
      minimum_darkness = 0.3,
      intensity = 0.4,
      size = 10,
      color = {r=1.0, g=1.0, b=1.0}
    },
    {
      type = "oriented",
      minimum_darkness = 0.3,
      picture =
      {
        filename = "__core__/graphics/light-cone.png",
        priority = "extra-high",
        flags = { "light" },
        scale = 2,
        width = 200,
        height = 200
      },
      shift = {0, -3.5},
      size = 0.5,
      intensity = 0.6,
      color = {r=1.0, g=1.0, b=1.0}
    }
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
  enabled = true,
  ingredients =
  {
    {"iron-plate", 5},
    {"iron-gear-wheel", 5},
    {"electronic-circuit", 10},
  },
  energy_required = 1,
  result = name
}

local proxy_chest_name = names.entities.construction_drone_proxy_chest
local proxy_chest = util.copy(data.raw.container["wooden-chest"])
proxy_chest.name = proxy_chest_name
proxy_chest.localised_name = proxy_chest_name
proxy_chest.collision_box = nil
proxy_chest.inventory_size = 4
proxy_chest.order = "nnov"
proxy_chest.next_upgrade = nil

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

beam_base = util.copy(data.raw.beam["laser-beam"])
beam_base.damage_interval = 10000

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
  proxy_chest,
  build_beam,
  deconstruct_beam,
  pickup_beam,
  attack_beam
}