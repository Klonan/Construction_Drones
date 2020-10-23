--Shared data interface between data and script, notably prototype names.

local data = {}

data.units =
{
  construction_drone = "Construction Drone",
}

data.technologies =
{
  construction_drone_system = "Construction Drone System"
}

data.entities =
{
  logistic_beacon = "Logistic Beacon",
  simple_storage_chest = "Simple Storage Chest",
  simple_provider_chest = "Simple Provider Chest",
  construction_drone_proxy_chest = "Construction Drone Proxy Chest"
}

data.equipment =
{
  drone_port = "Personal Drone Port"
}

data.beams =
{
  build = "Build beam",
  deconstruction = "Deconstruct Beam",
  pickup = "Pickup Beam",
  dropoff = "Dropoff Beam",
  attack = "Attack Beam"
}

return data
