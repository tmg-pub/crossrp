-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- This handles adding blips to the world map when we receive relay data from
--  connected players.
-------------------------------------------------------------------------------
local _, Me = ...
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
local m_blips = {}

-------------------------------------------------------------------------------
-- Reset all player blips. Should be called for fresh connections or after 
--                           disconnecting.
function Me.ResetMapBlips()
	m_blips = {}
end

-------------------------------------------------------------------------------
-- Returns `ic_name, icon` for a TRP user.
--
local function GetTRPNameIcon( username )
	if not TRP3_API then
		return username, nil 
	end
	local data
	if username == TRP3_API.globals.player_id then
		data = TRP3_API.profile.getData("player")
	elseif TRP3_API.register.isUnitIDKnown( username ) then
		data = TRP3_API.register.getUnitIDCurrentProfile( username )
	else
		return username, nil
	end

	local ci = data.characteristics
	if ci then
		local firstname = ci.FN or ""
		local lastname = ci.LN or ""
		local name = firstname .. " " .. lastname
		name = name:match("%s*(%S+)%s*") or username
		
		local icon
		if ci.IC and ci.IC ~= "" then
			icon = ci.IC 
		end
		
		return name, icon
	end
	return username, nil
end

-------------------------------------------------------------------------------
-- Called when we detect a player.
--   username: Full username.
--   continent, x, y: Position in the world. This is stored in relay messages.
--   faction: User faction, stored in the relay message header.
--   icon: User icon override, leave nil to fetch automatically from TRP.
--
function Me.SetMapBlip( username, continent, x, y, faction, icon )
	local ic_name = username
	ic_name, icon = GetTRPNameIcon( username )
	
	m_blips[username] = {
		time      = GetTime();
		name      = username;
		ic_name   = ic_name;
		continent = continent;
		x         = x;
		y         = y;
		faction   = faction;
		icon      = icon;
	}
	
	if WorldMapFrame:IsShown() then
		Me.MapDataProvider:RefreshAllData()
	end
end
-------------------------------------------------------------------------------
-- Scans our blip table and then returns a list of entries that are visible
--  on the map ID given.
-- Returns list of { source, x, y }
--  source: m_blips entry.
--  x, y:   Map position.
--
function Me.GetMapBlips( mapID )
	if not Me.connected then return {} end
	local blips = {}
	for k, v in pairs( m_blips ) do
		-- Only show if this player was updated in the last three minutes.
		--  Maybe we should clear this entry in here if we see that it's too
		--  old.
		if GetTime() - v.time < 180 then
			-- Convert our world position to a local position on the map
			--  screen using the map ID given. If the world coordinate isn't
			--  present on the map, position will be nil.
			local position = CreateVector2D( v.y, v.x )
			_, position = C_Map.GetMapPosFromWorldPos( v.continent, 
			                                                 position, mapID )
			if position then
				-- Add to visible blips.
				table.insert( blips, {
					source = v;
					x      = position.x;
					y      = position.y;
				})
			end
		end
	end
	return blips
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
end

-------------------------------------------------------------------------------
-- Called when the map changes pages or something; you need to update all
--  of the things that are shown or add them.
function DataProvider:RefreshAllData(fromOnShow)
	-- First we cleanup existing pins, so we can add new ones. Blizzard makes
	--  this easy with its new frame pools.
	self:RemoveAllData();
	
	local mapID = self:GetMap():GetMapID();
	for _, v in pairs( Me.GetMapBlips( mapID )) do
		-- AcquirePin gets a "pin" from some pool and then calls OnAcquire on
		--  it (see below). The second arg is passed to the OnAcquire function.
		self:GetMap():AcquirePin("CrossRPBlipTemplate", v )
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
BlipMixin:SetScalingLimits( 1.0, 0.4, 0.75 )

-------------------------------------------------------------------------------
-- Called when a pin is acquired from the frame pool. `info` is passed in from
--  AcquirePin, from our RefreshAllData.
--
function BlipMixin:OnAcquired( info )
	self.highlight:Hide()
	self:SetPosition( info.x, info.y )
	self.source = info.source
	
	if info.source.icon then
		self.icon:SetTexture( "Interface\\Icons\\" .. info.source.icon )
	else
		if info.source.faction == "H" then
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