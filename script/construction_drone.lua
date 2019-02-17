--todo put units into groups at logistic points they finish at -> will follow player and act more cute

local max = math.huge
local insert = table.insert
local remove = table.remove
local pairs = pairs
local beams = names.beams
local proxy_name = names.entities.construction_drone_proxy_chest

drone_prototypes =
{
  [names.units.construction_drone] =
  {
    interact_range = 10,
    follow_range = 20
  },
}

local abs = math.abs
--Assumes position will be between -1000000 and 1000000
local position_hash = function(position)
  local x = position.x
  local y = position.y
  if x < 0 then
    x = -x * 2 - 1
  else
    x = x * 2
  end
  if y < 0 then
    y = -y * 2 - 1
  else
    y = y * 2
  end
  return (x * 1000000) + y
end

local is_commandable = function(string)
  return drone_prototypes[string] ~= nil
end

local ghost_type = "entity-ghost"
local tile_ghost_type = "tile-ghost"
local proxy_type = "item-request-proxy"
local tile_deconstruction_proxy = "deconstructible-tile-proxy"
local cliff_type = "cliff"

local max_checks_per_tick = 6

local drone_pathfind_flags =
{
  allow_destroy_friendly_entities = false,
  cache = false,
  low_priority = false
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
  follow = 9
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
  idle_drones = {},
  drone_commands = {},
  targets = {},
  sent_deconstruction = {},
  debug = false,
  proxy_chests = {},
  deconstruction_map = {},
  no_network_drones = {},
  networks = {},
  allow_in_active_networks = true
}

local get_drone_radius = function()
  return 0.3
end

local print = function(string)
  if not data.debug then return end
  local tick = game.tick
  log(tick.." | "..string)
  game.print(tick.." | "..string)
end

local dist = function(cell_a, cell_b)
  local position1 = cell_a.owner.position
  local position2 = cell_b.owner.position
  return ((position2.x - position1.x) * (position2.x - position1.x)) + ((position2.y - position1.y) * (position2.y - position1.y))
end

local oofah = (2 ^ 0.5) / 2

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
  follow = 2
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
    elseif range == ranges.follow then
      radius = get_radius_map()[entity.name] + drone_prototypes[entity.name].follow_range
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

local lowest_f_score = function(set, f_score)
  local lowest = max
  local bestcell
  for k, cell in pairs(set) do
    local score = f_score[cell.owner.unit_number]
    if score <= lowest then
      lowest = score
      bestcell = cell
    end
  end
  return bestcell
end

local unwind_path
unwind_path = function(flat_path, map, current_cell)
  local index = current_cell.owner.unit_number
  if map[index] then
    insert(flat_path, 1, map[index])
    return unwind_path(flat_path, map, map[index])
  else
    return flat_path
  end
end

local get_path = function(start, goal, cells)
  print("Starting path find")
  local closed_set = {}
  local open_set = {}
  local came_from = {}

  local g_score = {}
  local f_score = {}
  local start_index = start.owner.unit_number
  open_set[start_index] = start
  g_score[start_index] = 0
  f_score[start_index] = dist(start, goal)

  local insert = table.insert
  while table_size(open_set) > 0 do

    local current = lowest_f_score(open_set, f_score)

    if current == goal then
      local path = unwind_path({}, came_from, goal)
      insert(path, goal)
      print("A* path find complete")
      return path
    end

    local current_index = current.owner.unit_number
    open_set[current_index] = nil
    closed_set[current_index] = current

    for k, neighbour in pairs(current.neighbours) do
      local neighbour_index = neighbour.owner.unit_number
      if not closed_set[neighbour_index] then
        local tentative_g_score = g_score[current_index] + dist(current, neighbour)
        local new_node = not open_set[neighbour_index]
        if new_node then
          open_set[neighbour.owner.unit_number] = neighbour
          f_score[neighbour.owner.unit_number] = max
        end
        if new_node or tentative_g_score < g_score[neighbour_index] then
          came_from[neighbour_index] = current
          g_score[neighbour_index] = tentative_g_score
          f_score[neighbour_index] = g_score[neighbour_index] + dist(neighbour, goal)
        end
      end
    end

  end
  return nil -- no valid path
end

local get_drone_path = function(unit, logistic_network, target)
  if not (unit and unit.valid) then return end

  local origin_cell = logistic_network.find_cell_closest_to(unit.position)
  local destination_cell = logistic_network.find_cell_closest_to(target.position)
  if not destination_cell and origin_cell then return end

  local cells = logistic_network.cells
  if not origin_cell then return end

  return get_path(origin_cell, destination_cell, cells)

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

local get_drone_inventory = function(drone_data)
  local inventory = drone_data.inventory
  if inventory and inventory.valid then
    inventory.sort_and_merge()
    return inventory
  end
  local drone = drone_data.entity
  local proxy_chest = data.proxy_chests[drone.unit_number] or drone.surface.create_entity
  {
    name = proxy_name,
    position = {1000000, 1000000},
    force = drone.force
  }
  data.proxy_chests[drone.unit_number] = proxy_chest
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
  local has = source_entity.get_item_count(stack.name)
  if has == 0 then return 0 end
  local wanted = stack.count
  local transferred = 0
  local insert = destination.insert
  local can_insert = destination.can_insert
  for k, inventory in pairs(inventories(source_entity)) do
    local source_stack = inventory.find_item_stack(stack.name)
    if source_stack and source_stack.valid and source_stack.valid_for_read and can_insert(source_stack) then
      local inserted = insert(stack)
      transferred = transferred + inserted
      local remove_stack = {name = stack.name, count = inserted}
      --count should always be greater than 0, otherwise can_insert would fail
      inventory.remove(remove_stack)
    end
    if transferred >= wanted then
      break
    end
  end
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
      --count should always be greater than 0, otherwise can_insert would fail
      remove(remove_stack)
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
  if products then
    for k, product in pairs (products) do
      insert(stack_from_product(product))
    end
  end
end

local mine_entity = function(inventory, target)
  take_all_content(inventory, target)
  if not (target and target.valid) then
    --Items on ground die when you remove the items...
    return true
  end
  if target.has_items_inside() then
    print("Tried to take all the target items, but he still has some, ergo, we cant fit that many items.")
    return
  end

  local prototype = target.prototype

  local destroyed = target.destroy
  {
    raise_destroy = true
  }

  if not destroyed then
    print("He is still alive after destroying him, tough guy.")
    return false
  end

  take_product_stacks(inventory, prototype.mineable_properties.products)
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

remote.add_interface("construction_drone",
{
  set_debug = function(bool)
    data.debug = bool
  end,
  dump = function()
    print(serpent.block(data))
  end
})

local check_priority_list = function(list, other_list, check_function, count)
  while count > 0 do
    local index, entry = next(list)
    if index == nil then break end
    other_list[index] = entry
    list[index] = nil
    check_function(entry)
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
    --if not entry then this_index = nil end
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

local get_point = function(prototype, entity)
  local position = entity.position
  local surface = entity.surface
  local force = entity.force
  local networks = surface.find_logistic_networks_by_construction_area(position, force)
  local items = prototype.items_to_place_this
  for k, network in pairs (networks) do
    --If there are the normal bots in the network, let them handle it!
    if data.allow_in_active_networks or network.available_construction_robots == 0 then
      local select = network.select_pickup_point
      for k, item in pairs(items) do
        point = select({name = item.name, position = position})
        if point then
          return point, item
        end
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

local get_nearest_network = function(entity)
  local surface = entity.surface
  local force = entity.force
  local position = entity.position

  local networks = surface.find_logistic_networks_by_construction_area(position, force)
  if #networks == 0 then
    networks = force.logistic_networks[surface.name]
  end
  local owners = {}
  for k, network in pairs (networks) do
    local cell = network.find_cell_closest_to(position)
    if cell then insert(owners, cell.owner) end
  end
  local closest = surface.get_closest(position, owners)
  if not closest then
    return
  end
  return closest.logistic_cell.logistic_network
end

local get_logistic_network_surface = function(logistic_network)
  local cell = logistic_network.cells[1]
  return cell.owner.surface
end

local get_logistic_network_index = function(logistic_network)
  local networks = data.networks
  local last_key = 0
  for k, network in pairs (networks) do
    if network and network.valid and network == logistic_network then
      return k
    end
    last_key = k
  end
  local new_key = last_key + 1
  networks[new_key] = logistic_network
  return new_key
end

local get_idle_drones = function(logistic_network)
  local network_index = get_logistic_network_index(logistic_network)

  local drones = data.idle_drones[network_index]
  if not drones then
    drones = {}
    data.idle_drones[network_index] = drones
  end

  return validate(drones)
end

local add_idle_drone = function(drone)
  local network = get_nearest_network(drone)
  if not network then
    data.no_network_drones[drone.unit_number] = drone
    return
  end
  local idle_drones = get_idle_drones(network)
  idle_drones[drone.unit_number] = drone
end

local get_or_find_network = function(drone_data)
  local network = drone_data.network
  if network and network.valid then
    return network
  end
  local network = get_nearest_network(drone_data.entity)
  drone_data.network = network
  return network
end

local remove_idle_drone = function(drone)
  local unit_number = drone.unit_number
  data.no_network_drones[unit_number] = nil
  local network
  local drone_data = data.drone_commands[unit_number]
  if drone_data then
    network = get_or_find_network(drone_data)
  else
    network = get_nearest_network(drone)
  end
  if not network then
    return
  end
  local idle_drones = get_idle_drones(network)
  idle_drones[unit_number] = nil
end

local update_drone_sticker

local process_drone_command

local set_drone_order = function(drone, drone_data)
  drone.ai_settings.path_resolution_modifier = -2
  drone.ai_settings.do_separation = true
  remove_idle_drone(drone)
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

local set_drone_idle = function(drone)
  if not (drone and drone.valid) then return end
  print("Setting drone idle")
  local drone_data = data.drone_commands[drone.unit_number]

  if drone_data then
    update_drone_sticker(drone_data)
    local stack = get_drone_first_stack(drone_data)
    if stack then
      drone_data.dropoff = {stack = stack}
      return process_drone_command(drone_data)
    end
  end

  drone.speed = math.random() * drone.speed
  data.drone_commands[drone.unit_number] = nil
  add_idle_drone(drone)

  local network = get_nearest_network(drone)
  if network then
    local destination_cell = network.find_cell_closest_to(drone.position)
    local owner = destination_cell.owner
    if destination_cell.mobile then
      local drone_data =
      {
        order = drone_orders.follow,
        target = owner
      }
      set_drone_order(drone, drone_data)
      add_idle_drone(drone)
      return
    end
    drone.set_command
    {
      type = defines.command.go_to_location,
      destination_entity = owner,
      distraction = defines.distraction.none,
      radius = math.max(destination_cell.logistic_radius, get_radius(drone) + get_radius(owner))
    }
  end

end

local check_ghost = function(entity)
  if not (entity and entity.valid) then return true end
  --entity.surface.create_entity{name = "flying-text", position = entity.position, text = "!"}
  local force = entity.force
  local surface = entity.surface
  local position = entity.position

  local prototype = game.entity_prototypes[entity.ghost_name]
  local point, item = get_point(prototype, entity)

  if not point then
    --print("no eligible point with item?")
    return
  end

  local chest = point.owner
  local drones = get_idle_drones(point.logistic_network)
  local drone = surface.get_closest(chest.position, drones)

  if not drone then
    --print("No drones for pickup")
    return
  end

  local network = point.logistic_network

  local radius = 5
  local area = {{position.x - radius, position.y - radius}, {position.x + radius, position.y + radius}}
  local count = 0
  local extra_targets = {} --{[entity.unit_number] = entity}
  local extra = surface.find_entities_filtered{ghost_name = entity.ghost_name, area = area}
  for k, ghost in pairs (extra) do
    if count >= 6 then break end
    local unit_number = ghost.unit_number
    local should_check = data.ghosts_to_be_checked[unit_number] or data.ghosts_to_be_checked_again[unit_number]
    if should_check then
      remove_from_list(data.ghosts_to_be_checked, unit_number)
      data.ghost_check_index = remove_from_list(data.ghosts_to_be_checked_again, unit_number, data.ghost_check_index)
      extra_targets[unit_number] = ghost
      count = count + 1
    end
  end

  --game.print("size "..table_size(extra_targets))
  --game.print("count "..count)
  --print(serpent.block(extra_targets))

  local target = surface.get_closest(chest.position, extra_targets)
  extra_targets[target.unit_number] = nil
  local drone_data =
  {
    order = drone_orders.construct,
    pickup = {chest = chest, stack = {name = item.name, count = count}},
    network = network,
    target = target,
    item_used_to_place = item.name,
    extra_targets = extra_targets
  }

  return set_drone_order(drone, drone_data)
end

local on_built_entity = function(event)
  local entity = event.created_entity or event.ghost
  if not (entity and entity.valid) then return end
  local entity_type = entity.type

  if entity_type == ghost_type then
    data.ghosts_to_be_checked[entity.unit_number] = entity
    return
  end

  if entity_type == tile_ghost_type then
    data.tiles_to_be_checked[entity.unit_number] = entity
    return
  end

  if is_commandable(entity.name) then
    print("Adding idle drone")
    set_drone_idle(entity)
    return
  end

  local bounding_box = entity.bounding_box or entity.selection_box
  local proxies = entity.surface.find_entities_filtered{area = bounding_box, type = proxy_type}
  for k, proxy in pairs (proxies) do
    if proxy.proxy_target == entity then
      insert(data.proxies_to_be_checked, proxy)
      break
    end
  end

end

local check_ghost_lists = function()

  local remaining_checks = check_priority_list(data.ghosts_to_be_checked, data.ghosts_to_be_checked_again, check_ghost, max_checks_per_tick)
  data.ghost_check_index = check_list(data.ghosts_to_be_checked_again, data.ghost_check_index, check_ghost, remaining_checks)

end

local check_upgrade = function(upgrade_data)
  local entity = upgrade_data.entity
  if not (entity and entity.valid) then return true end
  if not entity.to_be_upgraded() then return true end

  local target_prototype = upgrade_data.upgrade_prototype
  if not target_prototype then
    print("Maybe some migration?")
    return true
  end

  local surface = entity.surface
  local force = entity.force
  local point, item = get_point(target_prototype, entity)
  if not point then return end

  if not point then
    print("no point with item?")
    return
  end

  local chest = point.owner
  local drones = get_idle_drones(point.logistic_network)
  local drone = surface.get_closest(chest.position, drones)

  if not drone then
    print("No drones for pickup")
    return
  end

  local network = point.logistic_network
  local count = 0

  local extra_targets = {}
  local position = entity.position
  local radius = 5
  local area = {{position.x - radius, position.y - radius},{position.x + radius, position.y + radius}}
  for k, nearby in pairs (surface.find_entities_filtered{name = entity.name, area = area}) do
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

  local target = surface.get_closest(chest.position, extra_targets)
  extra_targets[target.unit_number] = nil

  local drone_data =
  {
    order = drone_orders.upgrade,
    pickup = {chest = chest, stack = {name = item.name, count = count}},
    network = network,
    target = target,
    extra_targets = extra_targets,
    target_prototype = target_prototype,
    item_used_to_place = item.name
  }

  return set_drone_order(drone, drone_data)
end

local check_upgrade_lists = function()

  local remaining_checks = check_priority_list(data.upgrade_to_be_checked, data.upgrade_to_be_checked_again, check_upgrade, max_checks_per_tick)
  data.upgrade_check_index = check_list(data.upgrade_to_be_checked_again, data.upgrade_check_index, check_upgrade, remaining_checks)

end

local check_proxy = function(entity)
  if not (entity and entity.valid) then print("Proxy not valid") return true end
  local target = entity.proxy_target
  if not (target and target.valid) then print("Proxy target not valid") return true end

  local items = entity.item_requests
  local force = entity.force
  local surface = entity.surface

  local networks = surface.find_logistic_networks_by_construction_area(entity.position, force)
  local needed = 0
  local sent = 0
  local position = entity.position
  for name, count in pairs (items) do
    needed = needed + 1
    local point
    for k, network in pairs (networks) do
      if data.allow_in_active_networks or network.available_construction_robots == 0 then
        point = network.select_pickup_point({name = name, position = position})
        if point then break end
      end
    end
    if point then
      local chest = point.owner
      local drone = surface.get_closest(chest.position, get_idle_drones(point.logistic_network))
      if drone then
        drone_data =
        {
          order = drone_orders.request_proxy,
          network = point.logistic_network,
          pickup = {stack = {name = name, count = count}, chest = chest},
          target = entity
        }
        set_drone_order(drone, drone_data)
        sent = sent + 1
      end
    end
  end
  return needed == sent
end

local check_proxies_lists = function()

  data.proxy_check_index = check_list(data.proxies_to_be_checked, data.proxy_check_index, check_proxy, max_checks_per_tick)

end

local check_cliff_deconstruction = function(deconstruct)

  local entity = deconstruct.entity
  local force = deconstruct.force
  local surface = entity.surface
  local position = entity.position

  local networks = surface.find_logistic_networks_by_construction_area(position, force)
  local any
  for k, network in pairs (networks) do
    if data.allow_in_active_networks or network.available_construction_robots == 0 then
      any = true
      break
    end
  end
  if not any then
    print("He is outside of any of our eligible construction areas...")
    return
  end

  local cliff_destroying_item = entity.prototype.cliff_explosive_prototype
  if not cliff_destroying_item then
    print("Welp, idk...")
    return true
  end

  local networks = surface.find_logistic_networks_by_construction_area(position, force)
  local point
  for k, network in pairs (networks) do
    --If there are the normal bots in the network, let them handle it!
    if data.allow_in_active_networks or network.available_construction_robots == 0 then
      point = network.select_pickup_point({name = cliff_destroying_item, position = position})
      if point then
        break
      end
    end
  end

  if not point then
    print("no point with cliff destroying item...")
    return
  end

  local chest = point.owner

  local drones = get_idle_drones(point.logistic_network)
  local drone = surface.get_closest(chest.position, drones)
  if drone then
    local drone_data =
    {
      order = drone_orders.cliff_deconstruct,
      network = point.logistic_network,
      target = entity,
      pickup = {stack = {name = cliff_destroying_item, count = 1}, chest = chest}
    }
    set_drone_order(drone, drone_data)
    return true
  end

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

  local mineable_properties = entity.prototype.mineable_properties
  if not mineable_properties.minable then
    print("Why are you marked for deconstruction if I cant mine you?")
    return
  end
  local networks = surface.find_logistic_networks_by_construction_area(entity.position, force)
  local network
  for k, other_network in pairs (networks) do
    if data.allow_in_active_networks or other_network.available_construction_robots == 0 then
      network = other_network
      break
    end
  end
  if not network then
    print("He is outside of any of our eligible construction areas...")
    return
  end

  local position = entity.position
  local index = position_hash(position)
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
  local drones = get_idle_drones(network)
  if needed == 1 then
    local drone = surface.get_closest(position, drones)
    if not drone then return end
    local extra_targets = {}
    local radius = 3
    local count = 6
    local area = {{position.x - radius, position.y - radius},{position.x + radius, position.y + radius}}
    for k, nearby in pairs (surface.find_entities_filtered{name = entity.name, area = area}) do
      if count <= 0 then break end
      local nearby_index = position_hash(nearby.position)
      local should_check = data.deconstructs_to_be_checked[nearby_index] or data.deconstructs_to_be_checked_again[nearby_index]
      if should_check then
        extra_targets[nearby_index] = nearby
        remove_from_list(data.deconstructs_to_be_checked, nearby_index)
        data.deconstruction_check_index = remove_from_list(data.deconstructs_to_be_checked_again, nearby_index, data.deconstruction_check_index)
        count = count - 1
      end
    end
    local target = surface.get_closest(drone.position, extra_targets)
    extra_targets[position_hash(target.position)] = nil
    local drone_data =
    {
      order = drone_orders.deconstruct,
      network = network,
      target = target,
      extra_targets = extra_targets
    }
    return set_drone_order(drone, drone_data)
  else
    for k = 1, math.min(needed, 10) do
      if not (entity and entity.valid) then break end
      local drone = surface.get_closest(position, drones)
      if drone then
        local drone_data =
        {
          order = drone_orders.deconstruct,
          network = network,
          target = entity
        }
        set_drone_order(drone, drone_data)
        sent = sent + 1
      end
    end
    data.sent_deconstruction[index] = sent
    return sent >= needed
  end

end

local check_deconstruction_lists = function()

  local remaining_checks = check_priority_list(data.deconstructs_to_be_checked, data.deconstructs_to_be_checked_again, check_deconstruction, max_checks_per_tick)
  data.deconstruction_check_index = check_list(data.deconstructs_to_be_checked_again, data.deconstruction_check_index, check_deconstruction, remaining_checks)

end

local check_tile_deconstruction = function(entity)

  if not (entity and entity.valid) then return true end

  --entity.surface.create_entity{name = "flying-text", position = entity.position, text = "!"}
  local force = entity.force
  local surface = entity.surface
  local position = entity.position

  local networks = surface.find_logistic_networks_by_construction_area(position, force)
  local network
  for k, other_network in pairs (networks) do
    if data.allow_in_active_networks or other_network.available_construction_robots == 0 then
      network = other_network
      break
    end
  end

  if not network then
    print("He is outside of any of our eligible construction areas...")
    return
  end

  local drone = surface.get_closest(position, get_idle_drones(network))
  if not drone then return end

  local extra_targets = {}
  local radius = 2
  local area = {{position.x - radius, position.y - radius},{position.x + radius, position.y + radius}}
  for k, nearby in pairs (surface.find_entities_filtered{type = tile_deconstruction_proxy, area = area}) do
    local nearby_index = position_hash(nearby.position)
    local should_check = data.deconstruction_proxies_to_be_checked[nearby_index]
    if should_check then
      extra_targets[nearby_index] = nearby
      remove_from_list(data.deconstructs_to_be_checked, nearby_index)
      data.deconstruction_tile_check_index = remove_from_list(data.deconstruction_proxies_to_be_checked, nearby_index, data.deconstruction_tile_check_index)
    end
  end
  local target = surface.get_closest(drone.position, extra_targets)
  extra_targets[position_hash(target.position)] = nil
  local drone_data =
  {
    order = drone_orders.tile_deconstruct,
    network = network,
    target = target,
    extra_targets = extra_targets
  }
  return set_drone_order(drone, drone_data)
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
  print("Checking repair of an entity: "..entity.name)
  if entity.has_flag("not-repairable") then return true end
  local health = entity.get_health_ratio()
  if not (health and health < 1) then return true end
  local surface = entity.surface
  local force = entity.force
  local networks = surface.find_logistic_networks_by_construction_area(entity.position, force)
  if not next(networks) then print("No networks for this entity") return end
  local repair_items = get_repair_items()
  local repair_item
  local pickup_target
  for k, network in pairs (networks) do
    if data.allow_in_active_networks or network.available_construction_robots == 0 then
      for name, item in pairs (repair_items) do
        if network.get_item_count(name) > 0 then
          pickup_target = network.select_pickup_point({name = name})
          if pickup_target then
            repair_item = item
            break
          end
        end
      end
    end
    if pickup_target then break end
  end
  if not pickup_target then
    print("No pickup target for any repair pack.")
    return
  end

  local chest = pickup_target.owner
  local drones = get_idle_drones(pickup_target.logistic_network)
  local drone = surface.get_closest(chest.position, drones)

  if not drone then
    print("No drone for repair.")
    return
  end

  local drone_data =
  {
    order = drone_orders.repair,
    pickup = {chest = chest, stack = {name = repair_item.name, count = 1}},
    network = pickup_target.logistic_network,
    target = entity,
  }
  set_drone_order(drone, drone_data)
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
  local position = entity.position
  local ghost_name = entity.ghost_name

  local tile_prototype = game.tile_prototypes[ghost_name]
  local point, item = get_point(tile_prototype, entity)

  if not point then
    print("no eligible point with item?")
    return
  end

  local chest = point.owner
  local drones = get_idle_drones(point.logistic_network)
  local drone = surface.get_closest(chest.position, drones)

  if not drone then
    print("No drones for pickup")
    return
  end

  local network = point.logistic_network

  local radius = 2
  local area = {{position.x - radius, position.y - radius}, {position.x + radius, position.y + radius}}
  local count = 0
  local extra_targets = {}
  local extra = surface.find_entities_filtered{type = tile_ghost_type, area = area}
  for k, ghost in pairs (extra) do
    local unit_number = ghost.unit_number
    local should_check = data.tiles_to_be_checked[unit_number] and ghost.ghost_name == ghost_name
    if should_check then
      data.tile_check_index = remove_from_list(data.tiles_to_be_checked, unit_number, data.tile_check_index)
      extra_targets[unit_number] = ghost
      count = count + 1
    end
  end

  local target = surface.get_closest(chest.position, extra_targets)
  extra_targets[target.unit_number] = nil

  local drone_data =
  {
    order = drone_orders.tile_construct,
    pickup = {chest = chest, stack = {name = item.name, count = count}},
    network = network,
    target = target,
    item_used_to_place = item.name,
    extra_targets = extra_targets
  }

  return set_drone_order(drone, drone_data)
end

local check_tile_lists = function()
  --Being lazy... only 1 list for tiles (also probably fine)
  data.tile_check_index = check_list(data.tiles_to_be_checked, data.tile_check_index, check_tile, max_checks_per_tick)
end

local check_no_network_drones = function()
  local drones = data.no_network_drones
  local index = data.drone_check_index

  for k = 1, max_checks_per_tick do
    index = index or next(drones)
    local drone = drones[index]
    if drone then
      --drone.surface.create_entity{name = "flying-text", text = "!", position = drone.position}
      local old_index = index
      index = next(drones, index)
      drones[old_index] = nil
      set_drone_idle(drone)
    end
  end
  data.drone_check_index = index
end

local on_tick = function(event)

  check_ghost_lists()

  check_deconstruction_lists()

  check_repair_lists()

  check_upgrade_lists()

  check_proxies_lists()

  check_tile_lists()

  check_tile_deconstruction_lists()

  check_no_network_drones()
end

local get_build_time = function(drone_data)
  return random(10, 20)
end

local cancel_extra_targets = function(drone_data)
  if not drone_data.extra_targets then return end
  local targets = validate(drone_data.extra_targets)
  local order = drone_data.order

  if order == drone_orders.upgrade then
    for unit_number, entity in pairs (targets) do
      data.upgrade_to_be_checked[unit_number] = {entity = entity, upgrade_prototype = drone_data.upgrade_prototype}
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

  if order == drone_orders.deconstruct then
    for index, entity in pairs (targets) do
      local index = position_hash(entity.position)
      data.deconstructs_to_be_checked[index] = {entity = entity, force = drone_data.entity.force}
      data.sent_deconstruction[index] = (data.sent_deconstruction[index] or 1) - 1
    end
    return
  end

end

local cancel_drone_order = function(drone_data, on_removed)
  local drone = drone_data.entity
  if not (drone and drone.valid) then return end
  local unit_number = drone.unit_number

  print("Drone command cancelled "..unit_number.." - "..game.tick)

  local target = drone_data.target
  if target and target.valid then
    local order = drone_data.order
    local target_unit_number = target.unit_number
    if target_unit_number then
      if data.targets[target_unit_number] then
        data.targets[target_unit_number][unit_number] = nil
        if not next(data.targets[target_unit_number]) then
          data.targets[target_unit_number] = nil
        end
      end
    end

    if order == drone_orders.request_proxy then
      insert(data.proxies_to_be_checked, target)
    elseif order == drone_orders.repair then
      insert(data.repair_to_be_checked, target)
    elseif order == drone_orders.upgrade then
      data.upgrade_to_be_checked[target_unit_number] = {entity = target, upgrade_prototype = drone_data.upgrade_prototype}
    elseif order == drone_orders.construct then
      data.ghosts_to_be_checked[target_unit_number] = target
    elseif order == drone_orders.tile_construct then
      data.tiles_to_be_checked[target_unit_number] = target
    elseif order == drone_orders.deconstruct then
      local index = position_hash(target.position)
      data.deconstructs_to_be_checked[index] = {entity = target, force = drone.force}
      data.sent_deconstruction[index] = (data.sent_deconstruction[index] or 1) - 1
    end
  end

  cancel_extra_targets(drone_data)

  drone_data.pickup = nil
  drone_data.path = nil
  drone_data.dropoff = nil
  drone_data.order = nil
  drone_data.target = nil

  local stack = get_drone_first_stack(drone_data)
  if stack then
    if not on_removed then
      print("Holding a stack, gotta go drop it off... "..unit_number)
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
local random = math.random

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

local move_to_logistic_target = function(drone_data, target)
  local network = get_or_find_network(drone_data)
  if not network then
    return drone_wait(drone_data, 300)
  end
  local cell = target.logistic_cell or network.find_cell_closest_to(target.position)
  if cell.logistic_network ~= network then
    print("Not in same network, goodbye")
    return cancel_drone_order(drone_data)
  end
  local drone = drone_data.entity
  if cell.is_in_construction_range(drone.position) then
    return drone.set_command
    {
      type = defines.command.go_to_location,
      destination_entity = target,
      radius = get_radius(drone) + get_radius(target),
      distraction = defines.distraction.none,
      pathfind_flags = drone_pathfind_flags
    }
  end

  drone_data.path = get_drone_path(drone, network, target)

  return process_drone_command(drone_data)
end

local move_to_order_target = function(drone_data, target, range)
  if in_construction_range(drone_data.entity, target, range) then
    return true
  end
  local network = get_or_find_network(drone_data)
  if not network then
    return drone_wait(drone_data, 300)
  end
  local cell = target.logistic_cell or network.find_cell_closest_to(target.position)
  if not cell.is_in_construction_range(target.position) then
    print("Not in construction range, goodbye")
    return cancel_drone_order(drone_data)
  end
  if cell.logistic_network ~= network then
    print("Not in same network, goodbye")
    return cancel_drone_order(drone_data)
  end
  local drone = drone_data.entity
  if cell.is_in_construction_range(drone.position) then
    return drone.set_command
    {
      type = defines.command.go_to_location,
      destination_entity = target,
      radius = get_radius(drone, range) + get_radius(target),
      distraction = defines.distraction.none,
      pathfind_flags = drone_pathfind_flags
    }
  end

  drone_data.path = get_drone_path(drone, network, target)
  return process_drone_command(drone_data)
end

update_drone_sticker = function(drone_data)

  local sticker = drone_data.sticker
  if sticker and sticker.valid then
    sticker.destroy()
  end

  local inventory = get_drone_inventory(drone_data)

  local stack = inventory[1]
  local item_name = stack and stack.valid and stack.valid_for_read and stack.name
  if not item_name then return end

  local sticker_name = item_name.." Drone Sticker"
  if not game.entity_prototypes[sticker_name] then
    print("No sticker with name sticker_name")
    return
  end
  local drone = drone_data.entity

  drone_data.sticker = drone.surface.create_entity
  {
    name = sticker_name,
    position = drone.position,
    target = drone,
    force = drone.force
  }

end

local process_pickup_command = function(drone_data)
  print("Procesing pickup command")

  --TODO maybe let this find a chest if the target isn't valid... but, cross network stuff etc?
  local chest = drone_data.pickup.chest
  if not (chest and chest.valid) then
    print("Chest for pickup was not valid")
    return cancel_drone_order(drone_data)
  end

  if not move_to_order_target(drone_data, chest, ranges.interact) then
    return
  end


  print("Pickup chest in range, picking up item")
  local stack = drone_data.pickup.stack
  local inventory
  local type = chest.type
  local chest_stack
  local stack_name = stack.name
  local drone_inventory = get_drone_inventory(drone_data)

  local taken = transfer_stack(drone_inventory, chest, stack)
  if taken < stack.count then
    print("The chest didn't have the item we want... or not enough of it")
    drone_data.pickup.chest = nil
    return drone_wait(drone_data, 12)
  end

  update_drone_sticker(drone_data)

  drone_data.pickup = nil
  local drone = drone_data.entity
  local build_time = get_build_time(drone_data)
  drone.surface.create_entity
  {
    name = beams.pickup,
    source = chest,
    target = drone,
    position = drone.position,
    force = drone.force,
    duration = build_time
  }
  return drone_wait(drone_data, build_time)
end

local get_dropoff_stack = function(drone_data)
  local stack = drone_data.dropoff.stack
  if stack and stack.valid and stack.valid_for_read then return stack end
  return get_drone_first_stack(drone_data)
end

local process_dropoff_command = function(drone_data)
  local drone = drone_data.entity
  print("Procesing dropoff command. "..drone.unit_number)


  local chest = drone_data.dropoff.chest

  local stack = get_dropoff_stack(drone_data)
  if not stack then
    print("We didn't have any items anyway, why are we dropping it off??. "..drone.unit_number)
    drone_data.dropoff = nil
    return
  end

  if not (chest and chest.valid) then
    local network = get_or_find_network(drone_data)
    local point
    if network then
      point = network.select_drop_point{stack = stack}
    end
    if not point then
      print("really is nowhere to put it... so just sit and wait...")
      for k, player in pairs (drone.force.connected_players) do
        player.add_alert(drone, defines.alert_type.no_storage)
      end
      return drone_wait(drone_data, 300)
    end
    chest = point.owner
    drone_data.dropoff.chest = chest
  end

  if not move_to_order_target(drone_data, chest, ranges.interact) then
    return
  end

  local name = stack.name

  print("Dropoff chest in range, dropping item. "..drone.unit_number)
  local drone_inventory = get_drone_inventory(drone_data)
  transfer_item(drone_inventory, chest, name)
  print("Dropped stack into the chest. "..drone.unit_number)
  update_drone_sticker(drone_data)

  if not drone_inventory.is_empty() then
    drone_data.dropoff = {stack = get_drone_first_stack(drone_data)}
    --So, players always are valid for robot dropping... so wait a while before chasing the player (if not a player network, it will find another chest...)
    return drone_wait(drone_data, 6)
  end

  local drone = drone_data.entity
  local build_time = get_build_time(drone_data)
  drone.surface.create_entity
  {
    name = beams.pickup,
    source = drone,
    target = chest,
    position = drone.position,
    force = drone.force,
    duration = build_time
  }
  return set_drone_idle(drone)
end

local unit_move_away = function(unit, target, multiplier)
  local multiplier = multiplier or 1
  local r = (get_radius(target) + get_radius(unit)) * (1 + (math.random() * 4))
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
  unit.speed = unit.prototype.speed * (0.95 + (math.random() / 10))
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
    drone_data.extra_targets[next_target.unit_number or position_hash(next_target.position)] = nil
    return next_target
  end
end


local process_construct_command = function(drone_data)
  print("Processing construct command")
  local target = drone_data.target
  if not (target and target.valid) then
    return set_drone_idle(drone_data.entity)
  end

  local drone_inventory = get_drone_inventory(drone_data)
  if drone_inventory.get_item_count(drone_data.item_used_to_place) == 0 then
    return cancel_drone_order(drone_data)
  end

  if not move_to_order_target(drone_data, target, ranges.interact) then
    return
  end


  local drone = drone_data.entity


  local unit_number = target.unit_number
  local success, entity, proxy = target.revive({return_item_request_proxy = true})
  if not success then
    drone_wait(drone_data, 30)
    print("Some idiot might be in the way too ("..drone.unit_number.." - "..game.tick..")")
    local radius = get_radius(target)
    local area = {{target.position.x - radius, target.position.y - radius},{target.position.x + radius, target.position.y + radius}}
    for k, unit in pairs (target.surface.find_entities_filtered{type = "unit", area = area}) do
      print("Telling idiot to MOVE IT ("..drone.unit_number.." - "..game.tick..")")
      unit_clear_target(unit, target)
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
  drone.surface.create_entity
  {
    name = beams.build,
    source = drone,
    target = entity,
    position = drone.position,
    force = drone.force,
    duration = build_time
  }
  return drone_wait(drone_data, build_time)
end

local drone_follow_path = function(drone_data)
  print("I am following path")
  local path = drone_data.path
  local drone = drone_data.entity
  local current_cell = path[1]

  if not (current_cell and current_cell.valid) then
    print("Current cell invalid Setting path nil")
    drone_data.path = nil
    return process_drone_command(drone_data)
  end

  if current_cell.is_in_construction_range(drone.position) then
    print("Current cell in range, incrementing path")
    remove(path, 1)
    return process_drone_command(drone_data)
  end

  print("Moving to current cell owner")
  return drone.set_command
  {
    type = defines.command.go_to_location,
    destination_entity = current_cell.owner,
    radius = math.max(current_cell.construction_radius, current_cell.logistic_radius),
    distraction = defines.distraction.none,
    pathfind_flags = drone_pathfind_flags
  }
end

local random = math.random
local randish = function(value, variance)
  return value + ((random() - 0.5) * variance * 2)
end

local process_failed_command = function(drone_data)
  local drone = drone_data.entity

  --Sometimes they just fail for unrelated reasons, lets give them a few chances
  drone_data.fail_count = (drone_data.fail_count or 0) + 1
  drone.ai_settings.path_resolution_modifier = math.min(3, drone.ai_settings.path_resolution_modifier + 1)
  --game.print("Set resolution: "..drone.ai_settings.path_resolution_modifier)
  if drone_data.fail_count < 10 then
    return drone_wait(drone_data, 10)
  end

  --We REALLY can't get to it or something, tell the player to come sort it out...
  if true then
    drone_data.fail_count = nil
    return cancel_drone_order(drone_data)
  end
  drone.surface.create_entity{name = "tutorial-flying-text", position = drone.position, text = "Oof "..drone.unit_number}
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
  print("Processing deconstruct command")
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

  local index = position_hash(target.position)
  local unit_number = target.unit_number

  local drone = drone_data.entity
  if not drone_data.beam then
    local build_time = get_build_time(drone_data)
    drone_data.beam = drone.surface.create_entity
    {
      name = beams.deconstruction,
      source = drone,
      target_position = target.position,
      position = drone.position,
      force = drone.force,
      duration = build_time
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
  print("Processing repair command")
  local target = drone_data.target
  if not (target and target.valid) then
    return cancel_drone_order(drone_data)
  end

  if target.get_health_ratio() == 1 then
    print("Target is fine... give up on healing him")
    drone_data.target = nil
    drone_data.repair_stack = nil
    drone_data.dropoff = {}
    return cancel_drone_order(drone_data)
  end

  local drone = drone_data.entity

  if not move_to_order_target(drone_data, target, ranges.interact) then
    return
  end

  local drone_inventory = get_drone_inventory(drone_data)
  local stack
  for name, prototype in pairs (get_repair_items()) do
    stack = drone_inventory.find_item_stack(name)
    if stack then break end
  end

  if not stack then
    print("I don't have a repair item... get someone else to do it")
    return cancel_drone_order(drone_data)
  end

  local health = target.health
  local repair_speed = game.item_prototypes[stack.name].speed
  if not repair_speed then
    print("WTF, maybe some migration?")
    drone_data.dropoff = {stack = stack}
    return process_drone_command(drone_data)
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
    print("Stack expired, someone else will take over")
    return cancel_drone_order(drone_data)
  end

  drone.surface.create_entity
  {
    name = beams.build,
    source = drone,
    target = target,
    position = drone.position,
    force = drone.force,
    duration = ticks_to_repair
  }


  return drone_wait(drone_data, ticks_to_repair)
end

local process_upgrade_command = function(drone_data)
  print("Processing upgrade command")

  local target = drone_data.target
  if not (target and target.valid and target.to_be_upgraded()) then
    return cancel_drone_order(drone_data)
  end

  local drone = drone_data.entity

  if not move_to_order_target(drone_data, target, ranges.interact) then
    return
  end

  local surface = drone.surface
  local prototype = drone_data.target_prototype
  local original_name = target.name
  local entity_type = target.type
  local unit_number = target.unit_number
  local neighbor = target.type == "underground-belt" and target.neighbours

  local upgraded = surface.create_entity
  {
    name = prototype.name,
    position = target.position,
    direction = target.direction,
    fast_replace = true,
    force = target.force,
    spill = false,
    type = entity_type == "underground-belt" and target.belt_to_ground_type or nil
  }
  if not upgraded then error("Shouldn't happen, upgrade failed when creating entity... let me know!") return end
  get_drone_inventory(drone_data).remove({name = drone_data.item_used_to_place})
  clear_target_data(unit_number)

  local drone_inventory = get_drone_inventory(drone_data)
  local products = game.entity_prototypes[original_name].mineable_properties.products

  take_product_stacks(drone_inventory, products)

  if neighbour and neighbour.valid then
    print("Upgrading neighbor")
    local neighbor_unit_number = neighbour.unit_number
    local upgraded_neighbour = surface.create_entity
    {
      name = prototype.name,
      position = neighbour.position,
      direction = neighbour.direction,
      fast_replace = true,
      force = neighbour.force,
      spill = false,
      type = entity_type == "underground-belt" and neighbour.belt_to_ground_type or nil
    }
    clear_target_data(neighbor_unit_number)
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
  drone.surface.create_entity
  {
    name = beams.build,
    source = drone,
    target = upgraded,
    position = drone.position,
    force = drone.force,
    duration = build_time
  }
  return drone_wait(drone_data, build_time)
end

local process_request_proxy_command = function(drone_data)
  print("Processing request proxy command")

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
    print("We don't have anything to offer, go pickup something")
    local name, count = next(requests)
    drone_data.pickup = {stack = {name = name, count = count}}
    return process_drone_command(drone_data)
  end

  if not move_to_order_target(drone_data, proxy_target, ranges.interact) then
    return
  end

  print("We are in range, and we have what he wants")

  local stack_name = stack.name
  local position = target.position
  local inserted = proxy_target.insert(stack)
  if inserted == 0 then
    print("Can't insert anything anyway, kill the proxy")
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
  drone.surface.create_entity
  {
    name = beams.pickup,
    source = drone,
    target_position = position,
    position = drone.position,
    force = drone.force,
    duration = build_time
  }

  return drone_wait(drone_data, build_time)
end

local process_construct_tile_command = function(drone_data)
  print("Processing construct tile command")
  local target = drone_data.target
  if not (target and target.valid) then
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

  surface.set_tiles({{name = target.ghost_name, position = position}}, true)

  local drone_inventory = get_drone_inventory(drone_data)
  drone_inventory.remove({name = drone_data.item_used_to_place, count = 1})

  local insert = drone_inventory.insert
  if products then
    for k, product in pairs (products) do
      insert(stack_from_product(product))
    end
    drone_data.dropoff = {}
  end

  update_drone_sticker(drone_data)
  local drone = drone_data.entity

  drone_data.target = get_extra_target(drone_data)

  local build_time = get_build_time(drone_data)
  drone.surface.create_entity
  {
    name = beams.build,
    source = drone,
    target_position = position,
    position = drone.position,
    force = drone.force,
    duration = build_time
  }
  return drone_wait(drone_data, build_time)
end

local process_deconstruct_tile_command = function(drone_data)
  print("Processing deconstruct tile command")
  local target = drone_data.target
  if not (target and target.valid) then
    print("Target was not valid...")
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
    surface.create_entity
    {
      name = beams.deconstruction,
      source = drone,
      target_position = position,
      position = drone.position,
      force = drone.force,
      duration = build_time
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
      insert(stack_from_product(product))
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
  print("Processing deconstruct cliff command")
  local target = drone_data.target

  if not (target and target.valid) then
    print("Target cliff was not valid. ")
    return cancel_drone_order(drone_data)
  end

  local drone = drone_data.entity

  if not move_to_order_target(drone_data, target, ranges.interact) then
    return
  end

  if not drone_data.beam then
    local drone = drone_data.entity
    local build_time = get_build_time(drone_data)
    drone.surface.create_entity
    {
      name = beams.deconstruction,
      source = drone,
      target_position = target.position,
      position = drone.position,
      force = drone.force,
      duration = build_time
    }
    drone_data.beam = true
    return drone_wait(drone_data, build_time)
  else
    drone_data.beam = nil
  end

  get_drone_inventory(drone_data).remove{name = target.prototype.cliff_explosive_prototype, count = 1}
  target.surface.create_entity{name = "ground-explosion", position = util.center(target.bounding_box)}
  target.destroy()
  print("Cliff destroyed, heading home bois. ")
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

local process_follow_command = function(drone_data)

  local target = drone_data.target
  if not (target and target.valid and target.logistic_network) then
    return cancel_drone_order(drone_data)
  end

  local check_time = random(20, 40)

  if not move_to_order_target(drone_data, drone_data.target, ranges.follow) then
    return
  end

  local drone = drone_data.entity
  if target.type == "player" then
    local player = target.player
    if player then
      local state = player.walking_state
      if state.walking then
        local offset = directions[state.direction]
        local target_speed = target.character_running_speed
        local new_position = {drone.position.x + (offset[1] * check_time * target_speed), drone.position.y + (offset[2] * check_time * target_speed)}
        drone.speed = math.min(drone.prototype.speed, target_speed * (check_time / (check_time - 1)))
        return drone.set_command
        {
          type = defines.command.go_to_location,
          radius = 1,
          distraction = defines.distraction.none,
          destination = drone.surface.find_non_colliding_position(drone.name, new_position, 0, 1)
        }
      end
    end
  end

  --todo wander in a random direction...
  drone.speed = drone.prototype.speed * ((random() * 0.5) + 0.5)
  return drone_data.entity.set_command
  {
    type = defines.command.wander,
    distraction = defines.distraction.none,
    ticks_to_wait = check_time,
  }
end


process_drone_command = function(drone_data, result)
  local drone = drone_data.entity
  if not (drone and drone.valid) then
    error("Drone entity not valid when processing its own command!\n"..serpent.block(drone_data))
  end

  local print = function(string)
    print(string.. " | "..drone.unit_number)
  end
  print("Processing drone command")

  drone.speed = drone.prototype.speed

  if (result == defines.behavior_result.fail) then
    print("Fail")
    return process_failed_command(drone_data)
  end

  if drone_data.path then
    print("Path")
    return drone_follow_path(drone_data)
  end

  if drone_data.pickup then
    print("Pickup")
    return process_pickup_command(drone_data)
  end

  if drone_data.dropoff then
    print("Dropoff")
    return process_dropoff_command(drone_data)
  end

  if drone_data.order == drone_orders.construct then
    print("Construct")
    return process_construct_command(drone_data)
  end

  if drone_data.order == drone_orders.deconstruct then
    print("Deconstruct")
    return process_deconstruct_command(drone_data)
  end

  if drone_data.order == drone_orders.repair then
    print("Repair")
    return process_repair_command(drone_data)
  end

  if drone_data.order == drone_orders.upgrade then
    print("Upgrade")
    return process_upgrade_command(drone_data)
  end

  if drone_data.order == drone_orders.request_proxy then
    print("Request proxy")
    return process_request_proxy_command(drone_data)
  end

  if drone_data.order == drone_orders.tile_construct then
    print("Tile Construct")
    return process_construct_tile_command(drone_data)
  end

  if drone_data.order == drone_orders.tile_deconstruct then
    print("Tile Deconstruct")
    return process_deconstruct_tile_command(drone_data)
  end

  if drone_data.order == drone_orders.cliff_deconstruct then
    print("Cliff Deconstruct")
    return process_deconstruct_cliff_command(drone_data)
  end

  if drone_data.order == drone_orders.follow then
    print("Follow")
    return process_follow_command(drone_data)
  end

  print("Nothin")
  return set_drone_idle(drone)
end

local on_ai_command_completed = function(event)
  local drone_data = data.drone_commands[event.unit_number]
  if drone_data then
    print("Drone command complete event: "..event.unit_number.." = "..tostring(result ~= defines.behavior_result.fail))
    return process_drone_command(drone_data, event.result)
  end
end

local on_entity_removed = function(event)
  local entity = event.entity or event.ghost
  print("On removed event fired: "..entity.name.." - "..game.tick)
  if not (entity and entity.valid) then return end
  local unit_number = entity.unit_number
  if not unit_number then return end

  if is_commandable(entity.name) then
    remove_idle_drone(entity)
    local drone_data = data.drone_commands[unit_number]
    if drone_data then
      cancel_drone_order(drone_data, true)
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
    data.deconstruction_proxies_to_be_checked[position_hash(entity.position)] = entity
  else
    data.deconstructs_to_be_checked[position_hash(entity.position)] = {entity = entity, force = force}
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

local shoo = function(event)
  local player = game.players[event.player_index]
  if not (player and player.valid) then return end
  local radius = 16
  local target = player.selected or player.character
  local position = target and target.position or player.position
  local area = {{position.x - radius, position.y - radius},{position.x + radius, position.y + radius}}
  for k, unit in pairs(player.surface.find_entities_filtered{area = area, type = "unit", force = player.force}) do
    unit_move_away(unit, target, 4)
  end
  player.surface.play_sound{path = "shoo", position = player.position}
end

local on_marked_for_upgrade = function(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  local upgrade_data = {entity = entity, upgrade_prototype = event.target}
  data.upgrade_to_be_checked[entity.unit_number] = upgrade_data
end

local on_unit_idle = function(event)
  --game.print("UNIT IDLE")
  local unit = event.entity
  if not (unit and unit.valid) then return end
  if not is_commandable(unit.name) then return end
  local unit_number = unit.unit_number
  if not unit_number then return end
  set_drone_idle(unit)
end

local on_unit_not_idle = function(event)
  --game.print("UNIT NOT IDLE")
  local unit = event.entity
  if not (unit and unit.valid) then return end
  if not is_commandable(unit.name) then return end
  local unit_number = unit.unit_number
  if not unit_number then return end
  local drone_data = data.drone_commands[unit_number]
  if drone_data then
    data.drone_commands[unit_number] = nil
    cancel_drone_order(drone_data, true)
  end
  remove_idle_drone(unit)
end

local lib = {}

local events =
{
  [defines.events.on_built_entity] = on_built_entity,
  [defines.events.on_tick] = on_tick,
  [defines.events.on_ai_command_completed] = on_ai_command_completed,
  [defines.events.on_entity_died] = on_entity_removed,
  [defines.events.on_robot_mined_entity] = on_entity_removed,
  [defines.events.on_player_mined_entity] = on_entity_removed,
  [defines.events.on_marked_for_deconstruction] = on_marked_for_deconstruction,
  [defines.events.on_pre_ghost_deconstructed] = on_entity_removed,
  [defines.events.on_post_entity_died] = on_built_entity,
  [defines.events.on_entity_damaged] = on_entity_damaged,
  [defines.events.on_marked_for_upgrade] = on_marked_for_upgrade,
  [names.hotkeys.shoo]  = shoo
}

local register_events = function()
  lib.on_event = handler(events)
  if remote.interfaces["unit_control"] then
    local unit_control_events = remote.call("unit_control", "get_events")
    events[unit_control_events.on_unit_idle] = on_unit_idle
    events[unit_control_events.on_unit_not_idle] = on_unit_not_idle
  end
end

lib.on_load = function()
  data = global.construction_drone or data
  global.construction_drone = data
  register_events()
end

lib.on_init = function()
  game.map_settings.steering.default.force_unit_fuzzy_goto_behavior = true
  game.map_settings.steering.moving.force_unit_fuzzy_goto_behavior = true
  global.construction_drone = global.construction_drone or data
  data.ghosts_to_be_checked_again = {}
  for k, surface in pairs (game.surfaces) do
    for k, ghost in pairs (surface.find_entities_filtered{type = "entity-ghost"}) do
      data.ghosts_to_be_checked_again[ghost.unit_number] = ghost
    end
  end
  register_events()
  if remote.interfaces["unit_control"] then
    --remote.call("unit_control", "register_unit_unselectable", drone_name)
  end
end

lib.on_configuration_changed = function()
  if remote.interfaces["unit_control"] then
    --remote.call("unit_control", "register_unit_unselectable", drone_name)
  end
end

lib.get_events = function() return events end

return lib
