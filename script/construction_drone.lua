
local max = math.huge
local insert = table.insert
local remove = table.remove
local pairs = pairs
local beams = names.beams
local proxy_name = names.entities.construction_drone_proxy_chest
local drone_range = 64
local beam_offset = {0, -0.5}

drone_prototypes =
{
  [names.units.construction_drone] =
  {
    interact_range = 4,
    return_to_character_range = -1
  },
}

local unique_index = function(entity)
  if entity.unit_number then return entity.unit_number end
  return entity.surface.index..entity.name..entity.position.x..entity.position.y
end

local is_commandable = function(string)
  return drone_prototypes[string] ~= nil
end

local ghost_type = "entity-ghost"
local tile_ghost_type = "tile-ghost"
local proxy_type = "item-request-proxy"
local tile_deconstruction_proxy = "deconstructible-tile-proxy"
local cliff_type = "cliff"


local drone_pathfind_flags =
{
  allow_destroy_friendly_entities = false,
  cache = false,
  low_priority = false,
  prefer_straight_paths = true,
  no_break = true
}

local drone_orders =
{
  construct = 1,
  deconstruct = 2,
  repair = 3,
  upgrade = 4,
  request_proxy = 5,
  cliff_deconstruct = 8,
  follow = 9,
  return_to_character = 10
}

local data =
{
  drone_commands = {},
  targets = {},
  sent_deconstruction = {},
  debug = false,
  proxy_chests = {},
  migrate_deconstructs = true,
  migrate_characters = true,
  path_requests = {},
  request_count = {},
  set_default_shortcut = true,
  job_queue = {},
  already_targeted = {},
  search_queue = {}
}

local prototype_cache = {}
local get_prototype = function(name)
  if prototype_cache[name] then return prototype_cache[name] end
  local prototype = game.entity_prototypes[name]
  prototype_cache[name] = prototype
  return prototype
end

local sin, cos = math.sin, math.cos
local angle = util.angle

local get_beam_orientation = function(source_position, target_position)

    -- Angle in rads
    local angle = angle(target_position, source_position)

    -- Convert to orientation
    local orientation =  (angle / (2 * math.pi)) - 0.25
    if orientation < 0 then orientation = orientation + 1 end

    local x, y = 0, 0.5


    --[[x = x cos θ − y sin θ
    y = x sin θ + y cos θ]]
    angle = angle + (math.pi / 2)
    local x1 = (x * cos(angle)) - (y * sin(angle))
    local y1 = (x * sin(angle)) + (y * cos(angle))

    return orientation, {x1, y1 - 0.5}

end

local abs = math.abs
local rect_dist = function(position_1, position_2)
  return abs(position_1.x - position_2.x) + abs(position_1.y - position_2.y)
end

local is_in_range = function(position_1, position_2)
  local dx = position_1.x - position_2.x
  local dy = position_1.y - position_2.y
  if dx > drone_range then return end
  if dy > drone_range then return end
  if dx < -drone_range then return end
  if dy < -drone_range then return end
  return true
end

local get_drone_radius = function()
  return 0.3
end

local print = function(string)
  --if not data.debug then return end
  local tick = game.tick
  log(tick.." | "..string)
  game.print(tick.." | "..string)
end

local oofah = (2 ^ 0.5) / 2

local radius_map

local get_radius_map = function()
  --Caching radius map, deliberately not local or data
  if radius_map then return radius_map end
  radius_map = {}
  for k, entity in pairs (game.entity_prototypes) do
    radius_map[k] = entity.radius
  end
  return radius_map
end

local ranges =
{
  interact = 1,
  return_to_character = 3
}

local get_radius = function(entity, range)
  local radius
  local type = entity.type
  if type == ghost_type then
    radius = get_radius_map()[entity.ghost_name]
  elseif type == cliff_type then
    radius = entity.get_radius() * 2
  --elseif entity.name == drone_name then
  --  radius = get_drone_radius()
  elseif is_commandable(entity.name) then
    if range == ranges.interact then
      radius = get_radius_map()[entity.name] + drone_prototypes[entity.name].interact_range
    elseif range == ranges.return_to_character then
      radius = get_radius_map()[entity.name] + drone_prototypes[entity.name].return_to_character_range
    else
      radius = get_radius_map()[entity.name]
    end
  else
    radius = get_radius_map()[entity.name]
  end

  if radius < oofah then
    return oofah
  end
  return radius
end

local distance = function(position_1, position_2)
  local x1 = position_1[1] or position_1.x
  local y1 = position_1[2] or position_1.y
  local x2 = position_2[1] or position_2.x
  local y2 = position_2[2] or position_2.y
  return (((x2 - x1) * (x2 - x1)) + ((y2 - y1) * (y2 - y1))) ^ 0.5
end

local in_range = function(entity_1, entity_2, extra)

  local distance = distance(entity_1.position, entity_2.position)
  return distance <= (get_radius(entity_1) + (get_radius(entity_2))) + (extra or 2)

end

local in_construction_range = function(drone, target, range)
  local distance =  distance(drone.position, target.position)
  return distance <= (get_radius(drone, range) + (get_radius(target)))
end

local floor = math.floor
local random = math.random
local stack_from_product = function(product)
  local count = floor(product.amount or (random() * (product.amount_max - product.amount_min) + product.amount_min))
  if count < 1 then return end
  local stack =
  {
    name = product.name,
    count = count
  }
  --print(serpent.line(stack))
  return stack
end

local proxy_position = {1000000, 1000000}

local get_proxy_chest = function(drone)
  local index = drone.unit_number
  local proxy_chest = data.proxy_chests[index]
  if proxy_chest and proxy_chest.valid then
    return proxy_chest
  end
  local new = drone.surface.create_entity
  {
    name = proxy_name,
    position = proxy_position,
    force = drone.force
  }
  data.proxy_chests[index] = new
  return new
end

local get_drone_inventory = function(drone_data)
  local inventory = drone_data.inventory
  if inventory and inventory.valid then
    inventory.sort_and_merge()
    return inventory
  end
  local drone = drone_data.entity
  local proxy_chest = get_proxy_chest(drone)
  drone_data.inventory = proxy_chest.get_inventory(defines.inventory.chest)
  return drone_data.inventory
end

local get_drone_first_stack = function(drone_data)
  local inventory = get_drone_inventory(drone_data)
  if inventory.is_empty() then return end
  inventory.sort_and_merge()
  local stack = inventory[1]
  if stack and stack.valid and stack.valid_for_read then
    return stack
  end
end

local get_first_empty_stack = function(inventory)
  inventory.sort_and_merge()
  for k = 1, #inventory do
    local stack = inventory[k]
    if stack and stack.valid and not stack.valid_for_read then
      return stack
    end
  end
end

local inventories = function(entity)
  local get = entity.get_inventory
  local inventories = {}
  for k = 1, 10 do
    inventories[k] = get(k)
  end
  return inventories
end

local belt_connectible_type =
{
  ["transport-belt"] = 2,
  ["underground-belt"] = 4,
  ["splitter"] = 8,
  ["loader"] = 2,
  ["loader-1x1"] = 2,
}

local transport_lines = function(entity)
  local max_line_index = belt_connectible_type[entity.type]
  if not max_line_index then return {} end
  local get = entity.get_transport_line
  local inventories = {}
  for k = 1, max_line_index do
    inventories[k] = get(k)
  end
  return inventories
end

local is_cheat_mode = function(entity)
  return entity.type == "character" and entity.player and entity.player.cheat_mode
end

local can_player_spawn_drones = function(player)

  if not player.is_shortcut_toggled("construction-drone-toggle") then
    return
  end

  local count = player.get_item_count(names.units.construction_drone) - (data.request_count[player.index] or 0)
  return count > 0
end

local transfer_stack = function(destination, source_entity, stack)

  if source_entity.is_player() and source_entity.cheat_mode then
    destination.insert(stack)
    return stack.count
  end

  stack.count = math.min(stack.count, source_entity.get_item_count(stack.name))
  if stack.count == 0 then return 0 end
  local transferred = 0
  local insert = destination.insert
  local can_insert = destination.can_insert
  for k, inventory in pairs(inventories(source_entity)) do
    while true do
      local source_stack = inventory.find_item_stack(stack.name)
      if source_stack and source_stack.valid and source_stack.valid_for_read and can_insert(source_stack) then
        local inserted = insert(stack)
        transferred = transferred + inserted
        --count should always be greater than 0, otherwise can_insert would fail
        inventory.remove(stack)
      else
        break
      end
      if transferred >= stack.count then
        --print("Transferred: "..transferred)
        return transferred
      end
    end
  end
  --print("Transferred end: "..transferred)
  return transferred
end

local transfer_inventory = function(source, destination)

  local insert = destination.insert
  local remove = source.remove
  local can_insert = destination.can_insert
  for k = 1, #source do
    local stack = source[k]
    if stack and stack.valid and stack.valid_for_read and can_insert(stack) then
      local remove_stack = {name = stack.name, count = insert(stack)}
      if remove_stack.count > 0 then
        remove(remove_stack)
      end
    end
  end
end

local transfer_transport_line = function(transport_line, destination)
  local insert = destination.insert
  local remove = transport_line.remove_item
  local can_insert = destination.can_insert
  for k = #transport_line, 1, -1 do
    local stack = transport_line[k]
    if stack and stack.valid and stack.valid_for_read and can_insert(stack) then
      local remove_stack = {name = stack.name, count = insert(stack)}
      --count should always be greater than 0, otherwise can_insert would fail
      remove(remove_stack)
    end
  end
end

local rip_inventory = function(inventory, list)
  if inventory.is_empty() then return end
  for name, count in pairs (inventory.get_contents()) do
    list[name] = (list[name] or 0) + count
  end
end

local contents = function(entity)
  local contents = {}

  local get_inventory = entity.get_inventory
  for k = 1, 10 do
    local inventory = get_inventory(k)
    if inventory then
      rip_inventory(inventory, contents)
    else
      break
    end
  end

  local max_line_index = belt_connectible_type[entity.type]
  if max_line_index then
    local get_transport_line = entity.get_transport_line
    for k = 1, max_line_index do
      local transport_line = get_transport_line(k)
      if transport_line then
        for name, count in pairs (transport_line.get_contents()) do
          contents[name] = (contents[name] or 0) + count
        end
      else
        break
      end
    end
  end

  return contents
end

local take_product_stacks = function(inventory, products)
  local insert = inventory.insert
  local to_spill = {}
  if products then
    for k, product in pairs (products) do
      local stack = stack_from_product(product)
      if stack then
        local leftover = stack.count - insert(stack)
        if leftover > 0 then
          to_spill[stack.name] = (to_spill[stack.name] or 0) + leftover
        end
      end
    end
  end
end

local destroy_param =
{
  raise_destroy = true
}

local make_path_request = function(drone_data, player, target)
  local prototype = get_prototype(names.units.construction_drone)

  local path_id = player.surface.request_path
  {
    bounding_box = prototype.collision_box,
    collision_mask = prototype.collision_mask_with_flags,
    start = player.position,
    goal = target.position,
    force = player.force,
    radius = target.get_radius() + 4,
    pathfind_flags = {},
    can_open_gates = true,
    path_resolution_modifier = 0,
  }

  data.path_requests[path_id] = drone_data

  local index = player.index
  data.request_count[index] = (data.request_count[index] or 0) + 1

end

remote.add_interface("construction_drone",
{
  set_debug = function(bool)
    data.debug = bool
  end,
  dump = function()
  --print(serpent.block(data))
  end
})

local drone_stack_capacity
local get_drone_stack_capacity = function(force)
  if drone_stack_capacity then return drone_stack_capacity end
  drone_stack_capacity = game.entity_prototypes[proxy_name].get_inventory_size(defines.inventory.chest)
  return drone_stack_capacity
end

local get_build_item = function(prototype, player)
  local items = prototype.items_to_place_this
  for k, item in pairs(items) do
    if player.get_item_count(item.name) >= item.count or player.cheat_mode then
      return item
    end
  end
end

local validate = function(entities)
  for k, entity in pairs (entities) do
    if not entity.valid then
      entities[k] = nil
    end
  end
  return entities
end

local update_drone_sticker

local process_drone_command

local make_player_drone = function(player)
  local position = player.surface.find_non_colliding_position(names.units.construction_drone, player.position, 5, 0.5, false)
  if not position then return end

  local removed = player.remove_item({name = names.units.construction_drone, count = 1})
  if removed == 0 then return end

  local drone = player.surface.create_entity
  {
    name = names.units.construction_drone,
    position = position,
    force = player.force
  }

  script.register_on_entity_destroyed(drone)

  return drone
end

local process_return_to_player_command

local set_drone_order = function(drone, drone_data)
  drone.ai_settings.path_resolution_modifier = 0
  drone.ai_settings.do_separation = true
  data.drone_commands[drone.unit_number] = drone_data
  drone_data.entity = drone
  return process_drone_command(drone_data)
end

local find_a_player = function(drone_data)
  local entity = drone_data.entity
  if not (entity and entity.valid) then return end

  if drone_data.player and drone_data.player.valid and drone_data.player.surface == entity.surface   then
    return true
  end

  local closest
  local min_distance = math.huge
  for k, player in pairs (game.connected_players) do
    if player.surface == entity.surface then
      local distance = distance(player.position, entity.position)
      if distance < min_distance then
        closest = player
        min_distance = distance
      end
    end
  end

  if closest then
    drone_data.player = closest
    return true
  end
end

local drone_wait = function(drone_data, ticks)
  local drone = drone_data.entity
  if not (drone and drone.valid) then return end
  drone.set_command
  {
    type = defines.command.stop,
    ticks_to_wait = ticks,
    distraction = defines.distraction.none,
    radius = get_radius(drone)
  }
end

local set_drone_idle = function(drone)
  if not (drone and drone.valid) then return end
--print("Setting drone idle")
  local drone_data = data.drone_commands[drone.unit_number]


  if drone_data then
    if find_a_player(drone_data) then
      process_return_to_player_command(drone_data)
      return
    else
      return drone_wait(drone_data, random(200, 400))
    end
  end

  set_drone_order(drone, {})

end


local check_ghost = function(entity, player)
  if not (entity and entity.valid) then return end

  if data.already_targeted[entity.unit_number] then return end

  local force = entity.force
  local surface = entity.surface
  local position = entity.position

  local item = get_build_item(entity.ghost_prototype, player)

--print("Checking ghost "..entity.ghost_name..random())

  if not item then
    return
  end

  local count = 0
  local extra_targets = {}
  local extra
  if entity.name == "tile-ghost" then
    extra = surface.find_entities_filtered{type = tile_ghost_type, position = position, radius = 3}
  else
    extra = surface.find_entities_filtered{ghost_name = entity.ghost_name, position = position, radius = 5}
  end
  for k, ghost in pairs (extra) do
    if count >= 8 then break end
    local unit_number = ghost.unit_number
    local should_check = not data.already_targeted[unit_number]
    if should_check then
      data.already_targeted[unit_number] = true
      extra_targets[unit_number] = ghost
      count = count + 1
    end
  end

  item.count = count

  local target = surface.get_closest(player.position, extra_targets)
  extra_targets[target.unit_number] = nil

  local drone_data =
  {
    player = player,
    order = drone_orders.construct,
    pickup = {stack = item},
    target = target,
    item_used_to_place = item.name,
    extra_targets = extra_targets
  }

  make_path_request(drone_data, player, target)
end

local check_upgrade = function(entity, player)

  if not (entity and entity.valid) then
    return
  end

  if not entity.to_be_upgraded() then
    return
  end

  local index = unique_index(entity)
  if data.already_targeted[index] then
    return
  end

  local upgrade_prototype = entity.get_upgrade_target()
  if not upgrade_prototype then
    return
  end

  local surface = entity.surface
  local force = entity.force
  local item = get_build_item(upgrade_prototype, player)
  if not item then return end

  local count = 0

  local extra_targets = {}
  for k, nearby in pairs (surface.find_entities_filtered{name = entity.name, position = entity.position, radius = 8, to_be_upgraded = true}) do
    if count >= 6 then break end
    local nearby_index = nearby.unit_number
    local should_check = not data.already_targeted[nearby_index]
    if should_check then
      data.already_targeted[nearby_index] = true
      extra_targets[nearby_index] = nearby
      count = count + 1
    end
  end

  local target = surface.get_closest(player.position, extra_targets)
  extra_targets[target.unit_number] = nil

  local drone_data =
  {
    player = player,
    order = drone_orders.upgrade,
    pickup = {stack = {name = item.name, count = count}},
    target = target,
    extra_targets = extra_targets,
    upgrade_prototype = upgrade_prototype,
    item_used_to_place = item.name
  }

  make_path_request(drone_data, player, target)
end

local check_proxy = function(entity, player)
  if not (entity and entity.valid) then
    return
  end

  local target = entity.proxy_target
  if not (target and target.valid) then
    return
  end

  if data.already_targeted[unique_index(entity)] then
    return
  end

  local items = entity.item_requests

  local position = entity.position
  for name, count in pairs (items) do
    if player.get_item_count(name) > 0 or player.cheat_mode then
      local drone_data =
      {
        player = player,
        order = drone_orders.request_proxy,
        pickup = {stack = {name = name, count = count}},
        target = entity
      }
      make_path_request(drone_data, player, entity)
    end
  end

  data.already_targeted[unique_index(entity)] = true
end

local check_cliff_deconstruction = function(entity, player)
  local surface = entity.surface
  local position = entity.position

  local cliff_destroying_item = entity.prototype.cliff_explosive_prototype
  if not cliff_destroying_item then
    return
  end

  if player.get_item_count(cliff_destroying_item) == 0 and (not player.cheat_mode) then
    return
  end

  local drone_data =
  {
    player = player,
    order = drone_orders.cliff_deconstruct,
    target = entity,
    pickup = {stack = {name = cliff_destroying_item, count = 1}}
  }
  make_path_request(drone_data, player, entity)

  data.already_targeted[unique_index(entity)] = true

end

local check_deconstruction = function(entity, player)
  if not (entity and entity.valid) then return end
  if not entity.to_be_deconstructed() then return end

  local index = unique_index(entity)
  if data.already_targeted[index] then
    return
  end

  local force = player.force

  if not (entity.force == force or entity.force.name == "neutral" or entity.force.is_friend(force)) then
    return
  end

  if entity.type == cliff_type then
    return check_cliff_deconstruction(entity, player)
  end

  local surface = entity.surface

  local sent = data.sent_deconstruction[index] or 0

  local capacity = get_drone_stack_capacity(force)
  local total_contents = contents(entity)
  local stack_sum = 0
  local items = game.item_prototypes
  for name, count in pairs (total_contents) do
    stack_sum = stack_sum + (count / items[name].stack_size)
  end
  local needed = math.ceil((stack_sum + 1) / capacity)
  needed = needed - sent

  if needed <= 1 then

    local extra_targets = {}
    local count = 10

    for k, nearby in pairs (surface.find_entities_filtered{name = entity.name, position = entity.position, radius = 8, to_be_deconstructed = true}) do
      if count <= 0 then break end
      local nearby_index = unique_index(nearby)
      local should_check = not data.already_targeted[nearby_index]
      if should_check then
        --nearby.surface.create_entity{name = "tutorial-flying-text", position = nearby.position, text = "  B"}
        data.already_targeted[nearby_index] = true
        data.sent_deconstruction[nearby_index] = (data.sent_deconstruction[nearby_index] or 0) + 1
        extra_targets[nearby_index] = nearby
        count = count - 1
      end
    end

    local target = surface.get_closest(player.position, extra_targets)
    if not target then return end

    extra_targets[unique_index(target)] = nil

    local drone_data =
    {
      player = player,
      order = drone_orders.deconstruct,
      target = target,
      extra_targets = extra_targets
    }

    make_path_request(drone_data, player, target)
    return

  end

  for k = 1, math.min(needed, 10, player.get_item_count(names.units.construction_drone)) do
    if not (entity and entity.valid) then break end
    local drone_data =
    {
      player = player,
      order = drone_orders.deconstruct,
      target = entity
    }
    make_path_request(drone_data, player, entity)
    sent = sent + 1
  end

  data.sent_deconstruction[index] = sent

  if sent >= needed then
    data.already_targeted[index] = true
  end
end

local repair_items
local get_repair_items = function()
  if repair_items then return repair_items end
  --Deliberately not 'local'
  repair_items = {}
  for name, item in pairs (game.item_prototypes) do
    if item.type == "repair-tool" then
      repair_items[name] = item
    end
  end
  return repair_items
end

local check_repair = function(entity, player)

  if not (entity and entity.valid) then return true end

  if entity.has_flag("not-repairable") then return end

  local health = entity.get_health_ratio()
  if not (health and health < 1) then return true end

  local index = unique_index(entity)
  if data.already_targeted[index] then
    return
  end

  local force = entity.force
  if not (force == player.force or player.force.get_friend(force)) then
    return
  end

  local repair_item
  local repair_items = get_repair_items()
  for name, item in pairs (repair_items) do
    if player.get_item_count(name) > 0 or player.cheat_mode then
      repair_item = item
      break
    end
  end

  if not repair_item then
    return
  end

  local drone_data =
  {
    player = player,
    order = drone_orders.repair,
    pickup = {stack = {name = repair_item.name, count = 1}},
    target = entity,
  }

  make_path_request(drone_data, player, entity)

  data.already_targeted[index] = true

end

local check_job = function(player, job)

  if job.type == drone_orders.construct then
    check_ghost(job.entity, player)
    return
  end

  if job.type == drone_orders.deconstruct then
    check_deconstruction(job.entity, player)
    return
  end

  if job.type == drone_orders.upgrade then
    check_upgrade(job.entity, player)
    return
  end

  if job.type == drone_orders.request_proxy then
    check_proxy(job.entity, player)
    return
  end

  if job.type == drone_orders.repair then
    check_repair(job.entity, player)
    return
  end

end

local ignored_types =
{
  "resource",
  "corpse",
  "beam",
  "flying-text",
  "explosion",
  "smoke-with-trigger",
  "stream",
  "fire-flame",
  "particle-source",
  "projectile",
  "sticker",
  "speech-bubble"
}

local scan_for_nearby_jobs = function(player, area)
  --game.print(serpent.line(area))
  --player.surface.create_entity{name = "tutorial-flying-text", position = {area[1][1], area[1][2]}, text = "["}
  --player.surface.create_entity{name = "tutorial-flying-text", position = {area[2][1], area[2][2]}, text = "]"}
  local job_queue = data.job_queue

  local player_index = player.index

  if not player.connected then
    job_queue[player_index] = nil
    return
  end

  if not player.is_shortcut_toggled("construction-drone-toggle") then
    job_queue[player_index] = nil
    return
  end

  local player_queue = job_queue[player.index]
  if not player_queue then
    player_queue = {}
    job_queue[player_index] = player_queue
  end

  local already_targeted = data.already_targeted

  local entities = player.surface.find_entities_filtered
  {
    area = area,
    type = ignored_types,
    invert = true
  }

  local unique_index = unique_index
  local check_entity = function(entity)
    local index = unique_index(entity)
    if already_targeted[index] then return end
    local name = entity.name
    --entity.surface.create_entity{name = "flying-text", position = entity.position, text = "!"}
    if name == "entity-ghost" or name == "tile-ghost" then
      player_queue[index] =
      {
        type = drone_orders.construct,
        entity = entity
      }
      return true
    end

    if name == "item-request-proxy" then
      player_queue[index] =
      {
        type = drone_orders.request_proxy,
        entity = entity
      }
      return true
    end

    if entity.to_be_deconstructed() then
      player_queue[index] =
      {
        type = drone_orders.deconstruct,
        entity = entity
      }
      return true
    end

    if (entity.get_health_ratio() or 1) < 1 then
      player_queue[index] =
      {
        type = drone_orders.repair,
        entity = entity
      }
      return true
    end

    if entity.to_be_upgraded() then
      player_queue[index] =
      {
        type = drone_orders.upgrade,
        entity = entity
      }
      return true
    end

  end

  for k, entity in pairs (entities) do
    check_entity(entity)
  end

end

local check_player_jobs = function(player)

  if not can_player_spawn_drones(player) then return end

  local queue = data.job_queue[player.index]
  if not queue then return end

  local count = math.min(5, player.get_item_count(names.units.construction_drone) - (data.request_count[player.index] or 0))

  for k = 1, count do
    local index, job = next(queue)
    if not index then
      return
    end

    check_job(player, job)
    queue[index] = nil
  end

end

local search_offsets = {}
local search_refresh = nil

local setup_search_offsets = function(div)
  local r = 60 / div

  search_offsets = {}

  for y = -div, div - 1 do
    for x = -div, div - 1 do
      local area = {{x * r, y * r}, {(x + 1) * r, (y + 1) * r}}
      table.insert(search_offsets, area)
    end
  end

  table.sort(search_offsets, function(a, b) return distance(a[1], {0,0}) < distance(b[1], {0,0}) end)
  search_refresh = #search_offsets
end

local check_search_queue = function()
  local index, search_data = next(data.search_queue)
  if not index then return end
  data.search_queue[index] = nil
  local player_index = search_data.player_index
  local player = game.get_player(player_index)
  if not player then return end
  local index = search_data.area_index
  local area = search_offsets[index]
  if not area then return end
  local position = player.position
  local search_area = {{area[1][1] + position.x, area[1][2] + position.y}, {area[2][1] + position.x, area[2][2] + position.y}}
  scan_for_nearby_jobs(player, search_area)
end

local insert = table.insert
local schedule_new_searches = function()

  local queue = data.search_queue
  if next(queue) then return end

  for k, player in pairs (game.connected_players) do
    local index = player.index
    if can_player_spawn_drones(player) and not next(data.job_queue[index] or {}) then
      for i, v in pairs(search_offsets) do
        insert(queue,
        {
          player_index = index,
          area_index = i
        })
      end
    end
  end

end

local on_tick = function(event)

  check_search_queue()

  for k, player in pairs (game.connected_players) do
    check_player_jobs(player)
  end

  if event.tick % search_refresh == 0 then
    schedule_new_searches()
  end

end

local get_build_time = function(drone_data)
  return random(15, 25)
end

local clear_extra_targets = function(drone_data)
  if not drone_data.extra_targets then return end

  local targets = validate(drone_data.extra_targets)
  local order = drone_data.order

  for k, entity in pairs (targets) do
    data.already_targeted[unique_index(entity)] = nil
  end

  if order == drone_orders.deconstruct or order == drone_orders.cliff_deconstruct then
    for index, entity in pairs (targets) do
      local index = unique_index(entity)
      data.sent_deconstruction[index] = (data.sent_deconstruction[index] or 1) - 1
    end
  end

end

local clear_target = function(drone_data)

  local target = drone_data.target
  if not (target and target.valid) then
    return
  end

  local order = drone_data.order
  local index = unique_index(target)

  if order == drone_orders.deconstruct or order == drone_orders.cliff_deconstruct then
    data.sent_deconstruction[index] = (data.sent_deconstruction[index] or 1) - 1
  end

  data.already_targeted[index] = nil

end

local cancel_drone_order = function(drone_data, on_removed)
  local drone = drone_data.entity
  if not (drone and drone.valid) then return end
  local unit_number = drone.unit_number

--print("Drone command cancelled "..unit_number.." - "..game.tick)

  clear_target(drone_data)
  clear_extra_targets(drone_data)

  drone_data.pickup = nil
  drone_data.path = nil
  drone_data.dropoff = nil
  drone_data.order = nil
  drone_data.target = nil

  if not find_a_player(drone_data) then
    return drone_wait(drone_data, random(30, 300))
  end

  local stack = get_drone_first_stack(drone_data)
  if stack then
    if not on_removed then
    --print("Holding a stack, gotta go drop it off... "..unit_number)
      drone_data.dropoff = {stack = stack}
      return process_drone_command(drone_data)
    end
  end

  if not on_removed then
    set_drone_idle(drone)
  end

end

local floor = math.floor

local move_to_order_target = function(drone_data, target, range)

  local drone = drone_data.entity

  if drone.surface ~= target.surface then
    cancel_drone_order(drone_data)
    return
  end

  if in_construction_range(drone, target, range) then
    return true
  end

  drone.set_command
  {
    type = defines.command.go_to_location,
    destination_entity = target,
    radius = (target == drone_data.character and 1) or (get_radius(drone, range) + get_radius(target)),
    distraction = defines.distraction.none,
    pathfind_flags = drone_pathfind_flags
  }

end

local move_to_player = function(drone_data, player, range)

  local drone = drone_data.entity

  if drone.surface ~= player.surface then
    cancel_drone_order(drone_data)
    return
  end

  if distance(drone.position, player.position) < 1 then
    return true
  end

  drone.set_command
  {
    type = defines.command.go_to_location,
    destination_entity = player.character or nil,
    destination = (not player.character and player.position) or nil,
    radius = 1,
    distraction = defines.distraction.none,
    pathfind_flags = drone_pathfind_flags
  }

end

local insert = table.insert

local offsets =
{
  {0, 0},
  {0.25, 0},
  {0, 0.25},
  {0.25, 0.25},
}

update_drone_sticker = function(drone_data)

  local sticker = drone_data.sticker
  if sticker and sticker.valid then
    sticker.destroy()
    --Legacy
  end

  local renderings = drone_data.renderings
  if renderings then
    for k, v in pairs (renderings) do
      rendering.destroy(v)
    end
    drone_data.renderings = nil
  end

  local inventory = get_drone_inventory(drone_data)

  local contents = inventory.get_contents()

  if not next(contents) then return end

  local number = table_size(contents)

  local drone = drone_data.entity
  local surface = drone.surface
  local forces = {drone.force}

  local renderings = {}
  drone_data.renderings = renderings

  insert(renderings, rendering.draw_sprite
  {
    sprite = "utility/entity_info_dark_background",
    target = drone,
    surface = surface,
    forces = forces,
    only_in_alt_mode = true,
    target_offset = {0, -0.5},
    x_scale = 0.5,
    y_scale = 0.5,
  })

  if number == 1 then
    insert(renderings, rendering.draw_sprite
    {
      sprite = "item/"..next(contents),
      target = drone,
      surface = surface,
      forces = forces,
      only_in_alt_mode = true,
      target_offset = {0, -0.5},
      x_scale = 0.5,
      y_scale = 0.5,
    })
    return
  end

  local offset_index = 1

  for name, count in pairs (contents) do
    local offset = offsets[offset_index]
    insert(renderings, rendering.draw_sprite
    {
      sprite = "item/"..name,
      target = drone,
      surface = surface,
      forces = forces,
      only_in_alt_mode = true,
      target_offset = {-0.125 + offset[1], -0.5 + offset[2]},
      x_scale = 0.25,
      y_scale = 0.25,
    })
    offset_index = offset_index + 1
  end


end

local process_pickup_command = function(drone_data)
--print("Procesing pickup command")

  local player = drone_data.player
  if not (player and player.valid) then
  --print("Character for pickup was not valid")
    return cancel_drone_order(drone_data)
  end

  if not move_to_player(drone_data, player, ranges.interact) then
    return
  end


--print("Pickup chest in range, picking up item")

  local stack = drone_data.pickup.stack
  local drone_inventory = get_drone_inventory(drone_data)

  transfer_stack(drone_inventory, player, stack)

  update_drone_sticker(drone_data)

  drone_data.pickup = nil

  return process_drone_command(drone_data)

end

local get_dropoff_stack = function(drone_data)
  local stack = drone_data.dropoff.stack
  if stack and stack.valid and stack.valid_for_read then return stack end
  return get_drone_first_stack(drone_data)
end

local process_dropoff_command = function(drone_data)

  local drone = drone_data.entity
--print("Procesing dropoff command. "..drone.unit_number)

  if drone_data.player then
    return process_return_to_player_command(drone_data)
  end

  find_a_player(drone_data)

end

local unit_move_away = function(unit, target, multiplier)
  local multiplier = multiplier or 1
  local r = (get_radius(target) + get_radius(unit)) * (1 + (random() * 4))
  r = r * multiplier
  local position = {x = nil, y = nil}
  if unit.position.x > target.position.x then
    position.x = unit.position.x + r
  else
    position.x = unit.position.x - r
  end
  if unit.position.y > target.position.y then
    position.y = unit.position.y + r
  else
    position.y = unit.position.y - r
  end
  unit.speed = unit.prototype.speed * (0.95 + (random() / 10))
  unit.set_command
  {
    type = defines.command.go_to_location,
    destination = position,
    radius = 2
  }
end

local unit_clear_target = function(unit, target)
  local r = get_radius(unit) + get_radius(target) + 1
  local position = {x = true, y = true}
  if unit.position.x > target.position.x then
    position.x = unit.position.x + r
  else
    position.x = unit.position.x - r
  end
  if unit.position.y > target.position.y then
    position.y = unit.position.y + r
  else
    position.y = unit.position.y - r
  end
  unit.speed = unit.prototype.speed
  local non_colliding_position = unit.surface.find_non_colliding_position(unit.name, position, 0, 0.5)
  unit.set_command
  {
    type = defines.command.go_to_location,
    destination = position,
    radius = 1
  }

end

local get_extra_target = function(drone_data)
  if not drone_data.extra_targets then return end
  drone_data.extra_targets = validate(drone_data.extra_targets)

  local any = next(drone_data.extra_targets)
  if not any then
    drone_data.extra_targets = nil
    return
  end

  local next_target = drone_data.entity.surface.get_closest(drone_data.entity.position, drone_data.extra_targets)
  if next_target then
    drone_data.target = next_target
    drone_data.extra_targets[unique_index(next_target)] = nil
    return next_target
  end
end

local revive_param = {return_item_request_proxy = true, raise_revive = true}
local process_construct_command = function(drone_data)
--print("Processing construct command")
  local target = drone_data.target
  if not (target and target.valid) then
    return cancel_drone_order(drone_data)
  end

  local drone_inventory = get_drone_inventory(drone_data)
  if drone_inventory.get_item_count(drone_data.item_used_to_place) == 0 then
    return cancel_drone_order(drone_data)
  end

  if not move_to_order_target(drone_data, target, ranges.interact) then
    return
  end

  local drone = drone_data.entity
  local position = target.position

  local index = unique_index(target)
  local success, entity, proxy = target.revive(revive_param)
  if not success then
    if target.valid then
      drone_wait(drone_data, 30)
    --print("Some idiot might be in the way too ("..drone.unit_number.." - "..game.tick..")")
      local radius = get_radius(target)
      for k, unit in pairs (target.surface.find_entities_filtered{type = "unit", position = position, radius = radius}) do
      --print("Telling idiot to MOVE IT ("..drone.unit_number.." - "..game.tick..")")
        unit_clear_target(unit, target)
      end
    end
    return
  end
  data.already_targeted[index] = nil


  drone_inventory.remove{name = drone_data.item_used_to_place, count = 1}
  update_drone_sticker(drone_data)

  drone_data.target = get_extra_target(drone_data)

  local build_time = get_build_time(drone_data)
  local orientation, offset = get_beam_orientation(drone.position, position)
  drone.orientation = orientation
  drone.surface.create_entity
  {
    name = beams.build,
    source = drone,
    target = entity and entity.valid and entity,
    target_position = position,
    position = position,
    force = drone.force,
    duration = build_time - 5,
    source_offset = offset
  }
  return drone_wait(drone_data, build_time)
end

local process_failed_command = function(drone_data)

  local drone = drone_data.entity

  local modifier = drone.ai_settings.path_resolution_modifier

  if modifier <= 3 then
    drone.ai_settings.path_resolution_modifier = modifier + 1
    return drone_wait(drone_data, 107)
  end

  drone.ai_settings.path_resolution_modifier = 0
  cancel_drone_order(drone_data, true)
  process_return_to_player_command(drone_data, true)

end

local process_deconstruct_command = function(drone_data)
--print("Processing deconstruct command")
  local target = drone_data.target
  if not (target and target.valid) then
    return cancel_drone_order(drone_data)
  end

  local drone = drone_data.entity

  if not target.to_be_deconstructed() then
    return cancel_drone_order(drone_data)
  end

  if not move_to_order_target(drone_data, target, ranges.interact) then
    return
  end

  local drone_inventory = get_drone_inventory(drone_data)

  local index = unique_index(target)
  local unit_number = target.unit_number

  local drone = drone_data.entity
  if not drone_data.beam then
    local build_time = get_build_time(drone_data)
    local orientation, offset = get_beam_orientation(drone.position, target.position)
    drone.orientation = orientation
    drone_data.beam = drone.surface.create_entity
    {
      name = beams.deconstruction,
      source = drone,
      target_position = target.position,
      position = drone.position,
      force = drone.force,
      duration = build_time - 5,
      source_offset = offset
    }
    return drone_wait(drone_data, build_time)
  else
    drone_data.beam = nil
  end

  local tiles
  if target.type == tile_deconstruction_proxy then
    tiles =
    {
      {
        name = target.surface.get_hidden_tile(target.position) or "grass-1",
        position = target.position

      }
    }
  end

  local mined = target.mine
  {
    inventory = drone_inventory,
    force = false,
    raise_destroyed = true
  }
  data.already_targeted[index] = nil

  if mined then
    data.sent_deconstruction[index] = nil
  else
    update_drone_sticker(drone_data)
    if drone_inventory.is_empty() then
      return drone_wait(drone_data, 300)
    end
    cancel_drone_order(drone_data)
    return
  end

  if tiles then
    drone.surface.set_tiles(tiles, true, false, false, true)
  end

  local target = get_extra_target(drone_data)
  if target then
    drone_data.target = target
  else
    drone_data.dropoff = {}
  end

  update_drone_sticker(drone_data)
  return process_drone_command(drone_data)
end

local process_repair_command = function(drone_data)
--print("Processing repair command")
  local target = drone_data.target

  if not (target and target.valid) then
    return cancel_drone_order(drone_data)
  end

  if target.get_health_ratio() == 1 then
  --print("Target is fine... give up on healing him")
    return cancel_drone_order(drone_data)
  end


  if not move_to_order_target(drone_data, target, ranges.interact) then
    return
  end


  local drone = drone_data.entity
  local drone_inventory = get_drone_inventory(drone_data)
  local stack
  for name, prototype in pairs (get_repair_items()) do
    stack = drone_inventory.find_item_stack(name)
    if stack then break end
  end

  if not stack then
  --print("I don't have a repair item... get someone else to do it")
    return cancel_drone_order(drone_data)
  end

  local health = target.health
  local repair_speed = game.item_prototypes[stack.name].speed
  if not repair_speed then
  --print("WTF, maybe some migration?")
    return cancel_drone_order(drone_data)
  end

  local ticks_to_repair = random(20, 30)
  local repair_cycles_left = math.ceil((target.prototype.max_health - target.health) / repair_speed)
  local max_left = math.ceil(stack.durability / repair_speed)
  ticks_to_repair = math.min(ticks_to_repair, repair_cycles_left)
  ticks_to_repair = math.min(ticks_to_repair, max_left)

  local repair_amount = (repair_speed * ticks_to_repair)

  target.health = target.health + repair_amount
  stack.drain_durability(repair_amount)

  if not stack.valid_for_read then
  --print("Stack expired, someone else will take over")
    return cancel_drone_order(drone_data)
  end

  local orientation, offset = get_beam_orientation(drone.position, target.position)
  drone.orientation = orientation
  drone.surface.create_entity
  {
    name = beams.build,
    source = drone,
    target = target,
    position = drone.position,
    force = drone.force,
    duration = ticks_to_repair,
    source_offset = offset
  }

  return drone_wait(drone_data, ticks_to_repair)
end

local process_upgrade_command = function(drone_data)
--print("Processing upgrade command")

  local target = drone_data.target
  if not (target and target.valid and target.to_be_upgraded()) then
    return cancel_drone_order(drone_data)
  end

  local drone_inventory = get_drone_inventory(drone_data)
  if drone_inventory.get_item_count(drone_data.item_used_to_place) == 0 then
    return cancel_drone_order(drone_data)
  end

  local drone = drone_data.entity

  if not move_to_order_target(drone_data, target, ranges.interact) then
    return
  end

  local surface = drone.surface
  local prototype = drone_data.upgrade_prototype
  local original_name = target.name
  local entity_type = target.type
  local index = unique_index(target)
  local neighbour = entity_type == "underground-belt" and target.neighbours
  local type = entity_type == "underground-belt" and target.belt_to_ground_type or (entity_type == "loader" or entity_type == "loader-1x1") and target.loader_type
  local position = target.position

  surface.create_entity
  {
    name = prototype.name,
    position = position,
    direction = target.direction,
    fast_replace = true,
    force = target.force,
    spill = false,
    type = type or nil,
    raise_built = true
  }

  data.already_targeted[index] = nil

  get_drone_inventory(drone_data).remove({name = drone_data.item_used_to_place})

  local drone_inventory = get_drone_inventory(drone_data)
  local products = get_prototype(original_name).mineable_properties.products

  take_product_stacks(drone_inventory, products)


  if neighbour and neighbour.valid then
  --print("Upgrading neighbour")
    local type = neighbour.type == "underground-belt" and neighbour.belt_to_ground_type
    local neighbour_index = unique_index(neighbour)
    surface.create_entity
    {
      name = prototype.name,
      position = neighbour.position,
      direction = neighbour.direction,
      fast_replace = true,
      force = neighbour.force,
      spill = false,
      type = type or nil,
      raise_built = true
    }
    data.already_targeted[neighbour_index] = nil
    take_product_stacks(drone_inventory, products)
  end

  local target = get_extra_target(drone_data)
  if target then
    drone_data.target = target
  else
    drone_data.dropoff = {}
  end

  update_drone_sticker(drone_data)
  local drone = drone_data.entity
  local build_time = get_build_time(drone_data)
  local orientation, offset = get_beam_orientation(drone.position, position)
  drone.orientation = orientation
  drone.surface.create_entity
  {
    name = beams.build,
    source = drone,
    target_position = position,
    position = drone.position,
    force = drone.force,
    duration = build_time - 5,
    source_offset = offset
  }
  return drone_wait(drone_data, build_time)
end

local process_request_proxy_command = function(drone_data)
--print("Processing request proxy command")

  local target = drone_data.target
  if not (target and target.valid) then
    return cancel_drone_order(drone_data)
  end

  local proxy_target = target.proxy_target
  if not (proxy_target and proxy_target.valid) then
    return cancel_drone_order(drone_data)
  end

  local drone = drone_data.entity

  local drone_inventory = get_drone_inventory(drone_data)
  local find_item_stack = drone_inventory.find_item_stack
  local requests = target.item_requests

  local stack
  for name, count in pairs(requests) do
    stack = find_item_stack(name)
    if stack then break end
  end

  if not stack then
  --print("We don't have anything to offer, abort")
    return cancel_drone_order(drone_data)
  end

  if not move_to_order_target(drone_data, proxy_target, ranges.interact) then
    return
  end

--print("We are in range, and we have what he wants")

  local stack_name = stack.name
  local position = target.position
  local inserted = proxy_target.insert(stack)
  if inserted == 0 then
  --print("Can't insert anything anyway, kill the proxy")
    target.destroy()
    return cancel_drone_order(drone_data)
  end
  drone_inventory.remove({name = stack_name, count = inserted})
  requests[stack_name] = requests[stack_name] - inserted
  if requests[stack_name] <= 0 then
    requests[stack_name] = nil
  end

  if not next(requests) then
    target.destroy()
  else
    target.item_requests = requests
  end

  local build_time = get_build_time(drone_data)
  local orientation, offset = get_beam_orientation(drone.position, position)
  drone.orientation = orientation
  drone.surface.create_entity
  {
    name = beams.build,
    source = drone,
    target_position = position,
    position = drone.position,
    force = drone.force,
    duration = build_time - 5,
    source_offset = offset
  }

  update_drone_sticker(drone_data)

  return drone_wait(drone_data, build_time)
end

local process_construct_tile_command = function(drone_data)
--print("Processing construct tile command")
  local target = drone_data.target
  if not (target and target.valid) then
    return cancel_drone_order(drone_data)
  end

  local drone_inventory = get_drone_inventory(drone_data)
  if drone_inventory.get_item_count(drone_data.item_used_to_place) == 0 then
    return cancel_drone_order(drone_data)
  end

  local drone = drone_data.entity

  if not move_to_order_target(drone_data, target, ranges.interact) then
    return
  end

  local position = target.position
  local surface = target.surface

  local tile = surface.get_tile(position.x, position.y)
  local current_prototype = tile.prototype
  local products = current_prototype.mineable_properties.products
  local target_tile_name = target.ghost_name

  surface.set_tiles({{name = target_tile_name, position = position}}, true, false, false, true)

  if surface.get_tile(position).name ~= current_prototype.name then
    --was successful
    local drone_inventory = get_drone_inventory(drone_data)
    drone_inventory.remove({name = drone_data.item_used_to_place, count = 1})

    local insert = drone_inventory.insert
    if products then
      for k, product in pairs (products) do
        local stack = stack_from_product(product)
        if stack then
          insert(stack)
        end
      end
      drone_data.dropoff = {}
    end
  end

  update_drone_sticker(drone_data)
  local drone = drone_data.entity

  drone_data.target = get_extra_target(drone_data)

  local build_time = get_build_time(drone_data)
  local orientation, offset = get_beam_orientation(drone.position, position)
  drone.orientation = orientation
  drone.surface.create_entity
  {
    name = beams.build,
    source = drone,
    target_position = position,
    position = drone.position,
    force = drone.force,
    duration = build_time - 5,
    source_offset = offset
  }
  return drone_wait(drone_data, build_time)
end

local process_deconstruct_cliff_command = function(drone_data)
--print("Processing deconstruct cliff command")
  local target = drone_data.target

  if not (target and target.valid) then
  --print("Target cliff was not valid. ")
    return cancel_drone_order(drone_data)
  end

  local drone = drone_data.entity

  if not move_to_order_target(drone_data, target, ranges.interact) then
    return
  end

  if not drone_data.beam then
    local drone = drone_data.entity
    local build_time = get_build_time(drone_data)
    local orientation, offset = get_beam_orientation(drone.position, target.position)
    drone.orientation = orientation
    drone.surface.create_entity
    {
      name = beams.deconstruction,
      source = drone,
      target_position = target.position,
      position = drone.position,
      force = drone.force,
      duration = build_time,
      source_offset = offset
    }
    drone_data.beam = true
    return drone_wait(drone_data, build_time)
  else
    drone_data.beam = nil
  end
  local index = unique_index(target)
  get_drone_inventory(drone_data).remove{name = target.prototype.cliff_explosive_prototype, count = 1}
  target.surface.create_entity{name = "ground-explosion", position = util.center(target.bounding_box)}
  target.destroy()
  data.already_targeted[index] = nil
--print("Cliff destroyed, heading home bois. ")
  update_drone_sticker(drone_data)

  return set_drone_idle(drone)
end

local directions =
{
  [defines.direction.north] = {0, -1},
  [defines.direction.northeast] = {1, -1},
  [defines.direction.east] = {1, 0},
  [defines.direction.southeast] = {1, 1},
  [defines.direction.south] = {0, 1},
  [defines.direction.southwest] = {-1, 1},
  [defines.direction.west] = {-1, 0},
  [defines.direction.northwest] = {-1, -1},
}

process_return_to_player_command = function(drone_data, force)

--print("returning to dude")

  local player = drone_data.player
  if not (player and player.valid) then
    return cancel_drone_order(drone_data)
  end

  if not (force or move_to_player(drone_data, player, ranges.return_to_character)) then
    return
  end

  local inventory = get_drone_inventory(drone_data)
  transfer_inventory(inventory, player)

  if not inventory.is_empty() then
    drone_wait(drone_data, random(18, 24))
    return
  end

  if player.insert({name = names.units.construction_drone, count = 1}) == 0 then
    drone_wait(drone_data, random(18, 24))
    return
  end

  cancel_drone_order(drone_data, true)

  local unit_number = drone_data.entity.unit_number

  local proxy_chest = data.proxy_chests[unit_number]
  if proxy_chest then
    proxy_chest.destroy()
    data.proxy_chests[unit_number] = nil
  end
  data.drone_commands[unit_number] = nil

  drone_data.entity.destroy()

end


process_drone_command = function(drone_data, result)

  local drone = drone_data.entity
  if not (drone and drone.valid) then
    return
  end

  if drone_data.player and drone_data.player.valid and drone_data.player.character then
    drone.speed = drone_data.player.character_running_speed * 1.2
  else
    drone.speed = 1
  end

  if (result == defines.behavior_result.fail) then
  --print("Fail")
    return process_failed_command(drone_data)
  end

  if drone_data.pickup then
  --print("Pickup")
    return process_pickup_command(drone_data)
  end

  if drone_data.dropoff then
  --print("Dropoff")
    return process_dropoff_command(drone_data)
  end

  if drone_data.order == drone_orders.construct then
  --print("Construct")
    return process_construct_command(drone_data)
  end

  if drone_data.order == drone_orders.deconstruct then
  --print("Deconstruct")
    return process_deconstruct_command(drone_data)
  end

  if drone_data.order == drone_orders.repair then
  --print("Repair")
    return process_repair_command(drone_data)
  end

  if drone_data.order == drone_orders.upgrade then
  --print("Upgrade")
    return process_upgrade_command(drone_data)
  end

  if drone_data.order == drone_orders.request_proxy then
  --print("Request proxy")
    return process_request_proxy_command(drone_data)
  end

  if drone_data.order == drone_orders.cliff_deconstruct then
  --print("Cliff Deconstruct")
    return process_deconstruct_cliff_command(drone_data)
  end

  find_a_player(drone_data)

  if drone_data.player then
    return process_return_to_player_command(drone_data)
  end

  --game.print("Nothin")
  return set_drone_idle(drone)
end

local on_ai_command_completed = function(event)
  local drone_data = data.drone_commands[event.unit_number]
  if drone_data then
  --print("Drone command complete event: "..event.unit_number.." = "..tostring(result ~= defines.behavior_result.fail))
    return process_drone_command(drone_data, event.result)
  end
end

local on_entity_removed = function(event)

  local unit_number
  local entity = event.entity
  if entity and entity.valid then
    unit_number = entity.unit_number
  else
    unit_number = event.unit_number
  end

  if not unit_number then return end

  local drone_data = data.drone_commands[unit_number]
  if drone_data then
    cancel_drone_order(drone_data, true)
  end

  local proxy_chest = data.proxy_chests[unit_number]
  if proxy_chest and proxy_chest.valid then
  --print("Giving inventory buffer from proxy")
    local buffer = event.buffer
    if buffer and buffer.valid then
      local inventory = proxy_chest.get_inventory(defines.inventory.chest)
      if inventory and inventory.valid then
        for name, count in pairs (inventory.get_contents()) do
          buffer.insert{name = name, count = count}
        end
      end
    end
    proxy_chest.destroy()
  end

end

local on_player_created = function(event)
  local player = game.get_player(event.player_index)
  player.set_shortcut_toggled("construction-drone-toggle", true)
end

local on_entity_cloned = function(event)

  local destination = event.destination
  if not (destination and destination.valid) then return end

  local source = event.source
  if not (source and source.valid) then return end

  if destination.type == "unit" then
    local unit_number = source.unit_number
    if not unit_number then return end

    local drone_data = data.drone_commands[unit_number]
    if not drone_data then return end

    local new_data = util.copy(drone_data)
    set_drone_order(destination, new_data)
    return
  end

end

local prune_commands = function()
  for unit_number, drone_data in pairs (data.drone_commands) do
    if not (drone_data.entity and drone_data.entity.valid) then
      data.drone_commands[unit_number] = nil
      local proxy_chest = data.proxy_chests[unit_number]
      if proxy_chest then
        proxy_chest.destroy()
        data.proxy_chests[unit_number] = nil
      end
    end
  end
end

local on_script_path_request_finished = function(event)
  local drone_data = data.path_requests[event.id]
  if not drone_data then return end
  data.path_requests[event.id] = nil

  local player = drone_data.player
  if not (player and player.valid) then
    clear_target(drone_data)
    clear_extra_targets(drone_data)
    return
  end

  local index = player.index
  data.request_count[index] = (data.request_count[index] or 0) - 1

  if not event.path then
    clear_target(drone_data)
    clear_extra_targets(drone_data)
    return
  end

  local drone = make_player_drone(player)
  if not drone then
    clear_target(drone_data)
    clear_extra_targets(drone_data)
    return
  end


  set_drone_order(drone, drone_data)

end


local on_lua_shortcut = function(event)
  if event.prototype_name ~= "construction-drone-toggle" then return end
  local player = game.get_player(event.player_index)

  local enabled = player.is_shortcut_toggled("construction-drone-toggle")
  if enabled then
    player.set_shortcut_toggled("construction-drone-toggle", false)
    data.job_queue[player.index] = nil
    return
  end

  player.set_shortcut_toggled("construction-drone-toggle", true)
end

local on_runtime_mod_setting_changed = function()
  setup_search_offsets(settings.global["throttling"].value)
end

local lib = {}

lib.events =
{
  [defines.events.on_tick] = on_tick,

  [defines.events.on_entity_died] = on_entity_removed,
  [defines.events.on_robot_mined_entity] = on_entity_removed,
  [defines.events.on_player_mined_entity] = on_entity_removed,
  [defines.events.on_pre_ghost_deconstructed] = on_entity_removed,
  [defines.events.on_entity_destroyed] = on_entity_removed,

  [defines.events.on_player_created] = on_player_created,

  [defines.events.on_ai_command_completed] = on_ai_command_completed,
  [defines.events.on_entity_cloned] = on_entity_cloned,

  [defines.events.on_script_path_request_finished] = on_script_path_request_finished,
  [defines.events.on_lua_shortcut] = on_lua_shortcut,

  [defines.events.on_runtime_mod_setting_changed] = on_runtime_mod_setting_changed,
}

lib.on_load = function()
  data = global.construction_drone or data
  global.construction_drone = data

  on_runtime_mod_setting_changed()
end

lib.on_init = function()
  game.map_settings.steering.default.force_unit_fuzzy_goto_behavior = false
  game.map_settings.steering.moving.force_unit_fuzzy_goto_behavior = false
  game.map_settings.path_finder.use_path_cache = false
  global.construction_drone = global.construction_drone or data

  for k, player in pairs (game.players) do
    player.set_shortcut_toggled("construction-drone-toggle", true)
  end

  on_runtime_mod_setting_changed()
end

lib.on_configuration_changed = function()
  game.map_settings.path_finder.use_path_cache = false

  data.path_requests = data.path_requests or {}
  data.request_count = data.request_count or {}

  prune_commands()

  if not data.set_default_shortcut then
    data.set_default_shortcut = true
    for k, player in pairs (game.players) do
      player.set_shortcut_toggled("construction-drone-toggle", true)
    end
  end

  data.search_queue = data.search_queue or {}
  data.job_queue = data.job_queue or {}
  data.already_targeted = data.already_targeted or {}

end

return lib
