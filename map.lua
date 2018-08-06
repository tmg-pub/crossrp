-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- This handles adding blips to the world map when we receive relay data from
--  connected players.
-------------------------------------------------------------------------------
local _, Me = ...
local L     = Me.Locale
-------------------------------------------------------------------------------
-- Collection of blips, indexed by username.
-- [username] = {
--   time      = Time this blip was added.
--   name      = Full user name.
--   ic_name   = IC name, pulled from RP profile.
--   continent = What instanceMapId they're on.
--   x, y      = Unit position in that map.
--   faction   = "A" for alliance, "H" for horde.
--   icon      = TRP icon they're using, or otherwise some icon for them.
local m_players = {}

-- Pins is a list of pins acquired from the map API, so we can update them
--  while the map is open. Indexed by username.
local m_pins = {}

local m_plot_scale = 10
local m_plotmap = {}

-- How long a pin will stay on the map after receiving a message from someone.
local ACTIVE_TIME = 180

-------------------------------------------------------------------------------
function Me.Map_Init()
	-- Add an option to the tracking button in the world map for toggling
	--  showing Cross RP users.
	-- Currently "2" is the tracking button overlay.
	hooksecurefunc( WorldMapFrame.overlayFrames[2], "InitializeDropDown",
		function()
			Me.DebugLog2( "WorldMap tracking opened." )
			if Me.connected then
				local info = UIDropDownMenu_CreateInfo();
				info.isNotRadio = true
				info.text       = L.MAP_TRACKING_CROSSRP_PLAYERS;
				info.checked    = Me.db.global.map_blips
				info.func = function( self, arg1, arg2, checked )
					Me.db.global.map_blips = checked
					Me.MapDataProvider:RefreshAllData()
				end
				info.keepShownOnClick = true;
				UIDropDownMenu_AddButton(info);
			end
		end)
end

-------------------------------------------------------------------------------
-- Reset all player blips. Should be called for fresh connections or after 
--                           disconnecting.
function Me.Map_ResetPlayers()
	m_players = {}
end

-------------------------------------------------------------------------------
-- Returns `ic_name, icon` for a TRP user.
--
local function GetTRPNameIcon( username )
	local fallback = username:match( "[^-]+" )
	if not TRP3_API then
		return fallback, nil 
	end
	local data
	if username == TRP3_API.globals.player_id then
		data = TRP3_API.profile.getData("player")
	elseif TRP3_API.register.isUnitIDKnown( username ) then
		data = TRP3_API.register.getUnitIDCurrentProfile( username )
	end
	
	if not data then return fallback, nil end

	local ci = data.characteristics
	if ci then
		local firstname = ci.FN or ""
		local lastname = ci.LN or ""
		local name = firstname .. " " .. lastname
		name = name:match("%s*(%S+)%s*") or fallback
		
		local icon
		if ci.IC and ci.IC ~= "" then
			icon = ci.IC 
		end
		
		if ci.CH then
			name = "|cff" .. ci.CH .. name
		end
		
		return name, icon
	end

	return fallback, nil
end

local function GetPlotIndex( x, y )
	local px = math.floor( (x + (m_plot_scale/2)) / m_plot_scale )
	local py = math.floor( (y + (m_plot_scale/2)) / m_plot_scale )
	return px + py * 10000
end

local function PlotPoint( x, y )
	local index = GetPlotIndex( x, y )
	if m_plotmap[index] then return false end
	m_plotmap[index] = true
	return index
end

local function RemovePlayerPlot( player )
	if player.plot then
		m_plotmap[player.plot] = nil
		player.plot = nil
	end
end

local function RemoveAllPlots()
	for _, player in pairs( m_players ) do
		player.plot = nil
	end
	
	wipe( m_plotmap )
end

-------------------------------------------------------------------------------
-- Called when we detect a player.
--   username: Full username.
--   continent, x, y: Position in the world. This is stored in relay messages.
--   faction: User faction, stored in the relay message header.
--   icon: User icon override, leave nil to fetch automatically from TRP.
--
function Me.Map_SetPlayer( username, continent, x, y, faction, icon )
	if username == Me.fullname then return end
	
	local ic_name = username
	ic_name, icon = GetTRPNameIcon( username )
	
	if not m_players[username] then
		m_players[username] = {}
	end
	
	local p = m_players[username]
	p.time      = GetTime();
	p.name      = username;
	p.ic_name   = ic_name;
	p.continent = continent;
	p.faction   = faction;
	p.icon      = icon;
	
	RemovePlayerPlot( p )
	
	p.x = x;
	p.y = y;
	
	-- Adjust position according to other players.
--[[	for k, op in pairs( m_players ) do
		if op.continent == p.continent and k ~= username 
		                            and GetTime() - op.time < ACTIVE_TIME  then
			local vx, vy = x - op.x, y - op.y
			local d2 = vx*vx+vy*vy
			if d2 < 20*20 then
				local d = math.sqrt(d2)
				vx = vx / d
				vy = vy / d
				x = op.x + vx * 20
				y = op.y + vy * 20
			end
		end
	end]]
	
	
	if WorldMapFrame:IsShown() then
		Me.Map_UpdatePlayer( username )
	end
end

function Me.Map_GetScale( map_id )
	local _, result1 = C_Map.GetWorldPosFromMapPos( map_id, CreateVector2D( 0.5, 0.4 ))
	local _, result2 = C_Map.GetWorldPosFromMapPos( map_id, CreateVector2D( 0.5, 0.5 ))
	if not result1 or not result2 then return 10 end
	return math.abs(result2.x - result1.x)*10
end
-------------------------------------------------------------------------------
-- Scans our blip table and then returns a list of entries that are visible
--  on the map ID given.
-- Returns list of { source, x, y }
--  source: m_players entry.
--  x, y:   Map position.
--
function Me.Map_UpdatePlayer( username )
	if not Me.connected then return end
	
	local player = m_players[username]
	if not player then return end
	
	RemovePlayerPlot( player )
	m_plot_scale = Me.Map_GetScale( WorldMapFrame:GetMapID() ) / 100
	
	-- Only show if this player was updated in the last three minutes.
	--  Maybe we should clear this entry in here if we see that it's too
	--  old.
	if Me.db.global.map_blips and GetTime() - player.time < ACTIVE_TIME then
		-- Convert our world position to a local position on the map
		--  screen using the map ID given. If the world coordinate isn't
		--  present on the map, position will be nil.
		
		-- Find a free plot. This is to avoid people overlapping on the map.
		local px, py
		for i = 0, 10 do
			local angle = math.random() * 6.283185 
			px = player.x + math.cos( angle ) * i * (m_plot_scale)
			py = player.y + math.sin( angle ) * i * (m_plot_scale)
			local j = PlotPoint( px, py )
			if j then
				player.plot = j
				break
			end
		end
		
		-- If it's too crowded, we skip this blip.
		if player.plot then
			local position = CreateVector2D( py, px )
			_, position = C_Map.GetMapPosFromWorldPos( player.continent, 
														position, 
														 WorldMapFrame:GetMapID() )
			if position then
				if not m_pins[username] then
					m_pins[username] = 
						  WorldMapFrame:AcquirePin( "CrossRPBlipTemplate", player )
				end
				m_pins[username]:SetPosition( position.x, position.y )
				m_pins[username]:Show()
				return true
			end
		end
	end
	
	if m_pins[username] then
		m_pins[username]:Hide()
	end
end

-------------------------------------------------------------------------------
-- To add things to the world map we need two things. One is a data provider.
--  This is registered at the end of this file with the world map frame, and
--  it receives callbacks from the map API to tell us to add things to the map.
-- Create from MapCanvasDataProviderMixin. This is documented in 
--  Blizzard_MapCanvas\MapCanvas_DataProviderBase.lua. See more examples in
--  Blizzard_SharedMapDataProviders.
CrossRPBlipDataProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin);
local DataProvider = CrossRPBlipDataProviderMixin

-------------------------------------------------------------------------------
-- Called when the map is opened.
--
function DataProvider:OnShow()

end

-------------------------------------------------------------------------------
-- Called when the map is closed.
--
function DataProvider:OnHide()
	
end

-------------------------------------------------------------------------------
-- Called when we receive an event. We can register events with the mixin.
--  e.g. self:RegisterEvent(...)
--
function DataProvider:OnEvent(event, ...)
	
end

-------------------------------------------------------------------------------
-- Called when the map wants to clear everything. This should remove all of
--  your added elements.
function DataProvider:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate( "CrossRPBlipTemplate" );
	wipe( m_pins )
	RemoveAllPlots()
end

-------------------------------------------------------------------------------
-- Called when the map changes pages or something; you need to update all
--  of the things that are shown or add them.
function DataProvider:RefreshAllData(fromOnShow)
	-- First we cleanup existing pins, so we can add new ones. Blizzard makes
	--  this easy with its new frame pools.
	self:RemoveAllData();
	
	--[[
	local mapID = self:GetMap():GetMapID();
	for _, v in pairs( Me.GetMapBlips( mapID )) do
		-- AcquirePin gets a "pin" from some pool and then calls OnAcquire on
		--  it (see below). The second arg is passed to the OnAcquire function.
		self:GetMap():AcquirePin("CrossRPBlipTemplate", v )
	end]]
	
	local mapID = self:GetMap():GetMapID()
	for _,v in pairs( m_players ) do
		Me.Map_UpdatePlayer( v.name )
	end
end

-------------------------------------------------------------------------------
-- This is for our blip frames. Create from MapCanvasPinMixin. Blizzard calls
--  little things that you add to the map "pins". This is also documented in
--  Blizzard_MapCanvas\MapCanvas_DataProviderBase.lua, where you can see all
--  of the interface base.
CrossRPBlipMixin = CreateFromMixins(MapCanvasPinMixin);
local BlipMixin = CrossRPBlipMixin
-------------------------------------------------------------------------------
-- You can see all of the frame levels used in 
--  Blizzard_WorldMap\Blizzard_WorldMap.lua. I picked to be drawn on the same
--  level as dungeon entrances, which is pretty low, but we don't want our
--  blips to be covering important things like flight masters and such.
BlipMixin:UseFrameLevelType( "PIN_FRAME_LEVEL_DUNGEON_ENTRANCE" )

-------------------------------------------------------------------------------
-- If you don't set scaling limits, then the scale will follow the map zoom,
--  (which is probably what you want!). Args are scaleFactor, scaleMin, 
--  scaleMax.
BlipMixin:SetScalingLimits( 1.0, 0.4, 0.4 )

-------------------------------------------------------------------------------
-- Called when a pin is acquired from the frame pool. `info` is passed in from
--  AcquirePin, from our RefreshAllData.
--
function BlipMixin:OnAcquired( player )
	self.highlight:Hide()
	self.source = player
	
	if player.icon then
		self.icon:SetTexture( "Interface\\Icons\\" .. player.icon )
	else
		if player.faction == "H" then
			self.icon:SetTexture( 
			              "Interface\\Icons\\Inv_Misc_Tournaments_banner_Orc" )
		else
			self.icon:SetTexture( 
			            "Interface\\Icons\\Inv_Misc_Tournaments_banner_Human" )
		end
	end
end

-------------------------------------------------------------------------------
-- Called when this pin is removed from the map. We're doing that with
--  RemoveAllPinsByTemplate.
--
function BlipMixin:OnReleased(info)
	self.source = nil
end

-------------------------------------------------------------------------------
-- Called when the mouse enters this pin's interactive area. We use it to
--  hook our special tooltip frame above it and show some info.
--
function BlipMixin:OnMouseEnter()
	CrossRPBlipTooltip:ClearAllPoints()
	CrossRPBlipTooltip:SetPoint( "BOTTOM", self, "TOP", 0, 8 )
	CrossRPBlipTooltip.text:SetText( self.source.ic_name or self.source.name )
	CrossRPBlipTooltip:Show()
	self.highlight:Show()
end

-------------------------------------------------------------------------------
-- Called when the mouse leaves this pin's interactive area.
--
function BlipMixin:OnMouseLeave()
	CrossRPBlipTooltip:Hide()
	self.highlight:Hide()
end

-------------------------------------------------------------------------------
-- See the rest of the callbacks in 
--  Blizzard_MapCanvas\MapCanvas_DataProviderBase.lua.
-------------------------------------------------------------------------------

Me.MapDataProvider = CreateFromMixins(CrossRPBlipDataProviderMixin)
WorldMapFrame:AddDataProvider( Me.MapDataProvider );

function Me.MapTest( count )
	count = count or 100
	local instanceMapID = select( 8, GetInstanceInfo() )
	local y, x = UnitPosition( "player" )
	for i = 1, count do
		local px, py = x + math.random() * 30, y + math.random() * 30
		Me.Map_SetPlayer( "TestUser" .. i .. "-Dalaran", instanceMapID, px, py, "H" )
	end
	
end
