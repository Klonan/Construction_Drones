
local max = math.huge
local insert = table.insert
local remove = table.remove
local pairs = pairs
local beams = names.beams
local proxy_name = names.entities.construction_drone_proxy_chest
local drone_range = 80
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

local max_checks_per_tick = 2
local max_important_checks_per_tick = 5

local drone_pathfind_flags =
{
  allow_destroy_friendly_entities = false,
  cache = false,
  low_priority = false,
  prefer_straight_paths = true
}

local drone_orders =
{
  construct = 1,
  deconstruct = 2,
  repair = 3,
  upgrade = 4,
  request_proxy = 5,
  tile_construct = 6,
  tile_deconstruct = 7,
  cliff_deconstruct = 8,
  follow = 9,
  return_to_character = 10
}

local data =
{
  ghosts_to_be_checked = {},
  ghosts_to_be_checked_again = {},
  deconstructs_to_be_checked = {},
  deconstructs_to_be_checked_again = {},
  repair_to_be_checked = {},
  repair_to_be_checked_again = {},
  upgrade_to_be_checked = {},
  upgrade_to_be_checked_again = {},
  proxies_to_be_checked = {},
  tiles_to_be_checked = {},
  deconstruction_proxies_to_be_checked = {},
  drone_commands = {},
  targets = {},
  sent_deconstruction = {},
  debug = false,
  proxy_chests = {},
  characters = {},
  migrate_deconstructs = true,
  migrate_characters = true,
  path_requests = {},
  request_count = {}

}

local sin, cos = math.sin, math.cos

local get_beam_orientation = function(source_position, target_position)

    -- Angle in rads
    local angle = util.angle(target_position, source_position)

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

local add_character = function(character)
  if not (character and character.valid) then return end
  data.characters[unique_index(character)] = character
end

local get_characters = function()
  local characters = data.characters
  for k, character in pairs (characters) do
    if not character.valid then
      characters[k] = nil
    end
  end
  return characters
end

local can_character_spawn_drones = function(character)
  if character.vehicle then return end

  if character.allow_dispatching_robots then
    local network = character.logistic_network
    if network then
      if network.all_construction_robots > 0 then
        return
      end
    end
  end

  local count = character.get_item_count(names.units.construction_drone) - (data.request_count[character.unit_number] or 0)
  return count > 0
end

local abs = math.abs
local rect_dist = function(position_1, position_2)
  return abs(position_1.x - position_2.x) + abs(position_1.y - position_2.y)
end

local get_characters_for_entity = function(entity, optional_force, predicate)
  --matches force and surface
  local force = optional_force or entity.force
  local surface = entity.surface
  local new_characters = {}
  for k, character in pairs (get_characters()) do
    if character.force == force and character.surface == surface and can_character_spawn_drones(character) and (not predicate or predicate(character, entity)) then
      new_characters[k] = character
    end
  end
  return new_characters
end


local get_characters_in_distance = function(entity, optional_force)
  local origin = entity.position
  local predicate = function(character)
    return rect_dist(origin, character.position) <= drone_range
  end
  return get_characters_for_entity(entity, optional_force, predicate)
end

local get_character_for_job = function(entity, optional_force)
  local characters = get_characters_for_entity(entity, optional_force)

  if not next(characters) then return end

  local closest = entity.surface.get_closest(entity.position, characters)
  if rect_dist(closest.position, entity.position) > drone_range then return end

  return closest
end

local get_drone_radius = function()
  return 0.3
end

local print = function(string)
  if not data.debug then return end
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
  elseif type == tile_deconstruction_proxy then
    radius = 0
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
  return (((position_2.x - position_1.x) * (position_2.x - position_1.x)) + ((position_2.y - position_1.y) * (position_2.y - position_1.y))) ^ 0.5
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

local transfer_stack = function(destination, source_entity, stack)
  --print("Want: "..stack.count)
  --print("Have: "..source_entity.get_item_count(stack.name))
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
    get_transport_line = entity.get_transport_line
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

local take_all_content = function(inventory, target)

  if not (target and target.valid) then return end

  local type = target.type

  if type == "item-entity" then
    local stack = target.stack
    if stack and stack.valid_for_read and inventory.can_insert(stack) then
      local remove_stack = {name = stack.name, count = inventory.insert(stack)}
      target.remove_item(remove_stack)
    end
    return
  end

  if type == "inserter" then
    local stack = target.held_stack
    if stack and stack.valid_for_read and inventory.can_insert(stack) then
      local remove_stack = {name = stack.name, count = inventory.insert(stack)}
      target.remove_item(remove_stack)
    end
  end

  for k, target_inventory in pairs (inventories(target)) do
    transfer_inventory(target_inventory, inventory)
  end

  for k, transport_line in pairs (transport_lines(target)) do
    transfer_transport_line(transport_line, inventory)
  end
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

local mine_entity = function(inventory, target)
  take_all_content(inventory, target)
  if not (target and target.valid) then
    --Items on ground die when you remove the items...
    return true
  end
  if target.has_items_inside() then
  --print("Tried to take all the target items, but he still has some, ergo, we cant fit that many items.")
    return
  end
  
  --[[
    
    if not inventory.is_empty() then
      --Decided they only carry 1 stack now...
      return
    end
    ]]
    
    local prototype = target.prototype
    local position = target.position
    local surface = target.surface
    
    local products = prototype.mineable_properties.products
    
    if products then
      if products[1] and not inventory.can_insert(products[1]) then
        --We can't insert even 1 of the result products
        return
      end
    end

  local destroyed = target.destroy(destroy_param)

  if not destroyed then
  --print("He is still alive after destroying him, tough guy.")
    return false
  end

  for k, remains_prototype in pairs (prototype.remains_when_mined) do
    surface.create_entity{name = remains_prototype.name, position = position, force = "neutral"}
  end

  take_product_stacks(inventory, products)
  return true
end

local transfer_item = function(source, destination, name)
  local insert = destination.insert
  local find = source.find_item_stack
  while true do
    stack = find(name)
    if stack then
      local count = stack.count
      local taken = insert(stack)
      if taken >= count then
        stack.clear()
      else
        stack.count = count - taken
        return
      end
    else
      return
    end
  end
end

local make_path_request = function(drone_data, character, target)

  local prototype = game.entity_prototypes[names.units.construction_drone]

  local path_id = character.surface.request_path
  {
    bounding_box = prototype.collision_box,
    collision_mask = prototype.collision_mask_with_flags,
    start = character.position,
    goal = target.position,
    force = character.force,
    radius = target.get_radius() + 4,
    pathfind_flags = {},
    can_open_gates = true,
    path_resolution_modifier = 0,
  }

  data.path_requests[path_id] = drone_data

  local unit_number = character.unit_number
  data.request_count[unit_number] = (data.request_count[unit_number] or 0) + 1

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

local check_priority_list = function(list, other_list, check_function, count)
  while count > 0 do
    local index, entry = next(list)
    if index == nil then break end
    other_list[index] = entry
    list[index] = nil
    if check_function(entry) then
      other_list[index] = nil
    end
    count = count - 1
  end
  return count
end

local check_list = function(list, index, check_function, count)
  if count == 0 then return index end
  if not index then
    index = next(list)
  end
  if not index then return end
  while count > 0 do
    local this_index = index
    entry = list[this_index]
    --TODO maybe change the index when doing the extra target logic
    if not entry then return nil end
    index = next(list, this_index)
    if entry and check_function(entry) == true then
      list[this_index] = nil
    end
    count = count - 1
    if index == nil then break end
  end
  return index
end

local remove_from_list = function(list, index, global_index)
  if not list[index] then return global_index end
  if global_index and global_index == index then
    global_index = next(list, index)
  end
  list[index] = nil
  return global_index
end

local get_drone_stack_capacity = function(force)
  --Deliberately not local
  drone_stack_capacity = drone_stack_capacity or game.entity_prototypes[proxy_name].get_inventory_size(defines.inventory.chest)
  return drone_stack_capacity
end

local get_character_point = function(prototype, entity)
  local items = prototype.items_to_place_this

  local characters = get_characters_in_distance(entity)

  for k, character in pairs (characters) do
    for k, item in pairs(items) do
      if character.get_item_count(item.name) >= item.count then
        return character, item
      end
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

local make_character_drone = function(character)
  local position = character.surface.find_non_colliding_position(names.units.construction_drone, character.position, 5, 0.5, false)
  if not position then return end

  local removed = character.remove_item({name = names.units.construction_drone, count = 1})
  if removed == 0 then return end

  local drone = character.surface.create_entity{name = names.units.construction_drone, position = position, force = character.force}

  return drone
end

local process_return_to_character_command

local set_drone_order = function(drone, drone_data)
  drone.ai_settings.path_resolution_modifier = 0
  drone.ai_settings.do_separation = true
  data.drone_commands[drone.unit_number] = drone_data
  drone_data.entity = drone
  local target = drone_data.target
  if target and target.valid and target.unit_number then
    local index = target.unit_number
    data.targets[index] = data.targets[index] or {}
    data.targets[index][drone.unit_number] = drone_data
  end
  return process_drone_command(drone_data)
end

local find_a_character = function(drone_data)
  local entity = drone_data.entity
  if not (entity and entity.valid) then return end
  if drone_data.character and drone_data.character.valid and drone_data.character.surface == entity.surface then return true end
  local characters = get_characters_for_entity(entity)
  if not next(characters) then
    return
  end
  drone_data.character = entity.surface.get_closest(entity.position, characters)
  return true
end

local set_drone_idle = function(drone)
  if not (drone and drone.valid) then return end
--print("Setting drone idle")
  local drone_data = data.drone_commands[drone.unit_number]


  if drone_data then
    if find_a_character(drone_data) then
      process_return_to_character_command(drone_data)
      return
    else
      return drone_wait(drone_data, random(200, 400))
    end
  end

  set_drone_order(drone, {})

end

local check_ghost = function(entity)
  if not (entity and entity.valid) then return true end
  --entity.surface.create_entity{name = "flying-text", position = entity.position, text = "!"}
  local force = entity.force
  local surface = entity.surface
  local position = entity.position

  local prototype = game.entity_prototypes[entity.ghost_name]
  local character, item = get_character_point(prototype, entity)

--print("Checking ghost "..entity.ghost_name..random())

  if not character then
    --game.print("No character")
    return
  end


  local count = 0
  local extra_targets = {} --{[entity.unit_number] = entity}
  local extra = surface.find_entities_filtered{ghost_name = entity.ghost_name, position = position, radius = 5}
  for k, ghost in pairs (extra) do
    if count >= 8 then break end
    local unit_number = ghost.unit_number
    local should_check = data.ghosts_to_be_checked[unit_number] or data.ghosts_to_be_checked_again[unit_number]
    if should_check then
      remove_from_list(data.ghosts_to_be_checked, unit_number)
      data.ghost_check_index = remove_from_list(data.ghosts_to_be_checked_again, unit_number, data.ghost_check_index)
      extra_targets[unit_number] = ghost
      count = count + 1
    end
  end

  item.count = count

  local target = surface.get_closest(character.position, extra_targets)
  extra_targets[target.unit_number] = nil

  local drone_data =
  {
    character = character,
    order = drone_orders.construct,
    pickup = {stack = item},
    target = target,
    item_used_to_place = item.name,
    extra_targets = extra_targets
  }

  make_path_request(drone_data, character, target)
end

local on_built_entity = function(event)
  local entity = event.created_entity or event.ghost or event.entity
  if not (entity and entity.valid) then return end
  local entity_type = entity.type

  if entity_type == ghost_type then
    data.ghosts_to_be_checked[entity.unit_number] = entity
    --game.print(entity.unit_number)
    return
  end

  if entity_type == tile_ghost_type then
    data.tiles_to_be_checked[entity.unit_number] = entity
    return
  end

  if entity_type == "character" then
    add_character(entity)
  end

  local proxies = entity.surface.find_entities_filtered{position = entity.position, type = proxy_type}
  for k, proxy in pairs (proxies) do
    if proxy.proxy_target == entity then
      insert(data.proxies_to_be_checked, proxy)
    end
  end

end

local check_ghost_lists = function()

  local remaining_checks = check_priority_list(data.ghosts_to_be_checked, data.ghosts_to_be_checked_again, check_ghost, max_important_checks_per_tick)
  data.ghost_check_index = check_list(data.ghosts_to_be_checked_again, data.ghost_check_index, check_ghost, remaining_checks)

end

local check_upgrade = function(upgrade_data)
  local entity = upgrade_data.entity
  if not (entity and entity.valid) then
    --game.print("upgrade not valid")
    return true
  end
  --entity.surface.create_entity{name = "flying-text", position = entity.position, text = "!"}
  if not entity.to_be_upgraded() then

    --game.print("upgrade not to be upgraded?")
    return true
  end

  local upgrade_prototype = upgrade_data.upgrade_prototype
  if not upgrade_prototype then
    --game.print("Maybe some migration?")
    return true
  end

  local surface = entity.surface
  local force = entity.force
  local character, item = get_character_point(upgrade_prototype, entity)
  if not character then return end

  local count = 0

  local extra_targets = {}
  for k, nearby in pairs (surface.find_entities_filtered{name = entity.name, position = entity.position, radius = 8}) do
    if count >= 6 then break end
    local nearby_index = nearby.unit_number
    local should_check = data.upgrade_to_be_checked[nearby_index] or data.upgrade_to_be_checked_again[nearby_index]
    if should_check then
      extra_targets[nearby_index] = nearby
      remove_from_list(data.upgrade_to_be_checked, nearby_index)
      data.upgrade_check_index = remove_from_list(data.upgrade_to_be_checked_again, nearby_index, data.upgrade_check_index)
      count = count + 1
    end
  end

  local target = surface.get_closest(character.position, extra_targets)
  extra_targets[target.unit_number] = nil

  local drone_data =
  {
    character = character,
    order = drone_orders.upgrade,
    pickup = {stack = {name = item.name, count = count}},
    target = target,
    extra_targets = extra_targets,
    upgrade_prototype = upgrade_prototype,
    item_used_to_place = item.name
  }

  make_path_request(drone_data, character, target)
end

local check_upgrade_lists = function()
  --game.print(serpent.line(data.upgrade_to_be_checked_again))
  local remaining_checks = check_priority_list(data.upgrade_to_be_checked, data.upgrade_to_be_checked_again, check_upgrade, max_checks_per_tick)
  data.upgrade_check_index = check_list(data.upgrade_to_be_checked_again, data.upgrade_check_index, check_upgrade, remaining_checks)

end

local check_proxy = function(entity)
  if not (entity and entity.valid) then
  --print("Proxy not valid")
    return true
  end
  local target = entity.proxy_target
  if not (target and target.valid) then
  --print("Proxy target not valid")
    return true
  end

  --entity.surface.create_entity{name = "flying-text", position = entity.position, text = "!"}

  local items = entity.item_requests
  local force = entity.force
  local surface = entity.surface

  local characters = get_characters_in_distance(entity)
  local needed = 0
  local sent = 0
  local position = entity.position
  for name, count in pairs (items) do
    needed = needed + 1
    local selected_character
    for k, character in pairs (characters) do
      if character.get_item_count(name) > 0 then
        selected_character = character
        break
      end
    end
    if selected_character then
      local drone_data =
      {
        character = selected_character,
        order = drone_orders.request_proxy,
        pickup = {stack = {name = name, count = count}},
        target = entity
      }
      make_path_request(drone_data, selected_character, entity)
      sent = sent + 1
    end
  end
  return needed == sent
end

local check_proxies_lists = function()

  data.proxy_check_index = check_list(data.proxies_to_be_checked, data.proxy_check_index, check_proxy, max_checks_per_tick)

end

local check_cliff_deconstruction = function(deconstruct)
  --game.print("HI")
  local entity = deconstruct.entity
  local force = deconstruct.force
  local surface = entity.surface
  local position = entity.position

  local cliff_destroying_item = entity.prototype.cliff_explosive_prototype
  if not cliff_destroying_item then
    --game.print("Welp, idk...")
    return true
  end

  local characters = get_characters_in_distance(entity, force)

  for k, character in pairs (characters) do
    if character.get_item_count(cliff_destroying_item) == 0 then
      --game.print("no item for this guy")
      characters[k] = nil
    end
  end

  if not next(characters) then
    --game.print("no characters")
    return
  end

  local character = surface.get_closest(position, characters)

  local drone_data =
  {
    character = character,
    order = drone_orders.cliff_deconstruct,
    target = entity,
    pickup = {stack = {name = cliff_destroying_item, count = 1}}
  }
  make_path_request(drone_data, character, entity)

  return true

end

local check_deconstruction = function(deconstruct)
  local entity = deconstruct.entity
  local force = deconstruct.force
  if not (entity and entity.valid) then return true end
  --entity.surface.create_entity{name = "flying-text", position = entity.position, text = "!"}
  if not (force and force.valid) then return true end

  if not entity.to_be_deconstructed(force) then return true end

  if entity.type == cliff_type then
    return check_cliff_deconstruction(deconstruct)
  end

  local surface = entity.surface

  --[[local mineable_properties = entity.prototype.mineable_properties
  if not mineable_properties.minable then
  --print("Why are you marked for deconstruction if I cant mine you?")
    return
  end]]

  local character = get_character_for_job(entity, force)
  if not character then return end

  local index = unique_index(entity)
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


  if needed == 1 then

    --local drone = make_character_drone(character)
    --if not drone then return end
    local extra_targets = {}
    local count = 10

    for k, nearby in pairs (surface.find_entities_filtered{name = entity.name, position = entity.position, radius = 8}) do
      if count <= 0 then break end
      local nearby_index = unique_index(nearby)
      local should_check = data.deconstructs_to_be_checked[nearby_index] or data.deconstructs_to_be_checked_again[nearby_index]
      if should_check then
        extra_targets[nearby_index] = nearby
        remove_from_list(data.deconstructs_to_be_checked, nearby_index)
        data.deconstruction_check_index = remove_from_list(data.deconstructs_to_be_checked_again, nearby_index, data.deconstruction_check_index)
        count = count - 1
      end
    end

    local target = surface.get_closest(character.position, extra_targets)
    if not target then return end

    extra_targets[unique_index(target)] = nil

    local drone_data =
    {
      character = character,
      order = drone_orders.deconstruct,
      target = target,
      extra_targets = extra_targets
    }

    make_path_request(drone_data, character, target)
    return

  end

  for k = 1, math.min(needed, 10, character.get_item_count(names.units.construction_drone)) do
    if not (entity and entity.valid) then break end
    local drone_data =
    {
      character = character,
      order = drone_orders.deconstruct,
      target = entity
    }
    make_path_request(drone_data, character, entity)
    sent = sent + 1
  end

  data.sent_deconstruction[index] = sent
  return sent >= needed

end

local check_deconstruction_lists = function()

  local remaining_checks = check_priority_list(data.deconstructs_to_be_checked, data.deconstructs_to_be_checked_again, check_deconstruction, max_important_checks_per_tick)
  data.deconstruction_check_index = check_list(data.deconstructs_to_be_checked_again, data.deconstruction_check_index, check_deconstruction, remaining_checks)

end

local check_tile_deconstruction = function(entity)

  if not (entity and entity.valid) then return true end

  --entity.surface.create_entity{name = "flying-text", position = entity.position, text = "!"}

  local character = get_character_for_job(entity)
  if not character then return end

  local surface = entity.surface

  local extra_targets = {}
  for k, nearby in pairs (surface.find_entities_filtered{type = tile_deconstruction_proxy, position = entity.position, radius = 3}) do
    local nearby_index = unique_index(nearby)
    local should_check = data.deconstruction_proxies_to_be_checked[nearby_index]
    if should_check then
      extra_targets[nearby_index] = nearby
      remove_from_list(data.deconstructs_to_be_checked, nearby_index)
      data.deconstruction_tile_check_index = remove_from_list(data.deconstruction_proxies_to_be_checked, nearby_index, data.deconstruction_tile_check_index)
    end
  end
  local target = surface.get_closest(character.position, extra_targets)
  extra_targets[unique_index(target)] = nil

  local drone_data =
  {
    character = character,
    order = drone_orders.tile_deconstruct,
    target = target,
    extra_targets = extra_targets
  }

  make_path_request(drone_data, character, target)

end

local check_tile_deconstruction_lists = function()

  data.deconstruction_tile_check_index = check_list(data.deconstruction_proxies_to_be_checked, data.deconstruction_tile_check_index, check_tile_deconstruction, max_checks_per_tick)

end

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

local check_repair = function(entity)
  if not (entity and entity.valid) then return true end
  --entity.surface.create_entity{name = "flying-text", position = entity.position, text = "!"}
--print("Checking repair of an entity: "..entity.name)
  if entity.has_flag("not-repairable") then return true end

  local health = entity.get_health_ratio()
  if not (health and health < 1) then return true end

  local surface = entity.surface

  local characters = get_characters_in_distance(entity)

  local selected_character, repair_item

  local repair_items = get_repair_items()
  for k, character in pairs (characters) do
    for name, item in pairs (repair_items) do
      if character.get_item_count(name) > 0 then
        selected_character = character
        repair_item = item
        break
      end
    end
  end

  if not selected_character then
    return
  end

  local drone_data =
  {
    character = selected_character,
    order = drone_orders.repair,
    pickup = {stack = {name = repair_item.name, count = 1}},
    target = entity,
  }
  make_path_request(drone_data, selected_character, entity)
  return true
end

local check_repair_lists = function()
  local remaining_checks = check_priority_list(data.repair_to_be_checked, data.repair_to_be_checked_again, check_repair, max_checks_per_tick)
  data.repair_check_index = check_list(data.repair_to_be_checked_again, data.repair_check_index, check_repair, remaining_checks)

end

local check_tile = function(entity)
  if not (entity and entity.valid) then
    return true
  end

  local force = entity.force
  local surface = entity.surface
  local ghost_name = entity.ghost_name

  local tile_prototype = game.tile_prototypes[ghost_name]
  local character, item = get_character_point(tile_prototype, entity)

  if not character then
  --print("no eligible character with item?")
    return
  end

  --local drone = make_character_drone(character)
  --if not drone then return end

  local count = 0
  local extra_targets = {}
  local extra = surface.find_entities_filtered{type = tile_ghost_type, position = entity.position, radius = 3}
  for k, ghost in pairs (extra) do
    local unit_number = ghost.unit_number
    local should_check = data.tiles_to_be_checked[unit_number] and ghost.ghost_name == ghost_name
    if should_check then
      data.tile_check_index = remove_from_list(data.tiles_to_be_checked, unit_number, data.tile_check_index)
      extra_targets[unit_number] = ghost
      count = count + 1
    end
  end

  local target = surface.get_closest(character.position, extra_targets)
  extra_targets[target.unit_number] = nil

  local drone_data =
  {
    character = character,
    order = drone_orders.tile_construct,
    pickup = {stack = {name = item.name, count = count}},
    target = target,
    item_used_to_place = item.name,
    extra_targets = extra_targets
  }

  make_path_request(drone_data, character, target)

end

local check_tile_lists = function()
  --Being lazy... only 1 list for tiles (also probably fine)
  data.tile_check_index = check_list(data.tiles_to_be_checked, data.tile_check_index, check_tile, max_checks_per_tick)
end

local on_tick = function(event)
  --local profiler = game.create_profiler()


  check_deconstruction_lists()
  --game.print({"", game.tick, " deconstruction checks ", profiler})
  --profiler.reset()

  check_ghost_lists()
  --game.print({"", game.tick, " ghost checks ", profiler})
  --profiler.reset()

  check_upgrade_lists()
  --game.print({"", game.tick, " upgrade checks ", profiler})
  --profiler.reset()

  check_repair_lists()
  --game.print({"", game.tick, " repair checks ", profiler})
  --profiler.reset()

  check_proxies_lists()
  --game.print({"", game.tick, " proxy checks ", profiler})
  --profiler.reset()

  check_tile_deconstruction_lists()
  --game.print({"", game.tick, " tile decon checks ", profiler})
  --profiler.reset()

  check_tile_lists()
  --game.print({"", game.tick, " tile ghost checks ", profiler})
  --profiler.reset()

end

local get_build_time = function(drone_data)
  return random(10, 20)
end

local clear_extra_targets = function(drone_data)
  if not drone_data.extra_targets then return end

  local targets = validate(drone_data.extra_targets)
  local order = drone_data.order

  if order == drone_orders.upgrade then
    for unit_number, entity in pairs (targets) do
      data.upgrade_to_be_checked_again[unit_number] = {entity = entity, upgrade_prototype = drone_data.upgrade_prototype}
    end
    return
  end

  if order == drone_orders.construct then
    for unit_number, entity in pairs (targets) do
      data.ghosts_to_be_checked[unit_number] = entity
    end
    return
  end

  if order == drone_orders.tile_construct then
    for unit_number, entity in pairs (targets) do
      data.tiles_to_be_checked[unit_number] = entity
    end
    return
  end

  if order == drone_orders.deconstruct or order == drone_orders.cliff_deconstruct then
    for index, entity in pairs (targets) do
      local index = unique_index(entity)
      local force = drone_data.entity and drone_data.entity.force or drone_data.character and drone_data.character.force
      data.deconstructs_to_be_checked[index] = {entity = entity, force = force}
      data.sent_deconstruction[index] = (data.sent_deconstruction[index] or 1) - 1
    end
    return
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

local clear_target = function(drone_data)

  local target = drone_data.target
  if not (target and target.valid) then
    return
  end
  local order = drone_data.order
  local target_unit_number = target.unit_number
  if target_unit_number then
    if data.targets[target_unit_number] then
      local unit_number = drone_data.entity and drone_data.entity.unit_number
      if unit_number then
        data.targets[target_unit_number][unit_number] = nil
        if not next(data.targets[target_unit_number]) then
          data.targets[target_unit_number] = nil
        end
      end
    end
  end

  if order == drone_orders.request_proxy then
    insert(data.proxies_to_be_checked, target)
  elseif order == drone_orders.repair then
    data.repair_to_be_checked[target_unit_number] = target
  elseif order == drone_orders.upgrade then
    data.upgrade_to_be_checked_again[target_unit_number] = {entity = target, upgrade_prototype = drone_data.upgrade_prototype}
  elseif order == drone_orders.construct then
    data.ghosts_to_be_checked_again[target_unit_number] = target
  elseif order == drone_orders.tile_construct then
    data.tiles_to_be_checked[target_unit_number] = target
  elseif order == drone_orders.deconstruct or order == drone_orders.cliff_deconstruct then
    local index = unique_index(target)
    local force = (drone_data.entity and drone_data.entity.valid and drone_data.entity.force) or (drone_data.character and drone_data.character.valid and drone_data.character.force)
    data.deconstructs_to_be_checked_again[index] = {entity = target, force = force}
    data.sent_deconstruction[index] = (data.sent_deconstruction[index] or 1) - 1
  end

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

  if not find_a_character(drone_data) then
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

local clear_target_data = function(unit_number)
  if not unit_number then return end
  data.targets[unit_number] = nil
end

local cancel_target_data = function(unit_number)
  if not unit_number then return end
  local drone_datas = data.targets[unit_number]
  if drone_datas then
    data.targets[unit_number] = nil
    for k, drone_data in pairs (drone_datas) do
      cancel_drone_order(drone_data)
    end
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

  local chest = drone_data.character
  if not (chest and chest.valid) then
  --print("Character for pickup was not valid")
    return cancel_drone_order(drone_data)
  end

  if not move_to_order_target(drone_data, chest, ranges.interact) then
    return
  end


--print("Pickup chest in range, picking up item")

  local stack = drone_data.pickup.stack
  local drone_inventory = get_drone_inventory(drone_data)

  transfer_stack(drone_inventory, chest, stack)

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

  if drone_data.character then
    return process_return_to_character_command(drone_data)
  end

  find_a_character(drone_data)

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

  local unit_number = target.unit_number
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


  drone_inventory.remove{name = drone_data.item_used_to_place, count = 1}
  update_drone_sticker(drone_data)

  clear_target_data(unit_number)

  if proxy and proxy.valid then
    insert(data.proxies_to_be_checked, proxy)
  end

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
    duration = build_time,
    source_offset = offset
  }
  return drone_wait(drone_data, build_time)
end

local process_failed_command = function(drone_data)
  --game.speed = 0.1

  local drone = drone_data.entity
  --print(drone.ai_settings.path_resolution_modifier)
  --Sometimes they just fail for unrelated reasons, lets give them a few chances
  drone_data.fail_count = (drone_data.fail_count or 0) + 1
  drone.ai_settings.path_resolution_modifier = math.min(4, drone.ai_settings.path_resolution_modifier + 1)
  --game.print("Set resolution: "..drone.ai_settings.path_resolution_modifier)
  if drone_data.fail_count < 10 then
    return drone_wait(drone_data, 10)
  end

  --We REALLY can't get to it or something, tell the player to come sort it out...
  if true then
    drone_data.fail_count = nil
    local position = drone.surface.find_non_colliding_position(drone.name, drone.position, 0, 2)
    drone.teleport(position)
    return cancel_drone_order(drone_data)
  end
  local target = drone_data.target
  if target and target.valid then
    target.surface.create_entity{name = "tutorial-flying-text", position = target.position, text = "Can't reach me "..drone.unit_number}
  end
  for k, player in pairs (drone.force.connected_players) do
    player.add_custom_alert(drone, {type = "item", name = drone.name}, "Drone cannot reach target.", true)
  end
  return drone_wait(drone_data, 300)
end

local process_deconstruct_command = function(drone_data)
--print("Processing deconstruct command")
  local target = drone_data.target
  if not (target and target.valid) then
    return cancel_drone_order(drone_data)
  end

  local drone = drone_data.entity

  if not target.to_be_deconstructed(drone.force) then
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
      duration = build_time,
      source_offset = offset
    }
    return drone_wait(drone_data, build_time)
  else
    drone_data.beam = nil
  end

  local mined = mine_entity(drone_inventory, target)

  if mined then
    if unit_number then
      clear_target_data(unit_number)
    end
    data.sent_deconstruction[index] = nil
  else
    update_drone_sticker(drone_data)
    if drone_inventory.is_empty() then
      return drone_wait(drone_data, 300)
    end
    cancel_drone_order(drone_data)
    return
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
  local unit_number = target.unit_number
  local neighbour = entity_type == "underground-belt" and target.neighbours
  local type = entity_type == "underground-belt" and target.belt_to_ground_type or entity_type == "loader" and target.loader_type
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

  get_drone_inventory(drone_data).remove({name = drone_data.item_used_to_place})
  clear_target_data(unit_number)

  local drone_inventory = get_drone_inventory(drone_data)
  local products = game.entity_prototypes[original_name].mineable_properties.products

  take_product_stacks(drone_inventory, products)


  if neighbour and neighbour.valid then
  --print("Upgrading neighbour")
    local type = neighbour.type == "underground-belt" and neighbour.belt_to_ground_type
    local neighbour_unit_number = neighbour.unit_number
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
    clear_target_data(neighbour_unit_number)
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
    duration = build_time,
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
    duration = build_time,
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

  local tile = target.surface.get_tile(position.x, position.y)
  local current_prototype = tile.prototype
  local products = current_prototype.mineable_properties.products

  clear_target_data(target.unit_number)
  surface.set_tiles({{name = target.ghost_name, position = position}}, true)

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
    duration = build_time,
    source_offset = offset
  }
  return drone_wait(drone_data, build_time)
end

local process_deconstruct_tile_command = function(drone_data)
--print("Processing deconstruct tile command")
  local target = drone_data.target
  if not (target and target.valid) then
  --print("Target was not valid...")
    return cancel_drone_order(drone_data)
  end


  if not move_to_order_target(drone_data, target, ranges.interact) then
    return
  end


  local drone = drone_data.entity
  local position = target.position
  local surface = target.surface
  if not drone_data.beam then
    local build_time = get_build_time(drone_data)
    local orientation, offset = get_beam_orientation(drone.position, position)
    drone.orientation = orientation
    surface.create_entity
    {
      name = beams.deconstruction,
      source = drone,
      target_position = position,
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

  local tile = surface.get_tile(position.x, position.y)
  local current_prototype = tile.prototype
  local products = current_prototype.mineable_properties.products

  local hidden = tile.hidden_tile or "out-of-map"
  surface.set_tiles({{name = hidden, position = position}}, true)
  target.destroy()

  local drone_inventory = get_drone_inventory(drone_data)
  local insert = drone_inventory.insert
  if products then
    for k, product in pairs (products) do
      local stack = stack_from_product(product)
      if stack then
        insert(stack)
      end
    end
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

  get_drone_inventory(drone_data).remove{name = target.prototype.cliff_explosive_prototype, count = 1}
  target.surface.create_entity{name = "ground-explosion", position = util.center(target.bounding_box)}
  target.destroy()
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

process_return_to_character_command = function(drone_data)

--print("returning to dude")

  local target = drone_data.character
  if not (target and target.valid) then
    return cancel_drone_order(drone_data)
  end

  if not move_to_order_target(drone_data, target, ranges.return_to_character) then
    return
  end

  local inventory = get_drone_inventory(drone_data)
  transfer_inventory(inventory, target)

  if not inventory.is_empty() then
    drone_wait(drone_data, random(18, 24))
    return
  end

  if target.insert({name = names.units.construction_drone, count = 1}) == 0 then
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
    --I guess it can happen, that another mod will kill it first? Who cares, this never happened during testing!
    log("Drone entity not valid when processing its own command!\n"..serpent.block(drone_data))
    return
  end

  --local print = function(string)
  --print(string.. " | "..drone.unit_number)
  --end
--print("Processing drone command")

  drone.speed = drone.prototype.speed * ( 1 + (math.random() - 0.5) / 4)

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

  if drone_data.order == drone_orders.tile_construct then
  --print("Tile Construct")
    return process_construct_tile_command(drone_data)
  end

  if drone_data.order == drone_orders.tile_deconstruct then
  --print("Tile Deconstruct")
    return process_deconstruct_tile_command(drone_data)
  end

  if drone_data.order == drone_orders.cliff_deconstruct then
  --print("Cliff Deconstruct")
    return process_deconstruct_cliff_command(drone_data)
  end

  find_a_character(drone_data)

  if drone_data.character then
    return process_return_to_character_command(drone_data)
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
  local entity = event.entity or event.ghost
--print("On removed event fired: "..entity.name.." - "..game.tick)
  if not (entity and entity.valid) then return end
  local unit_number = entity.unit_number
  if not unit_number then return end

  if is_commandable(entity.name) then
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
    return
  end

  cancel_target_data(unit_number)

  if entity.type == ghost_type then
    data.ghosts_to_be_checked_again[unit_number] = nil
    data.ghosts_to_be_checked[unit_number] = nil
    return
  end

end

local on_marked_for_deconstruction = function(event)

  local force = event.force or (event.player_index and game.players[event.player_index].force)
  if not force then return end
  local entity = event.entity
  if not (entity and entity.valid) then return end
  local type = entity.type
  if type == tile_deconstruction_proxy then
    data.deconstruction_proxies_to_be_checked[unique_index(entity)] = entity
  else
    data.deconstructs_to_be_checked[unique_index(entity)] = {entity = entity, force = force}
  end
end

local on_entity_damaged = function(event)
  local entity = event.entity
  local unit_number = entity.unit_number
  --For now, why would you want to repair trees and things? If it doens't have a unit number, no repairs.
  --Maybe I will change this in the future.
  if not unit_number then return end
  if data.targets[unit_number] then return end
  if data.repair_to_be_checked[unit_number] then return end
  data.repair_to_be_checked[unit_number] = entity
end

local on_marked_for_upgrade = function(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  local upgrade_data = {entity = entity, upgrade_prototype = event.target}
  data.upgrade_to_be_checked[entity.unit_number] = upgrade_data
end

local resetup_ghosts = function()
  data.ghosts_to_be_checked_again = {}
  for k, surface in pairs (game.surfaces) do
    for k, ghost in pairs (surface.find_entities_filtered{type = "entity-ghost"}) do
      data.ghosts_to_be_checked_again[ghost.unit_number] = ghost
    end
  end
end

local setup_characters = function()
  data.characters = {}
  for k, surface in pairs (game.surfaces) do
    for k, character in pairs (surface.find_entities_filtered{type = "character"}) do
      add_character(character)
    end
  end
end

local on_player_created = function(event)
  local player = game.get_player(event.player_index)
  if player.character then
    add_character(player.character)
  end
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

  if destination.to_be_deconstructed(destination.force) then
    data.deconstructs_to_be_checked_again[unique_index(destination)] = {entity = destination, force = destination.force}
    data.sent_deconstruction[unique_index(destination)] = 0
  end

  if destination.type == tile_deconstruction_proxy then
    data.deconstruction_proxies_to_be_checked[unique_index(destination)] = destination
  end

  if destination.to_be_upgraded() then
    data.upgrade_to_be_checked[destination.unit_number] = destination
  end

  if destination.type == proxy_type then
    insert(data.proxies_to_be_checked, destination)
  end

  on_built_entity{created_entity = destination}


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
  --game.print("HI")
  local drone_data = data.path_requests[event.id]
  if not drone_data then return end
  data.path_requests[event.id] = nil

  local character = drone_data.character
  if not (character and character.valid) then
    --game.print("no character")
    clear_target(drone_data)
    clear_extra_targets(drone_data)
    return
  end

  local unit_number = character.unit_number
  data.request_count[unit_number] = (data.request_count[unit_number] or 0) - 1

  if not event.path then
    --game.print("no path")
    clear_target(drone_data)
    clear_extra_targets(drone_data)
    return
  end


  local drone = make_character_drone(character)
  if not drone then

    --game.print("no drone")
    clear_target(drone_data)
    clear_extra_targets(drone_data)
    return
  end

  set_drone_order(drone, drone_data)

end

local set_damaged_event_filter = function()

  if not data.non_repairable_entities then return end

  local filters = {}
  for name, bool in pairs (data.non_repairable_entities) do
    local filter =
    {
      filter = "name",
      name = name,
      invert = true,
      mode = "and"
    }
    table.insert(filters, filter)
  end

  if not next(filters) then return end

  script.set_event_filter(defines.events.on_entity_damaged, filters)
end

local update_non_repairable_entities = function()
  data.non_repairable_entities = {}
  for name, entity in pairs (game.entity_prototypes) do
    if entity.has_flag("not-repairable") then
      data.non_repairable_entities[name] = true
    end
  end
  set_damaged_event_filter()
end

local lib = {}

lib.events =
{
  [defines.events.on_tick] = on_tick,

  [defines.events.on_built_entity] = on_built_entity,
  [defines.events.on_post_entity_died] = on_built_entity,
  [defines.events.script_raised_built] = on_built_entity,

  [defines.events.on_entity_died] = on_entity_removed,
  [defines.events.on_robot_mined_entity] = on_entity_removed,
  [defines.events.on_player_mined_entity] = on_entity_removed,
  [defines.events.on_pre_ghost_deconstructed] = on_entity_removed,

  [defines.events.on_player_created] = on_player_created,
  [defines.events.on_player_joined_game] = on_player_created,
  [defines.events.on_player_toggled_map_editor] = on_player_created,
  [defines.events.on_player_respawned] = on_player_created,
  [defines.events.on_player_changed_surface] = on_player_created,

  [defines.events.on_ai_command_completed] = on_ai_command_completed,
  [defines.events.on_marked_for_deconstruction] = on_marked_for_deconstruction,
  [defines.events.on_entity_damaged] = on_entity_damaged,
  [defines.events.on_marked_for_upgrade] = on_marked_for_upgrade,
  [defines.events.on_entity_cloned] = on_entity_cloned,

  [defines.events.on_script_path_request_finished] = on_script_path_request_finished,
}

lib.on_load = function()
  data = global.construction_drone or data
  global.construction_drone = data
  set_damaged_event_filter()
end

lib.on_init = function()
  game.map_settings.steering.default.force_unit_fuzzy_goto_behavior = false
  game.map_settings.steering.moving.force_unit_fuzzy_goto_behavior = false
  game.map_settings.path_finder.use_path_cache = false
  global.construction_drone = global.construction_drone or data

  resetup_ghosts()
  setup_characters()

  if remote.interfaces["unit_control"] then
    remote.call("unit_control", "register_unit_unselectable", names.units.construction_drone)
  end
  update_non_repairable_entities()
end

lib.on_configuration_changed = function()
  game.map_settings.path_finder.use_path_cache = false

  if remote.interfaces["unit_control"] then
    remote.call("unit_control", "register_unit_unselectable", names.units.construction_drone)
  end

  if data.idle_drones then
    for k, drones in pairs (data.idle_drones) do
      for k, drone in pairs (drones) do
        set_drone_idle(drone)
      end
    end
  end

  if not data.migrate_deconstructs then
    data.migrate_deconstructs = true
    local new_check = {}
    for k, to_check in pairs (data.deconstructs_to_be_checked) do
      if to_check.entity.valid then
        new_check[unique_index(to_check.entity)] = to_check
      end
    end
    for k, to_check in pairs (data.deconstructs_to_be_checked_again) do
      if to_check.entity.valid then
        new_check[unique_index(to_check.entity)] = to_check
      end
    end
    data.deconstructs_to_be_checked = new_check
    data.deconstructs_to_be_checked_again = {}
  end

  data.path_requests = data.path_requests or {}
  data.request_count = data.request_count or {}

  setup_characters()
  prune_commands()
  
  update_non_repairable_entities()
end

return lib
