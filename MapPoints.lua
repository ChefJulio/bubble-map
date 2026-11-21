local ADDON_NAME, ns = ...

-- Blizzard's map points on our map window (MapWindow.lua): flight masters, zone exits, dungeon
-- entrances and area points (events, landmarks), from the same calls Blizzard's world map uses for them
-- (Blizzard_SharedMapDataProviders: FlightPointDataProvider, MapLinkDataProvider,
-- DungeonEntranceDataProvider, AreaPOIDataProvider), with their icons and a tooltip.
--
-- Those calls take a UI map and give positions on it (0..1). Our window is one continent in world
-- yards, so a continent's points are gathered from its UI map and every zone under it (some only show
-- on the zone's map), deduplicated by ID, and turned into world positions once
-- (C_Map.GetWorldPosFromMapPos: x north, y west). Kept per continent until the game says they changed
-- (AREA_POIS_UPDATED, TAXI_NODE_STATUS_CHANGED) or the window opens again.
--
-- Flight masters of the other faction are left out, as Blizzard does; undiscovered ones are dimmed.

local ICON_MAX = 20           -- pixels: atlases are drawn at their size, the largest side capped here
local POI_ICON = 16           -- Interface/Minimap/POIIcons cells (an area point without an atlas)
local HOVER_RADIUS = 9
local ATLAS_WITH_KIT = "%s-%s"  -- Blizzard's ATLAS_WITH_TEXTURE_KIT_PREFIX

local Points = {}
ns.MapPoints = Points

local continents = {}  -- instance map -> its continent's UI map
local cache = {}       -- instance map -> { point, ... }
local EMPTY = {}

local function invalidate()
  wipe(cache)
end
ns.On("AREA_POIS_UPDATED", invalidate)
ns.On("TAXI_NODE_STATUS_CHANGED", invalidate)

local function continentOf(uiMap)
  local id = uiMap
  while id and id ~= 0 do
    local info = C_Map.GetMapInfo(id)
    if not info then
      return nil
    end
    if info.mapType == Enum.UIMapType.Continent then
      return info.mapID
    end
    id = info.parentMapID
  end
end

---The continent UI map that instance map `map` is drawn on, found from a world point on it (or the
---player's map when they're there); nil when there is none (the point is out at sea and the player
---elsewhere). Kept once found.
---@param map number
---@param north number
---@param west number
---@return number?
function Points.Continent(map, north, west)
  local found = continents[map]
  if found then
    return found
  end
  found = continentOf((C_Map.GetMapPosFromWorldPos(map, CreateVector2D(north, west))))
  if not found then
    local _, _, _, playerMap = UnitPosition("player")
    if playerMap == map then
      found = continentOf(C_Map.GetBestMapForUnit("player"))
    end
  end
  continents[map] = found
  return found
end

-- An atlas with its texture kit, when the kit has its own (Blizzard formats the two together).
local function kitAtlas(atlas, kit)
  if atlas and kit and kit ~= "" then
    local withKit = ATLAS_WITH_KIT:format(kit, atlas)
    if C_Texture.GetAtlasInfo(withKit) then
      return withKit
    end
  end
  return atlas
end

local function gather(map, continent)
  local list, seen = {}, {}
  local function add(key, uiMap, position, point)
    if seen[key] or not position then
      return
    end
    local cont, world = C_Map.GetWorldPosFromMapPos(uiMap, position)
    if cont ~= map or not world then
      return
    end
    seen[key] = true
    point.north, point.west = world.x, world.y
    list[#list + 1] = point
  end

  local uiMaps = { continent }
  for _, child in ipairs(C_Map.GetMapChildrenInfo(continent, Enum.UIMapType.Zone, true) or {}) do
    uiMaps[#uiMaps + 1] = child.mapID
  end
  local faction = UnitFactionGroup("player")
  for _, uiMap in ipairs(uiMaps) do
    if C_TaxiMap.ShouldMapShowTaxiNodes(uiMap) then
      for _, node in ipairs(C_TaxiMap.GetTaxiNodesForMap(uiMap)) do
        local mine = (node.faction ~= Enum.FlightPathFaction.Horde or faction == "Horde")
          and (node.faction ~= Enum.FlightPathFaction.Alliance or faction == "Alliance")
        if mine then
          add("t" .. node.nodeID, uiMap, node.position, {
            kind = "flight", atlas = kitAtlas(node.atlasName, node.textureKit), name = node.name,
            note = node.isUndiscovered and "Undiscovered flight point" or "Flight point",
            dim = node.isUndiscovered,
          })
        end
      end
    end
    -- Zone exits: the green arrows at a zone's edge to the next (MapLinkDataProvider.lua).
    for _, link in ipairs(C_Map.GetMapLinksForMap(uiMap) or {}) do
      add("l" .. link.areaPoiID, uiMap, link.position, {
        kind = "link", atlas = link.atlasName, name = link.name, note = "Way to " .. (link.name or "the next zone"),
      })
    end
    for _, entrance in ipairs(C_EncounterJournal.GetDungeonEntrancesForMap(uiMap)) do
      add("d" .. entrance.areaPoiID, uiMap, entrance.position, {
        kind = "dungeon", atlas = entrance.atlasName, name = entrance.name, note = entrance.description,
      })
    end
    for _, id in ipairs(C_AreaPoiInfo.GetAreaPOIForMap(uiMap)) do
      local poi = C_AreaPoiInfo.GetAreaPOIInfo(uiMap, id)
      if poi then
        add("a" .. id, uiMap, poi.position, {
          kind = "area", atlas = poi.atlasName, index = poi.textureIndex, name = poi.name, note = poi.description,
        })
      end
    end
  end
  return list
end

---The points on instance map `map` (world north, west each), or an empty list off a known continent.
---@param map number
---@param north number a world point on it, to find its continent
---@param west number
---@return table
function Points.For(map, north, west)
  local list = cache[map]
  if not list then
    local continent = Points.Continent(map, north, west)
    if not continent then
      return EMPTY
    end
    list = gather(map, continent)
    cache[map] = list
  end
  return list
end

---Forget the points, so they're gathered again (the window reopening).
function Points.Refresh()
  invalidate()
end

-- Live points ---------------------------------------------------------------------------------------
-- What changes as you play, read again every LIVE_SECONDS: your corpse (C_DeathInfo, as the world map's
-- DeathMapDataProvider), the graveyards while you're dead (SelectableGraveyardDataProvider), and rares and
-- treasures (vignettes, C_VignetteInfo, as the minimap and the world map show them). Positions on your
-- zone's map, so only around you. A point keeps its table while it lasts (its texture stays set).

local LIVE_SECONDS = 1
local CORPSE_COORDS = { 0.56640625, 0.6328125, 0.001953125, 0.03515625 }  -- POIIcons (CorpsePinTemplate)
local live = { at = -1, map = nil, list = {} }
local liveByKey = {}

local function readable(v)
  return v ~= nil and not issecretvalue(v)
end

---The live points on instance map `map` (world north, west each); `north`, `west` a point on it.
---@param map number
---@param north number
---@param west number
---@return table
function Points.Live(map, north, west)
  if live.map == map and GetTime() - live.at < LIVE_SECONDS then
    return live.list
  end
  local list, keys = {}, {}
  local function put(key, uiMap, position, fields)
    if not position then
      return
    end
    local cont, world = C_Map.GetWorldPosFromMapPos(uiMap, position)
    if cont ~= map or not world then
      return
    end
    local point = liveByKey[key]
    if not point or point.atlas ~= fields.atlas or point.index ~= fields.index or point.dim ~= fields.dim then
      point = fields  -- new, or its icon changed: a new table (a new texture set up)
      point.live = true
      liveByKey[key] = point
    else
      point.name, point.note = fields.name, fields.note
    end
    point.north, point.west = world.x, world.y
    keys[key] = true
    list[#list + 1] = point
  end

  local here = C_Map.GetBestMapForUnit("player")
  local continent = Points.Continent(map, north, west)
  for _, uiMap in ipairs({ here or 0, continent or 0 }) do
    local corpse = uiMap ~= 0 and C_DeathInfo.GetCorpseMapPosition(uiMap)
    if corpse then
      put("corpse", uiMap, corpse, { kind = "corpse", texture = "Interface/Minimap/POIIcons",
        coords = CORPSE_COORDS, name = "Your corpse" })
      break
    end
  end
  -- apiguard: allow its result is checked with issecretvalue (readable) before use
  local dead = UnitIsDeadOrGhost("player")
  if here and readable(dead) and dead then
    for _, grave in ipairs(C_DeathInfo.GetGraveyardsForMap(here) or {}) do
      put("g" .. grave.graveyardID, here, grave.position, { kind = "corpse", index = grave.textureIndex,
        name = grave.name, note = "Graveyard" })
    end
  end
  if here then
    for _, guid in ipairs(C_VignetteInfo.GetVignettes() or {}) do
      if readable(guid) then
        local info = C_VignetteInfo.GetVignetteInfo(guid)
        if info and (info.onWorldMap or info.onMinimap) and readable(info.name) and readable(info.atlasName) then
          put("v" .. guid, here, C_VignetteInfo.GetVignettePosition(guid, here), { kind = "vignette",
            atlas = info.atlasName, name = info.name, dim = info.isDead })
        end
      end
    end
  end
  for key in pairs(liveByKey) do
    if not keys[key] then
      liveByKey[key] = nil
    end
  end
  live.map, live.at, live.list = map, GetTime(), list
  return list
end

-- The layer ---------------------------------------------------------------------------------------

local Layer = {}
Layer.__index = Layer

---A layer of points over `frame` (which should clip its children); its frame takes no mouse.
---@param frame Frame
---@return table
function Points.NewLayer(frame)
  local layer = CreateFrame("Frame", nil, frame)
  layer:SetAllPoints()
  layer:EnableMouse(false)
  -- icons: point -> texture; free: textures of points gathered again (the list replaced).
  return setmetatable({ frame = layer, icons = {}, free = {}, shown = {}, hovering = false }, Layer)
end

-- A texture per point (a continent has a few hundred at most), set up once: panning only moves them.
function Layer:Icon(point)
  local t = self.icons[point]
  if not t then
    t = table.remove(self.free) or self.frame:CreateTexture(nil, "ARTWORK")
    self.icons[point] = t
    local set = false
    if point.atlas and C_Texture.GetAtlasInfo(point.atlas) then
      t:SetAtlas(point.atlas, true)
      local w, h = t:GetSize()
      local k = math.min(1, ICON_MAX / math.max(w, h, 1))
      t:SetSize(w * k, h * k)
      set = true
    elseif point.index then
      t:SetTexture("Interface/Minimap/POIIcons")
      t:SetTexCoord(C_Minimap.GetPOITextureCoords(point.index))
      t:SetSize(POI_ICON, POI_ICON)
      set = true
    elseif point.texture then
      local c = point.coords or { 0, 1, 0, 1 }
      t:SetTexture(point.texture)
      t:SetTexCoord(c[1], c[2], c[3], c[4])
      t:SetSize(ICON_MAX, ICON_MAX)
      set = true
    end
    t.empty = not set
    t:SetDesaturated(point.dim or false)
    t:SetAlpha(point.dim and 0.6 or 1)
  end
  return t
end

---Draw the points of instance map `map`, each where `project(north, west)` puts it (pixels right and
---up of the frame's centre); `north`, `west` is a point on the map (to find its continent). Then the
---hover, unless `noHover` (another layer's tooltip is up).
---@param map number?
---@param north number
---@param west number
---@param project? fun(north: number, west: number): number, number
---@param noHover boolean?
---@param liveOnly boolean? only the live points (the minimap: the rest is in the window)
function Layer:Draw(map, north, west, project, noHover, liveOnly)
  wipe(self.shown)
  local list = map and project and not liveOnly and Points.For(map, north, west) or EMPTY
  local liveList = map and project and Points.Live(map, north, west) or EMPTY
  project = project or function() return 0, 0 end
  -- Live points gone (looted, resurrected): their textures back to the pool.
  local current = {}
  for _, point in ipairs(liveList) do
    current[point] = true
  end
  for point, t in pairs(self.icons) do
    if point.live and not current[point] then
      t:Hide()
      self.free[#self.free + 1] = t
      self.icons[point] = nil
    end
  end
  if list ~= self.list then
    -- Gathered again (or another continent): the old points' textures go back to the pool.
    for point, t in pairs(self.icons) do
      if not point.live then
        t:Hide()
        self.free[#self.free + 1] = t
        self.icons[point] = nil
      end
    end
    self.list = list
  end
  local frame = self.frame
  local halfW, halfH = frame:GetWidth() / 2 + ICON_MAX, frame:GetHeight() / 2 + ICON_MAX
  for _, points in ipairs({ list, liveList }) do
    for _, point in ipairs(points) do
      local x, y = project(point.north, point.west)
      local t = self:Icon(point)
      if not t.empty and math.abs(x) <= halfW and math.abs(y) <= halfH and ns.MapWindow.Shows(point.kind) then
        t:ClearAllPoints()
        t:SetPoint("CENTER", frame, "CENTER", x, y)
        t:Show()
        self.shown[#self.shown + 1] = { x = x, y = y, point = point }
      else
        t:Hide()
      end
    end
  end
  self:Hover(noHover)
end

-- Hover: the points under the cursor, named (worked out from the cursor, as the group dots are).
function Layer:Hover(noHover)
  local frame = self.frame
  local over = {}
  if not noHover and #self.shown > 0 and frame:IsVisible() and frame:IsMouseOver() then
    local cx, cy = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    local mx, my = frame:GetCenter()
    local x, y = cx / scale - mx, cy / scale - my
    for _, p in ipairs(self.shown) do
      if (p.x - x) ^ 2 + (p.y - y) ^ 2 <= HOVER_RADIUS ^ 2 then
        over[#over + 1] = p.point
      end
    end
  end
  if #over == 0 then
    if self.hovering then
      self.hovering = false
      GameTooltip:Hide()
    end
    return
  end
  self.hovering = true
  GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
  for _, point in ipairs(over) do
    GameTooltip:AddLine(point.name or "", 1, 1, 1)
    if point.note and point.note ~= "" then
      GameTooltip:AddLine(point.note, 0.8, 0.8, 0.8, true)
    end
  end
  GameTooltip:Show()
end

---Whether the cursor is over one of this layer's points (its tooltip is up).
---@return boolean
function Layer:IsHovering()
  return self.hovering
end

-- The minimap's live points (our map hides the game's minimap, its rares and corpse with it): relative
-- to the player, turned as the terrain is, over the quest layer. With the game's minimap showing, it
-- draws them itself.
table.insert(ns.Minimap.onActivate, function(outer)
  local layer = Points.NewLayer(outer)
  layer.frame:SetFrameStrata("LOW")
  layer.frame:SetClipsChildren(true)
  local elapsed = 0
  layer.frame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 0.05 then
      return
    end
    elapsed = 0
    local level = math.max(outer:GetFrameLevel(), Minimap:GetFrameLevel()) + 3
    if layer.frame:GetFrameLevel() ~= level then
      layer.frame:SetFrameLevel(level)
    end
    local pn, pw, _, pmap = UnitPosition("player")
    local s, turn = ns.Terrain:Projection()
    if not (ns.Zoom.own and readable(pn) and readable(pw) and s) then
      layer:Draw(nil, 0, 0)
      return
    end
    local cos, sin = math.cos(turn), math.sin(turn)
    layer:Draw(pmap, pn, pw, function(north, west)
      local x, y = (pw - west) * s, (north - pn) * s
      return x * cos + y * sin, -x * sin + y * cos
    end, false, true)
  end)
end)
