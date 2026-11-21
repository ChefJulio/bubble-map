local ADDON_NAME, ns = ...

-- The enclosed cities (Ironforge, Undercity) drawn into our maps: the minimap images of the city's own
-- model (Data/Cities.lua), where the terrain tiles have only the mountain above (review: "paste the IF
-- and UC terrains over their spot"). Views: the minimap (Terrain.lua) and the map window (MapWindow.lua).
--
-- Drawn as TerrainWorldMap draws them (its TWM_WMOOverlay_Update; MIT, credited): each image at its
-- centre, its texture coordinates turned a quarter (the game bakes these images turned 90 degrees, so
-- width and height swap), then rotated by minus its angle; on a turning minimap, by the turn as well.
-- Their screen axes match ours (east right, north up), so the centre projects as any world point.
--
-- Floors: images are kept in height order (the data's z: the placement's height plus its group's lowest
-- point) and only those up to ABOVE_YARDS over your feet are drawn, so a floor above you doesn't hide
-- the one you're on (Undercity stacks several). Stacking: one frame, the draw layers and sublevels in
-- height order (64 slots; the images are bucketed into them).

local ABOVE_YARDS = 6
local SLOTS = { "BACKGROUND", "BORDER", "ARTWORK", "OVERLAY" }  -- x 16 sublevels (-8 .. 7)
local PIVOT = { x = 0.5, y = 0.5 }

local MapCities = {}
MapCities.__index = MapCities
ns.MapCities = MapCities

---A view drawing into `parent` (which shows, hides and clips it).
---@param parent Frame
---@return table
function MapCities.New(parent)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetAllPoints()
  return setmetatable({ frame = frame, textures = {}, used = 0 }, MapCities)
end

function MapCities:Texture(i)
  local t = self.textures[i]
  if not t then
    t = self.frame:CreateTexture(nil, "BACKGROUND")
    t:SetSnapToPixelGrid(false)
    t:SetTexelSnappingBias(0)
    t:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)  -- the quarter turn (TWM_WMOOverlay_EnsureTexture)
    self.textures[i] = t
  end
  return t
end

---Hide everything.
function MapCities:Hide()
  for i = 1, self.used do
    self.textures[i]:Hide()
  end
  self.used = 0
end

---Draw the cities around world (north, west) on instance map `map`, `s` pixels a yard, turned by
---`turn` radians; `feet`: your height (nil: every floor).
---@param north number
---@param west number
---@param map number
---@param s number
---@param turn number
---@param feet number?
function MapCities:Draw(north, west, map, s, turn, feet)
  local cities = ns.Cities.maps[map]
  local count = 0
  if cities then
    local w, h = self.frame:GetWidth(), self.frame:GetHeight()
    local reach = math.sqrt(w * w + h * h) / 2 / s  -- yards from the centre to a corner
    local cos, sin = math.cos(turn), math.sin(turn)
    for _, city in pairs(cities) do
      local box = city.box
      if west - reach <= box[1] and west + reach >= box[3] and north - reach <= box[2] and north + reach >= box[4] then
        local tiles = city.tiles
        local n = #tiles
        for i = 1, n do
          local tile = tiles[i]
          if not feet or tile[7] <= feet + ABOVE_YARDS then
            local x, y = (west - tile[2]) * s, (tile[3] - north) * s
            local half = math.max(tile[4], tile[5]) * s
            if math.abs(x) - half <= reach * s and math.abs(y) - half <= reach * s then
              count = count + 1
              local t = self:Texture(count)
              if t.file ~= tile[1] then
                t.file = tile[1]
                t:SetTexture(tile[1])
              end
              -- Height order into the 64 draw slots (the tiles are sorted by height).
              local slot = math.floor((i - 1) / n * 64)
              t:SetDrawLayer(SLOTS[math.floor(slot / 16) + 1], slot % 16 - 8)
              t:ClearAllPoints()
              t:SetPoint("CENTER", self.frame, "CENTER", x * cos + y * sin, -x * sin + y * cos)
              t:SetSize(tile[5] * s, tile[4] * s)  -- swapped with the quarter turn
              t:SetRotation(math.rad(-tile[6]) - turn, PIVOT)
              t:Show()
            end
          end
        end
      end
    end
  end
  for i = count + 1, self.used do
    self.textures[i]:Hide()
  end
  self.used = count
end
