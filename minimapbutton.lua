
local _, Me = ...
local L = Me.Locale

local LDB          = LibStub:GetLibrary( "LibDataBroker-1.1" )
local DBIcon       = LibStub:GetLibrary( "LibDBIcon-1.0"     )
local m_tooltip_frame = nil
local m_traffic_lines_index = nil

function Me.SetupMinimapButton()

	Me.ldb = LDB:NewDataObject( "CrossRP", {
		type = "data source";
		text = L.CROSS_RP;
		icon = "Interface\\Icons\\Spell_Shaman_SpiritLink";
		OnClick = Me.OnMinimapButtonClick;
		OnEnter = Me.OnMinimapButtonEnter;
		OnLeave = Me.OnMinimapButtonLeave;
		iconR = 0.5;
		iconG = 0.5;
		iconB = 0.5;
	--	OnTooltip = Me.OnTooltip;
	})
	DBIcon:Register( "CrossRP", Me.ldb, Me.db.global.minimapbutton )
end

-------------------------------------------------------------------------------
function Me.OnMinimapButtonClick( frame, button )
	GameTooltip:Hide()
	if button == "LeftButton" then
		Me.OpenMinimapMenu( frame )
	elseif button == "RightButton" then
		Me.OpenOptions()
	end
end

function UpdateTrafficDisplay()
	if GameTooltip:GetOwner() ~= m_tooltip_frame
	      or (not GameTooltip:IsShown())
	            or (not m_traffic_lines_index) then
		return
	end
	local tooltip_text = _G["GameTooltipTextRight"..m_traffic_lines_index]
	tooltip_text:SetText( Me.GetTrafficFormatted() )
	Me.Timer_Start( "traffic_tooltip", "ignore", 0.5, UpdateTrafficDisplay )
end

-------------------------------------------------------------------------------
function Me.OnMinimapButtonEnter( frame )
	GameTooltip:SetOwner( frame, "ANCHOR_NONE" )
	GameTooltip:SetPoint( "TOPRIGHT", frame, "BOTTOMRIGHT", 0, 0 )

	GameTooltip:AddDoubleLine( L.CROSS_RP, GetAddOnMetadata( "CrossRP", "Version" ), 1, 1, 1, 1, 1, 1 )
	GameTooltip:AddLine( " " )
	if Me.connected then
		GameTooltip:AddLine( L( "CONNECTED_TO_SERVER", Me.GetServerName( true )), 1,1,1 )
		m_traffic_lines_index = 4
		if Me.relay_on then
			GameTooltip:AddLine( "|cFF03FF11" .. L.RELAY_ACTIVE, 1,1,1 )
			m_traffic_lines_index = 5
		end
		GameTooltip:AddDoubleLine( L.TRAFFIC, Me.GetTrafficFormatted(), 1,1,1, 1,1,1 )
		Me.Timer_Start( "traffic_tooltip", "ignore", 0.5, UpdateTrafficDisplay )
	else
		GameTooltip:AddLine( L.NOT_CONNECTED, 0.5,0.5, 0.5 )
		Me.Timer_Cancel( "traffic_tooltip" )
	end
	GameTooltip:AddLine( " " )
	GameTooltip:AddLine( L.MINIMAP_TOOLTIP_LEFTCLICK, 1, 1, 1 )
	GameTooltip:AddLine( L.MINIMAP_TOOLTIP_RIGHTCLICK, 1, 1, 1 )
	GameTooltip:Show()
	m_tooltip_frame = frame
	
end

-------------------------------------------------------------------------------
function Me.OnMinimapButtonLeave( frame )
	GameTooltip:Hide()
end

-------------------------------------------------------------------------------
local function ToggleChannel( self, arg1, arg2, checked )
	Me.ListenToChannel( arg1, checked )
end

-------------------------------------------------------------------------------
local function GetChannelColorCode( index )
	index = tostring(index)
	local color = Me.db.global["color_rp"..index:lower()]
	return string.format( "|cff%2x%2x%2x", color[1]*255, color[2]*255, color[3]*255 )
end

local function ToggleRelayClicked( self, arg1, arg2, checked )
	Me.EnableRelay( checked )
	local caption = L.RELAY
	if Me.relay_on then
		caption = "|cFF03FF11" .. caption
	end
	self:SetText( caption )
end

-------------------------------------------------------------------------------
local function InitializeMenu( self, level, menuList )
	local info
	if level == 1 then

		if not Me.connected then
			info = UIDropDownMenu_CreateInfo()
			info.text    = L.CROSS_RP
			info.isTitle = true
			info.notCheckable = true
			UIDropDownMenu_AddButton( info, level )
		end
		
		if Me.connected then
				
			info = UIDropDownMenu_CreateInfo()
			--info.colorCode    = 
			info.isTitle      = true;
			info.text         = L("CONNECTED_TO_SERVER", Me.GetServerName( true ))
			info.notCheckable = true
			UIDropDownMenu_AddButton( info, level )

			info = UIDropDownMenu_CreateInfo()
			info.text         = L.DISCONNECT
			info.notCheckable = true
			info.func         = function() Me.Disconnect() end
			info.tooltipTitle     = info.text
			info.tooltipText      = L.DISCONNECT_TOOLTIP
			info.tooltipOnButton  = true
			UIDropDownMenu_AddButton( info, level )
			
			info = UIDropDownMenu_CreateInfo()
			info.text             = L.RELAY
			if Me.relay_on then
				info.text = "|cFF03FF11" .. info.text
			end
			info.checked          = Me.relay_on
			info.isNotRadio       = true
			info.func             = ToggleRelayClicked
			info.tooltipTitle     = info.text
			info.tooltipText      = L.RELAY_TIP
			info.tooltipOnButton  = true
			info.keepShownOnClick = true
			UIDropDownMenu_AddButton( info, level )
			
		else
		
			if #(Me.GetServerList()) > 0 then
				info = UIDropDownMenu_CreateInfo()
				info.text             = L.CONNECT
				info.hasArrow         = true
				info.notCheckable     = true
				info.keepShownOnClick = true
				info.menuList         = "CONNECT"				
				info.tooltipTitle     = info.text
				info.tooltipText      = L.CONNECT_TOOLTIP
				info.tooltipOnButton  = true
				UIDropDownMenu_AddButton( info, level )
			else
				info = UIDropDownMenu_CreateInfo()
				info.text             = L.NO_SERVERS_AVAILABLE
				info.disabled         = true
				info.notCheckable     = true
				UIDropDownMenu_AddButton( info, level )
			end
		end
		
		UIDropDownMenu_AddSeparator( level )
		info = UIDropDownMenu_CreateInfo()
		info.text             = L.RP_CHANNELS
		info.hasArrow         = true
		info.notCheckable     = true
		info.keepShownOnClick = true
		info.tooltipTitle     = info.text
		info.tooltipText      = L.RP_CHANNELS_TOOLTIP
		info.tooltipOnButton  = true
		info.menuList         = "CHANNELS"
		UIDropDownMenu_AddButton( info, level )
		
		if Me.connected and Me.IsMuted() then
			info = UIDropDownMenu_CreateInfo()
			info.text         = L.RP_IS_MUTED
			info.notCheckable = true
			info.keepShownOnClick = true
			info.tooltipTitle     = info.text
			info.tooltipText      = L.RP_IS_MUTED_TOOLTIP
			info.tooltipOnButton  = true
			UIDropDownMenu_AddButton( info, level )
		end
		
		UIDropDownMenu_AddSeparator( level )
		info = UIDropDownMenu_CreateInfo()
		info.text         = L.SETTINGS
		info.notCheckable = true
		info.func         = Me.OpenOptions
		info.tooltipTitle     = info.text
		info.tooltipText      = L.SETTINGS_TIP
		info.tooltipOnButton  = true
		UIDropDownMenu_AddButton( info, level )
	
	elseif menuList == "CONNECT" then
		
		local servers = Me.GetServerList()
		for _,server in ipairs(servers) do
			info = UIDropDownMenu_CreateInfo()
			info.text             = server.name
			info.notCheckable     = true
			info.tooltipTitle     = server.name
			info.tooltipText      = L.CONNECT_TO_SERVER_TOOLTIP
			info.tooltipOnButton  = true
			info.checked          = Me.connected 
			                        and Me.club == server.club 
									and Me.stream == server.stream
			info.func = function()
				Me.Connect( server.club, true )
				Me.minimap_menu:Hide()
			end
			UIDropDownMenu_AddButton( info, level )
		end
	elseif menuList == "CHANNELS" then
		
		info = UIDropDownMenu_CreateInfo()
		info.text             = L.RP_WARNING
		info.arg1             = "W"
		info.colorCode        = GetChannelColorCode( "W" )
		info.func             = ToggleChannel
		info.checked          = Me.db.global.show_rpw
		info.isNotRadio       = true
		info.keepShownOnClick = true
		info.tooltipTitle     = info.text
		-- i was gonna say the "global warning" channel, heh heh
		info.tooltipText      = L.RP_WARNING_TOOLTIP
		info.tooltipOnButton  = true
		UIDropDownMenu_AddButton( info, level )
		
		for i = 1,9 do
			
			info = UIDropDownMenu_CreateInfo()
			if i == 1 then
				info.text         = L.RP_CHANNEL
			else
				info.text         = L("RP_CHANNEL_X", i)
			end
			info.arg1             = i
			info.colorCode        = GetChannelColorCode( i )
			info.func             = ToggleChannel
			info.checked          = Me.db.global["show_rp"..i]
			info.isNotRadio       = true
			info.keepShownOnClick = true
			info.tooltipTitle     = info.text
			if i == 1 then
				info.tooltipText  = L.RP_CHANNEL_1_TOOLTIP
			else
				info.tooltipText  = L.RP_CHANNEL_X_TOOLTIP
			end
			info.tooltipOnButton  = true
			UIDropDownMenu_AddButton( info, level )
		end
	end
end
		

function Me.OpenMinimapMenu( parent )
	
	if not Me.minimap_menu then
		Me.minimap_menu = CreateFrame( "Button", "CrossRPMinimapMenu", 
		                                 UIParent, "UIDropDownMenuTemplate" )
		Me.minimap_menu.displayMode = "MENU"
	end
	
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
	if UIDROPDOWNMENU_OPEN_MENU == Me.minimap_menu and Me.minimap_menu_parent == parent then
	
		-- the menu is already open at the same parent, so we close it.
		ToggleDropDownMenu( 1, nil, Me.minimap_menu )
		return
	end
	
	Me.minimap_menu_parent = parent
	
	UIDropDownMenu_Initialize( Me.minimap_menu, InitializeMenu )
	UIDropDownMenu_JustifyText( Me.minimap_menu, "LEFT" )
	
	ToggleDropDownMenu( 1, nil, Me.minimap_menu, parent:GetName(), offset_x or 0, offset_y or 0 )
	
end