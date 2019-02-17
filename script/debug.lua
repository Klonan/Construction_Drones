local names = names
local get_position = function(n)
  local root = n^0.5
  local nearest_root = math.floor(root+0.5)
  local upper_root = math.ceil(root)
  local root_difference = math.abs(nearest_root^2 - n)
  if nearest_root == upper_root then
    x = upper_root - root_difference
    y = nearest_root
  else
    x = upper_root
    y = root_difference
  end
  --game.print(x.." - "..y)
  return {x, y}
end

local on_player_created = function(event)
  if true then return end
  local player = game.players[event.player_index]
  player.force = "player"
  --player.insert(names.entities.buy_chest)
  --player.insert(names.entities.sell_chest)
  --if true then return end
  --player.surface.create_entity{name = "small-biter", position = {-10, 10}}
  --player.surface.create_entity{name = "small-biter", position = {-10, 10}}
  --player.surface.create_entity{name = "small-biter", position = {-10, 10}}
  --player.surface.create_entity{name = "small-biter", position = {-10, 10}}
  if player.character then player.character.destroy() end

  --if true then return {} end
  local team1 = {
    --scout_car = 20,
    --beetle = 80,
    --plasma_bot = 1,
    --tazer_bot = 20,
    blaster_bot = 500
    --shell_tank = 500,
    --plasma_bot = 10,
    --acid_worm = 20,
    --piercing_biter = 50
    --scatter_spitter = 20
    --smg_guy = 30,
    --rocket_guy = 1000
  }
  local pos = {x = -40, y = 0}
    for name, count in pairs (team1) do
      for x = 1, count do
        local vec = get_position(math.random(400))
        player.surface.create_entity{name = names.units[name], position = {pos.x + vec[1], pos.y + vec[2]}, force = "player"}
      end
    end


    --if true then return end

  team2 = {
    --beetle = 200,
    --plasma_bot = 10,
    --blaster_bot = 30,
    --laser_bot = 20,
    --tazer_bot = 100,
    --smg_guy = 30,
    --scout_car = 30,
    --rocket_guy = 20,
    --shell_tank = 80
    --scatter_spitter = 100,
    --piercing_biter = 30,
    --rocket_guy = 30,
    --laser_bot = 20
    --acid_worm = 50
  }
  local pos = {x = 20, y = 0}
  for name, count in pairs (team2) do
    for x = 1, count do
      local vec = get_position(math.random(400))
      player.surface.create_entity{name = names.units[name], position = {pos.x + vec[1], pos.y + vec[2]}, force = "enemy"}
    end
  end

end

local events =
{
  [defines.events.on_player_created] = on_player_created
}

local debug = {}

debug.get_events = function() return events end

debug.on_init = function()
  for k, surface in pairs (game.surfaces) do
    surface.always_day = true
  end
  debug.on_event = handler(events)
end

debug.on_load = function()
  debug.on_event = handler(events)
end

return debug
