local ADDON_NAME, ns = ...

-- BubbleMap's settings: its own page in Blizzard's Options > AddOns. STOPGAP until the suite's shared
-- library (LibBubble, docs/design/bubble-suite.md) brings the one settings window and schema every
-- Bubble addon uses; these entries move into it then.

local function show(key)
  return function() return ns.DB.show[key] end, function(value)
    ns.DB.show[key] = value
    ns.Around:Apply()
  end
end

-- kind, id, label, tooltip, default, get, set (+ min, max, step, format for sliders; options() ->
-- { { value, label }, ... } for dropdowns)
local ENTRIES = {
  { kind = "section", label = "Map" },
  { kind = "checkbox", id = "BUBBLEMAP_LOCKED", label = "Lock the map", default = true,
    tooltip = "Untick to drag the map by its top bar.",
    get = function() return ns.DB.locked end, set = function(v) ns.DB.locked = v end },
  { kind = "checkbox", id = "BUBBLEMAP_ATTACH_TRACKER", label = "BubbleQuest's tracker under the map",
    default = true, needsQuest = true,
    tooltip = "With BubbleQuest: its tracker hangs under the map as one column, the map as wide as the "
      .. "tracker. Untick to place them apart.",
    get = function() return ns.DB.attachTracker end,
    set = function(v) ns.DB.attachTracker = v; ns.Minimap:ApplyAttach() end },
  { kind = "slider", id = "BUBBLEMAP_WIDTH", label = "Width", default = 220, min = 140, max = 450, step = 5,
    tooltip = "The map's width. With BubbleQuest's tracker under the map it follows the tracker's width "
      .. "instead (drag the tracker's corner).",
    format = function(v) return ("%d"):format(v) end,
    get = function() return ns.DB.width end,
    set = function(v) ns.DB.width = v; ns.Minimap:Refresh() end },
  { kind = "slider", id = "BUBBLEMAP_HEIGHT", label = "Height", default = 100, min = 50, max = 150, step = 5,
    tooltip = "The map's height, as a percentage of its width.",
    format = function(v) return ("%d%%"):format(v) end,
    get = function() return ns.DB.heightPercent end,
    set = function(v) ns.DB.heightPercent = v; ns.Minimap:Refresh() end },

  { kind = "slider", id = "BUBBLEMAP_MINIMAP_ALPHA", label = "Minimap opacity", default = 100, min = 20,
    max = 100, step = 5,
    tooltip = "How see-through the minimap is while the mouse isn't over it; hovering it makes it fully "
      .. "opaque.",
    format = function(v) return ("%d%%"):format(v) end,
    get = function() return math.floor(ns.DB.minimapAlpha * 100 + 0.5) end,
    set = function(v) ns.DB.minimapAlpha = v / 100 end },

  { kind = "dropdown", id = "BUBBLEMAP_GATHER_MODE", label = "Gather mode", default = "never",
    tooltip = "BubbleMap draws its own map, zooming in and out freely. Gather mode shows the game's own "
      .. "minimap instead, for its live herb, ore and tracking blips, which are only right at the game's "
      .. "zoom levels: zoom is limited to those. Automatic: while a tracking "
      .. "spell such as Find Herbs is on. The bar's gather button switches it on and off.",
    options = function()
      return { { "never", "Off" }, { "auto", "Automatic (while tracking)" }, { "always", "On" } }
    end,
    get = function() return ns.DB.gatherMode end,
    set = function(v) ns.DB.gatherMode = v; ns.Zoom:Update() end },

  { kind = "dropdown", id = "BUBBLEMAP_MAP_STYLE", label = "Map style", default = "terrain",
    tooltip = "What the map draws: the real terrain (the game's own minimap ground), or the world map's "
      .. "painted art with your explored areas, as on the world map. Also in gather mode, under the game's "
      .. "blips. Indoors the game's own minimap shows either way.",
    options = function()
      return { { "terrain", "Terrain" }, { "art", "Map art" } }
    end,
    get = function() return ns.DB.mapStyle end,
    set = function(v) ns.DB.mapStyle = v; ns.Around:Apply() end },  -- the bar button's icon follows

  { kind = "section", label = "Map window" },
  { kind = "slider", id = "BUBBLEMAP_WINDOW_FADE", label = "Opacity while moving", default = 60, min = 20,
    max = 100, step = 5,
    tooltip = "The map window fades while you move, to see past it; hovering it makes it opaque. 100%: "
      .. "no fading.",
    format = function(v) return ("%d%%"):format(v) end,
    get = function() return math.floor(ns.DB.windowMoveAlpha * 100 + 0.5) end,
    set = function(v) ns.DB.windowMoveAlpha = v / 100 end },
  { kind = "checkbox", id = "BUBBLEMAP_GAME_WAYPOINT", label = "Set the game's waypoint too", default = true,
    tooltip = "Your waypoint also becomes the game's own map pin, with its on-screen arrow and distance.",
    get = function() return ns.DB.gameWaypoint end, set = function(v) ns.DB.gameWaypoint = v end },
  { kind = "checkbox", id = "BUBBLEMAP_MAP_KEY", label = "The map key opens this map", default = false,
    tooltip = "The world map's key (M) opens BubbleMap's map window instead of the game's world map. "
      .. "Applied out of combat.",
    get = function() return ns.DB.mapOnMapKey end,
    set = function(v) ns.DB.mapOnMapKey = v; ns.MapWindow:ApplyMapKey() end },
  { kind = "checkbox", id = "BUBBLEMAP_REVEAL", label = "Reveal the whole map", default = true,
    tooltip = "Map art (the minimap's Map style and the map window's): every zone fully painted, as if "
      .. "explored. Untick to see only the parts you've discovered, as on the world map.",
    get = function() return ns.DB.revealMap end,
    set = function(v) ns.DB.revealMap = v; ns.Art.Rebuild() end },
  { kind = "checkbox", id = "BUBBLEMAP_GROUP_NAMES", label = "Party members' names", default = true,
    tooltip = "Each party or raid member's name beside their dot, in their class colour, on the map and "
      .. "in the map window. Untick for dots only (hover one for its name).",
    get = function() return ns.DB.groupNames end, set = function(v) ns.DB.groupNames = v end },
  { kind = "checkbox", id = "BUBBLEMAP_GROUP_LINES", label = "Lines to party members", default = true,
    tooltip = "A dashed line from you to each party or raid member, in their class colour, on the map and "
      .. "in the map window (to the map's edge when they're beyond it).",
    get = function() return ns.DB.groupLines end, set = function(v) ns.DB.groupLines = v end },

  { kind = "checkbox", id = "BUBBLEMAP_WORLD_TERRAIN", label = "Terrain on the world map", default = false,
    tooltip = "Zone maps on the world map show the real terrain (the minimap's own ground) instead of the "
      .. "painted art. Also the button at the world map's top right.",
    get = function() return ns.DB.worldTerrain end,
    set = function(v) ns.WorldMap:SetEnabled(v) end },

  { kind = "section", label = "Around the map" },
  { kind = "checkbox", id = "BUBBLEMAP_SHOW_BAR", label = "Top bar", default = true,
    tooltip = "The bar along the map's top: zone name, buttons and clock. Untick to hide all of it." },
  { kind = "checkbox", id = "BUBBLEMAP_SHOW_ZONE", label = "Zone name", default = true,
    tooltip = "Click it to open the world map." },
  { kind = "checkbox", id = "BUBBLEMAP_SHOW_CLOCK", label = "Clock", default = true,
    tooltip = "Local or realm time, 12 or 24 hours: the game's clock settings (click the clock)." },
  { kind = "checkbox", id = "BUBBLEMAP_SHOW_CALENDAR", label = "Calendar button", default = true,
    tooltip = "Shows how many invites are waiting." },
  { kind = "checkbox", id = "BUBBLEMAP_SHOW_TRACKING", label = "Tracking button", default = true,
    tooltip = "What the minimap shows: flight masters, trainers, ..." },
  { kind = "checkbox", id = "BUBBLEMAP_SHOW_GATHER", label = "Gather button", default = true,
    tooltip = "Gather mode on and off in one click: on, the game's minimap and its live herb and ore blips; "
      .. "off, BubbleMap's map with all its zoom." },
  { kind = "checkbox", id = "BUBBLEMAP_SHOW_STYLE", label = "Map style button", default = true,
    tooltip = "Switches the map between the terrain and the world map's art in one click (also the Map "
      .. "style setting above)." },
  { kind = "checkbox", id = "BUBBLEMAP_SHOW_MAIL", label = "New mail", default = true,
    tooltip = "An envelope when there's new mail; hover it for the senders." },
  { kind = "checkbox", id = "BUBBLEMAP_SHOW_COORDS", label = "Coordinates", default = false,
    tooltip = "Your position, bottom left of the map. (BubbleQuest's header shows them too.)" },
  { kind = "checkbox", id = "BUBBLEMAP_SHOW_ZOOM", label = "Zoom buttons", default = false,
    tooltip = "+ and - at the map's bottom right. The mouse wheel zooms either way." },
  { kind = "checkbox", id = "BUBBLEMAP_LAUNCHERS", label = "Collect addon buttons", default = true,
    tooltip = "Every addon's minimap button and addon-menu entry in one list, opened from the bar; their "
      .. "buttons are put away. With another button collector on (MinimapButtonButton, ...) this waits, "
      .. "and BubbleMap offers to turn that one off. Takes effect after /reload." },
}

local SHOW_KEYS = {
  BUBBLEMAP_SHOW_BAR = "bar", BUBBLEMAP_SHOW_ZONE = "zone", BUBBLEMAP_SHOW_CLOCK = "clock",
  BUBBLEMAP_SHOW_CALENDAR = "calendar", BUBBLEMAP_SHOW_TRACKING = "tracking",
  BUBBLEMAP_SHOW_MAIL = "mail", BUBBLEMAP_SHOW_GATHER = "gather", BUBBLEMAP_SHOW_STYLE = "style", BUBBLEMAP_SHOW_COORDS = "coords", BUBBLEMAP_SHOW_ZOOM = "zoom",
  BUBBLEMAP_LAUNCHERS = "launchers",
}

local VAR_TYPE = { checkbox = "Boolean", slider = "Number", dropdown = "String" }

local Settings_ = {}
ns.Settings = Settings_

-- An entry's getter and setter (the "show" ones through ns.DB.show and Around:Apply).
local function accessors(entry)
  if SHOW_KEYS[entry.id] then
    return show(SHOW_KEYS[entry.id])
  end
  return entry.get, entry.set
end

local function register()
  local category = Settings.RegisterVerticalLayoutCategory("BubbleMap")
  local layout = SettingsPanel:GetLayout(category)
  for _, entry in ipairs(ENTRIES) do
    if entry.needsQuest and not ns.Quest then
      -- Only with BubbleQuest loaded (it would do nothing without).
    elseif entry.kind == "section" then
      layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(entry.label))
    else
      local get, set = accessors(entry)
      local setting = Settings.RegisterProxySetting(category, entry.id, Settings.VarType[VAR_TYPE[entry.kind]],
        entry.label, entry.default, get, set)
      if entry.kind == "checkbox" then
        Settings.CreateCheckbox(category, setting, entry.tooltip)
      elseif entry.kind == "dropdown" then
        Settings.CreateDropdown(category, setting, function()
          local container = Settings.CreateControlTextContainer()
          for _, option in ipairs(entry.options()) do
            container:Add(option[1], option[2])
          end
          return container:GetData()
        end, entry.tooltip)
      else
        local options = Settings.CreateSliderOptions(entry.min, entry.max, entry.step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, entry.format)
        Settings.CreateSlider(category, setting, options, entry.tooltip)
      end
    end
  end
  Settings.RegisterAddOnCategory(category)
end

ns.On("ADDON_LOADED", function(name)
  if name == ADDON_NAME then
    register()  -- after Init.lua's handler (registered first): ns.DB is set
  end
end)

-- The settings drawer (MapWindow.lua's footer: Settings): the same entries as the Options page, as
-- widgets in a scrolling list, applied as they change. Built once; every open reads the values again
-- (the Options page or a bar button may have changed them).

local ROW, PAD = 26, 10
local widgets = {}  -- { refresh = function() } per entry
local built = {}    -- [frame] = true once filled

local function tooltipOn(frame, entry)
  if not entry.tooltip then
    return
  end
  frame:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(entry.label, 1, 1, 1)
    GameTooltip:AddLine(entry.tooltip, 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function build(frame)
  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -6)
  scroll:SetPoint("BOTTOMRIGHT", -24, 6)
  local list = CreateFrame("Frame", nil, scroll)
  list:SetSize(1, 1)
  scroll:SetScrollChild(list)
  scroll:SetScript("OnSizeChanged", function(_, w) list:SetWidth(w) end)

  local y = 0
  local function row(height)
    local r = CreateFrame("Frame", nil, list)
    r:SetPoint("TOPLEFT", PAD, -y)
    r:SetPoint("RIGHT", list, "RIGHT", -PAD, 0)
    r:SetHeight(height or ROW)
    y = y + (height or ROW)
    return r
  end
  for _, entry in ipairs(ENTRIES) do
    if entry.needsQuest and not ns.Quest then
      -- Only with BubbleQuest loaded.
    elseif entry.kind == "section" then
      y = y + 6
      local r = row(24)
      local text = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
      text:SetPoint("LEFT")
      text:SetText(entry.label)
    else
      local get, set = accessors(entry)
      local r = row(entry.kind == "checkbox" and ROW or 44)
      if entry.kind == "checkbox" then
        local box = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
        box:SetSize(24, 24)
        box:SetPoint("LEFT")
        box.Text:SetFontObject("GameFontHighlight")
        box.Text:SetText(entry.label)
        box:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
        tooltipOn(box, entry)
        widgets[#widgets + 1] = { refresh = function() box:SetChecked(get() and true or false) end }
      else
        local label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("TOPLEFT", 4, -2)
        label:SetText(entry.label)
        if entry.kind == "slider" then
          local slider = CreateFrame("Frame", nil, r, "MinimalSliderWithSteppersTemplate")
          slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
          slider:SetPoint("RIGHT", r, "RIGHT", -40, 0)
          slider:SetHeight(20)
          local steps = math.floor((entry.max - entry.min) / entry.step + 0.5)
          local ready = false
          slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
            if ready then
              set(value)
            end
          end, slider)
          tooltipOn(slider, entry)
          widgets[#widgets + 1] = { refresh = function()
            ready = false
            slider:Init(get(), entry.min, entry.max, steps,
              { [MinimalSliderWithSteppersMixin.Label.Right] = entry.format })
            ready = true
          end }
        else
          local dropdown = CreateFrame("DropdownButton", nil, r, "WowStyle1DropdownTemplate")
          dropdown:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
          dropdown:SetPoint("RIGHT", r, "RIGHT", -8, 0)
          dropdown:SetupMenu(function(_, root)
            for _, option in ipairs(entry.options()) do
              root:CreateRadio(option[2], function() return get() == option[1] end, function() set(option[1]) end)
            end
          end)
          tooltipOn(dropdown, entry)
          widgets[#widgets + 1] = { refresh = function() dropdown:GenerateMenu() end }
        end
      end
    end
  end
  list:SetHeight(y + PAD)
end

---Fill `frame` with the settings (built the first time) and show the current values.
---@param frame Frame
function Settings_:FillPanel(frame)
  if not built[frame] then
    built[frame] = true
    build(frame)
  end
  for _, w in ipairs(widgets) do
    w.refresh()
  end
end
