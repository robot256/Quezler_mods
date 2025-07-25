local Crafter = {}

local function get_name_quality_key(item)
  return assert(item.quality) .. " " .. assert(item.name)
end

local function add_contents_to_map(contents, map)
  for _, content in ipairs(contents) do
    if content.type ~= "fluid" then
      local key = get_name_quality_key(content)
      local mapped = map[key]
      if mapped then
        mapped.count = mapped.count + content.count
      else
        map[key] = {
          name = content.name,
          quality = content.quality,
          count = content.count,
        }
      end
    end
  end
end

-- returns true if map a had all of map b
local function map_subtract(map_a, map_b)
  for key, item_b in pairs(map_b) do
    local item_a = map_a[key]
    if not item_a then return end

    item_a.count = item_a.count - item_b.count
    if 0 > item_a.count then return end
  end

  return true
end

local function map_has(map_a, map_b)
  for key, item_b in pairs(map_b) do
    local item_a = map_a[key]
    if item_a then return true end
  end
end

Crafter.craft = function(building)
  local factory = storage.factories[building.factory_index]

  local contents_map = {}
  add_contents_to_map(building.inventory.get_contents(), contents_map)
  -- log(serpent.block(contents_map))

  local buildings_map = {}
  add_contents_to_map(factory.export.entities, buildings_map)
  add_contents_to_map(factory.export.modules, buildings_map)
  -- log(serpent.block(buildings_map))

  -- circuits only trigger this method when all item requests are fulfilled,
  -- but we do have to confirm everything is here, we'll start with the buildings:
  -- (we're also subtracting them from the contents to avoid using them as ingredients)
  if not map_subtract(contents_map, buildings_map) then
    Buildings.set_status(building, "[img=utility/status_not_working] suddenly not enough buildings")
    return
  end

  local output_map = {}
  add_contents_to_map(factory.export.products, output_map)
  add_contents_to_map(factory.export.byproducts, output_map)

  if map_has(contents_map, output_map) then
    Buildings.set_status(building, "[img=utility/status_yellow] output full")
    return
  end

  -- for _, ingredient in pairs(factory.export.ingredients) do
  --   if ingredient.type == "fluid" then
  --     print(ingredient.name)
  --     local fluidbox = building.children.crafter_b.fluidbox
  --     for index = 1, #fluidbox do
  --       local fluid = fluidbox.get_fluid_segment_contents(index)
  --       if next(fluid) and fluid[ingredient.name] then
  --         log(string.format("index %d has %g %s", index, fluid[ingredient.name], ingredient.name))
  --       end
  --     end
  --     return
  --   end
  -- end

  local ingredients_map = {}
  add_contents_to_map(factory.export.ingredients, ingredients_map)
  if not map_subtract(contents_map, ingredients_map) then
    Buildings.set_status(building, "[img=utility/status_not_working] suddenly not enough ingredients")
    return
  end

  -- item ingredients
  for _, ingredient in pairs(ingredients_map) do
    local buffer = building.item_input_buffer[get_name_quality_key(ingredient)]
    local top_up_with = math.ceil(ingredient.count - buffer.count)

    if top_up_with > 0 then
      local removed = building.inventory.remove({name = ingredient.name, count = top_up_with, quality = ingredient.quality})
      assert(removed == top_up_with, string.format("failed to remove %g × %s (%s), only %g succeeded", top_up_with, ingredient.name, ingredient.quality, removed))
      building.item_statistics.on_flow(ingredient.name, -top_up_with)
      buffer.count = buffer.count + removed - ingredient.count
    end
  end

  -- item products
  for _, product in pairs(output_map) do
    local buffer = building.item_output_buffer[get_name_quality_key(product)]
    buffer.count = buffer.count + product.count

    local payout = math.floor(buffer.count)
    if payout > 0 then
      local inserted = building.inventory.insert({name = product.name, count = payout, quality = product.quality})
      assert(inserted == payout, string.format("failed to insert %g × %s (%s), only %g succeeded", payout, product.name, product.quality, inserted))
      building.item_statistics.on_flow(product, payout)
      buffer.count = buffer.count - payout
    end
  end

  building.entity.surface.pollute(building.entity.position, factory.export.pollution * prefix_to_multiplier(factory.export.pollution_prefix))

  Buildings.set_status(building, "[img=utility/status_working] working")
end

-- ensure the buffers exist so we do not need to check for their prescence first each time,
-- unused buffers persist for as long as the building does, lost completely upon deconstruction.
Crafter.inflate_buffers = function(building)
  local factory = storage.factories[building.factory_index]

  for _, ingredient in ipairs(factory.export.ingredients) do
    if ingredient.type == "fluid" then
      building.fluid_input_buffer[ingredient.name] = (building.fluid_input_buffer[ingredient.name] or 0)
    else
      local key = get_name_quality_key(ingredient)
      if not building.item_input_buffer[key] then
        building.item_input_buffer[key] = {name = ingredient.name, count = 0}
      end
    end
  end

  for _, product in ipairs(factory.export.products) do
    if product.type == "fluid" then
      building.fluid_output_buffer[product.name] = (building.fluid_output_buffer[product.name] or 0)
    else
      local key = get_name_quality_key(product)
      if not building.item_output_buffer[key] then
        building.item_output_buffer[key] = {name = product.name, count = 0}
      end
    end
  end

  for _, byproduct in ipairs(factory.export.byproducts) do
    if byproduct.type == "fluid" then
      building.fluid_output_buffer[byproduct.name] = (building.fluid_output_buffer[byproduct.name] or 0)
    else
      local key = get_name_quality_key(byproduct)
      if not building.item_output_buffer[key] then
        building.item_output_buffer[key] = {name = byproduct.name, count = 0}
      end
    end
  end
end

return Crafter
