local hotkeys = names.hotkeys

local shoo =
{
  type = "custom-input",
  name = hotkeys.shoo,
  localised_names = hotkeys.shoo,
  key_sequence = "SHIFT + ]",
  consuming = "game-only"
}

data:extend
{
  shoo
}