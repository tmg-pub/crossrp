local _, Me = ...

local m_blips = {}

function Me.ResetMapBlips()
	m_blips = {}
end

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

function Me.SetMapBlip( username, continent, x, y, faction, icon )

	local ic_name = username
	ic_name, icon = GetTRPNameIcon( username )
	
	m_blips[username] = {
		time = GetTime();
		name = username;
		ic_name = ic_name;
		continent = continent;
		x = x;
		y = y;
		faction = faction;
		icon = icon;
	}
	
	if WorldMapFrame:IsShown() then
		Me.MapDataProvider:RefreshAllData()
	end
end

function Me.GetMapBlips( mapID )
	if not Me.connected then return {} end
	local blips = {}
	for k, v in pairs( m_blips ) do
		if GetTime() - v.time < 180 then
			local position = CreateVector2D( v.y, v.x )
			_, position = C_Map.GetMapPosFromWorldPos( v.continent, position, mapID )
			if position then
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

CrossRPBlipDataProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin);
local DataProvider = CrossRPBlipDataProviderMixin

function DataProvider:OnShow()

end

function DataProvider:OnHide()
	
end

function DataProvider:OnEvent(event, ...)
	
end
function DataProvider:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate("CrossRPBlipTemplate");
end

function DataProvider:RefreshAllData(fromOnShow)
	self:RemoveAllData();
	local mapID = self:GetMap():GetMapID();
	for _, v in pairs( Me.GetMapBlips( mapID )) do
		self:GetMap():AcquirePin("CrossRPBlipTemplate", v )
	end
end

CrossRPBlipMixin = CreateFromMixins(MapCanvasPinMixin);
local BlipMixin = CrossRPBlipMixin
BlipMixin:UseFrameLevelType( "PIN_FRAME_LEVEL_GROUP_MEMBER" )
BlipMixin:SetScalingLimits( 1.0, 0.4, 0.75 )

function BlipMixin:OnAcquired( info )
	self.highlight:Hide()
	self:SetPosition( info.x, info.y )
	self.source = info.source
	
	if info.source.icon then
		self.icon:SetTexture( "Interface\\Icons\\" .. info.source.icon )
	else
		if info.source.faction == "H" then
			self.icon:SetTexture( "Interface\\Icons\\Inv_Misc_Tournaments_banner_Orc" )
		else
			self.icon:SetTexture( "Interface\\Icons\\Inv_Misc_Tournaments_banner_Human" )
		end
	end
end

function BlipMixin:OnReleased(info)
	self.source = nil
end

function BlipMixin:OnMouseEnter()
	CrossRPBlipTooltip:ClearAllPoints()
	CrossRPBlipTooltip:SetPoint( "BOTTOM", self, "TOP", 0, 8 )
	CrossRPBlipTooltip.text:SetText( self.source.ic_name or self.source.name )
	CrossRPBlipTooltip:Show()
	self.highlight:Show()
end

function BlipMixin:OnMouseLeave()
	CrossRPBlipTooltip:Hide()
	self.highlight:Hide()
end

Me.MapDataProvider = CreateFromMixins(CrossRPBlipDataProviderMixin)
WorldMapFrame:AddDataProvider( Me.MapDataProvider );