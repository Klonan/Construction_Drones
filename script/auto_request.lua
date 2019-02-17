-- sigh... another mini mod to waste my time on
local get_burners = function()
  if burners then return burners end
  --deliberately not local
  burners = {}
  for name, entity in pairs (game.entity_prototypes) do
    if entity.burner_prototype then
      burners[name] = entity.burner_prototype
    end
  end
  return burners
end

local get_fuel = function()
  if fuel then return fuel end
  --deliberately not local
  fuel = {}
  for name, item in pairs (game.item_prototypes) do
    if item.fuel_value > 0 and item.fuel_category then
      fuel[item.fuel_category] = fuel[item.fuel_category] or {}
      fuel[item.fuel_category][name] = true
    end
  end
  return fuel
end

local get_category_items = function(categories)
  local items = {}
  for category_name, bool in pairs (categories) do
    for item_name, bool in pairs (get_fuel()[category_name] or {}) do
      items[item_name] = true
    end
  end
  return items
end

local get_fuel_item = function(entity, burner)
  local networks = entity.surface.find_logistic_networks_by_construction_area(entity.position, entity.force)

  local category_items = get_category_items(burner.fuel_categories)
  local item
  local count = 0
  for k, network in pairs(networks) do
    local contents = network.get_contents()
    for item_name, bool in pairs (category_items) do
      local item_count = contents[item_name] or 0
      if item_count > count then
        item = item_name
        count = item_count
      end
    end
  end
  return item
end

local ghost_built = function(entity)

  local burner = get_burners()[entity.ghost_name]
  if not burner then return end

  local item_name = get_fuel_item(entity, burner)
  if not item_name then return end

  local requests = entity.item_requests
  requests[item_name] = 5
  entity.item_requests = requests
end
local ghost_type = "entity-ghost"
local on_built_entity = function(event)
  local entity = event.created_entity
  if not (entity and entity.valid) then return end

  if entity.type == ghost_type then
    return ghost_built(entity)
  end

  local burner = get_burners()[entity.name]
  if not burner then return end

  local item_name = get_fuel_item(entity, burner)
  if not item_name then return end

  entity.surface.create_entity
  {
    name = "item-request-proxy",
    position = entity.position,
    force = entity.force,
    target = entity,
    modules = {[item_name] = 5}
  }

end

local events =
{
  [defines.events.on_built_entity] = on_built_entity
}


local lib = {}
lib.on_event = handler(events)
lib.get_events = function() return events end
return lib
