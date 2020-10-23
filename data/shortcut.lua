local path = util.path("data/units/construction_drone/")

local icon = 
{
  filename = path.."construction_drone_icon.png",
  priority = "extra-high-no-scale",
  size = 64,
  scale = 1,
  flags = {"icon"},
}

data:extend(
  {
    {
      type = "shortcut",
      name = "construction-drone-toggle",
      associated_control_input = "construction-drone-toggle",
      localised_name = "Toggle Construction drones",
      order = "a[construction-drones]",
      action = "lua",
      style = "default",
      icon = icon,
      small_icon = icon,
      disabled_small_icon = icon,
      toggleable = true
    }
  }
)