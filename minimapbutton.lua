-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- The minimap button and menu.
-------------------------------------------------------------------------------
local _, Me  = ...
local L      = Me.Locale
local LDB    = LibStub( "LibDataBroker-1.1" )
local DBIcon = LibStub( "LibDBIcon-1.0"     )
-------------------------------------------------------------------------------
-- The communities frame is very unstable when it comes to taint issues, so
--  we don't use the Blizzard internal drop down menu stuff; instead we use
--  MSA-DropDownMenu as an easy replacement. As far as I know, it's just
--  Blizzard's code copied and renamed. We're doing it this way in the hopes
--  that Blizzard will unfuck their menus so we can use them directly.

local UIDropDownMenu_CreateInfo   = MSA_DropDownMenu_CreateInfo
local UIDropDownMenu_AddButton    = MSA_DropDownMenu_AddButton
local UIDropDownMenu_AddSeparator = function( level )
	MSA_DropDownMenu_AddSeparator( MSA_DropDownMenu_CreateInfo(), level )
end
local UIDropDownMenu_Initialize  = MSA_DropDownMenu_Initialize
local UIDropDownMenu_JustifyText = MSA_DropDownMenu_JustifyText
local ToggleDropDownMenu         = MSA_ToggleDropDownMenu

local DROPDOWNMENU_TEMPLATE      = "UIDropDownMenuTemplate"
local function GetOpenMenu()
	return MSA_DROPDOWNMENU_OPEN_MENU
	--return UIDROPDOWNMENU_OPEN_MENU
end
-------------------------------------------------------------------------------
-- The frame that the GameTooltip belongs to, if we're using it.
local m_tooltip_frame = nil
-------------------------------------------------------------------------------
-- What spot in the tooltip does the "Traffic: " line appear. This only shows
--  when the user is connected.
local m_traffic_lines_index = nil

-------------------------------------------------------------------------------
-- Called during setup, it initializes our LDB object and registers it, as well
--  as passes it to LibDBIcon so we can have a minimap button.
function Me.SetupMinimapButton()

	Me.ldb = LDB:NewDataObject( "CrossRP", {
		-- "data source" for addons to get a feed from and display our button.
		--  Titan Panel and other similar addons will also see this so they 
		--  can have our minimap button too.
		type    = "data source";
		
		-- The text that's displayed for addons like Titan Panel; this isn't
		--  used for the minimap button (LibDBIcon).
		text    = L.CROSS_RP;
		
		-- The label for this text, shown next to the text like a title. This
		--  will be mostly static, and the above will change according to the 
		--  connection state.
		label   = L.CROSS_RP;
		
		-- The icon that's paired with the text, or the icon for the minimap
		--  button.
		icon    = "Interface\\Icons\\INV_Jewelcrafting_ArgusGemCut_Red_MiscIcons";
		
		-- Mouse event handlers. These are used both for the minimap button
		--  and the relay indicator when connected.
		OnClick = Me.OnMinimapButtonClick;
		OnEnter = Me.OnMinimapButtonEnter;
		OnLeave = Me.OnMinimapButtonLeave;
		
		-- The color of the icon.
		iconR   = 1.0;
		iconG   = 1.0;
		iconB   = 1.0;
	})
	-- Second argument is a saved variables section. It uses that to read and
	--  save settings like if the minimap button is hidden, and handles all of
	--  that under the hood.
	DBIcon:Register( "CrossRP", Me.ldb, Me.db.global.minimapbutton )
end

-------------------------------------------------------------------------------
-- Called when the minimap button or anything hooked to act the same way is
--  clicked.
function Me.OnMinimapButtonClick( frame, button )
	if button == "LeftButton" and frame ~= Me.indicator.thumb then
		if Me.connected then
			if Me.relay_on then
				if Me.relay_idle then
					Me.ResetRelayIdle( true )
				else
					Me.EnableRelay( false )
				end
			else
				Me.EnableRelay( true )
			end
		else
			GameTooltip:Hide()
			Me.OpenMinimapMenu( frame )
		end
	elseif button == "LeftButton" or button == "RightButton" then
		GameTooltip:Hide()
		Me.OpenMinimapMenu( frame )
	end
end

-------------------------------------------------------------------------------
local function FormatTimePeriod( t )
	local seconds = math.floor( t ) % 60
	local minutes = math.floor( t / 60 ) % 60
	local hours = math.floor( t / (60*60) )
	if hours > 0 then
		return string.format( "%d:%02d:%02d", hours, minutes, seconds )
	else
		return string.format( "%d:%02d", minutes, seconds )
	end
end

-------------------------------------------------------------------------------
function Me.FormatIdleTime()
	return FormatTimePeriod( GetTime() - Me.relay_active_time )
end

-------------------------------------------------------------------------------
function Me.FormatUptime()
	return FormatTimePeriod( GetTime() - Me.connect_time )
end

-------------------------------------------------------------------------------
function Me.RefreshMinimapTooltip()
	GameTooltip:ClearLines()
	-- Name, version.
	GameTooltip:AddDoubleLine( L.CROSS_RP, 
	                   GetAddOnMetadata( "CrossRP", "Version" ), 1,1,1, 1,1,1 )
	if Me.DEBUG_MODE then
		GameTooltip:AddLine( "|cFFFFFF00Debug Mode", 1,1,1 )
	end
	GameTooltip:AddLine( " " )
	
	-- If connected, show connected label and traffic usage.
	-- Otherwise, show "Not Connected"
	if Me.connected then
		local relay_info = Me.GetRelayInfo( Me.club, Me.stream )
		GameTooltip:AddLine( L( "CONNECTED_TO_SERVER", 
		                                    relay_info.clubinfo.name ), 1,1,1 )
		if relay_info.name then
			GameTooltip:AddLine( "|cFF03FF11" .. relay_info.name, 1,1,1 )
		end
		if Me.relay_on then
			if Me.relay_idle then
				GameTooltip:AddLine( "|cff20b5e7" .. L.RELAY_IDLE, 1,1,1 )
			else
				GameTooltip:AddLine( "|cFF03FF11" .. L.RELAY_ACTIVE, 1,1,1 )
			end
		end
		GameTooltip:AddDoubleLine( L.TRAFFIC, Me.GetTrafficFormatted(), 
		                                                         1,1,1, 1,1,1 )
		if Me.DEBUG_MODE then
			-- With debug mode we can show some more advanced statistics, like
			--  the smooth traffic value used in the relay timing.
			GameTooltip:AddDoubleLine( "Traffic/Smooth", 
			                     Me.GetTrafficFormatted( true ), 1,1,1, 1,1,1 )
		end
		GameTooltip:AddDoubleLine( L.UPTIME, Me.FormatUptime(), 
		                                                         1,1,1, 1,1,1 )
		if Me.relay_on then
			GameTooltip:AddDoubleLine( L.IDLE_TIME, Me.FormatIdleTime(), 
		                                                         1,1,1, 1,1,1 )
		end
		
		GameTooltip:AddLine( " " )
		
		if m_tooltip_frame == Me.indicator.thumb then
			GameTooltip:AddLine( L.MINIMAP_TOOLTIP_CLICK_OPEN_MENU, 1,1,1 )
		else
			if Me.relay_idle then
				GameTooltip:AddLine( L.MINIMAP_TOOLTIP_RESET_RELAY, 1,1,1 )
			else
				GameTooltip:AddLine( L.MINIMAP_TOOLTIP_TOGGLE_RELAY, 1,1,1 )
			end
			GameTooltip:AddLine( L.MINIMAP_TOOLTIP_RIGHTCLICK_OPEN_MENU, 
			                                                            1,1,1 )
		end
	else
		GameTooltip:AddLine( L.NOT_CONNECTED, 0.5, 0.5, 0.5 )
		GameTooltip:AddLine( " " )
		GameTooltip:AddLine( L.MINIMAP_TOOLTIP_CLICK_OPEN_MENU, 1,1,1 )
	end
	
	GameTooltip:Show()
	return true
end

-------------------------------------------------------------------------------
local function UpdateTooltipTicker()
	if GameTooltip:GetOwner() ~= m_tooltip_frame
	                                        or (not GameTooltip:IsShown()) then
		return
	end
	Me.RefreshMinimapTooltip()
	Me.Timer_Start( "minimap_tooltip", "push", 1.0, UpdateTooltipTicker )
end

-------------------------------------------------------------------------------
function Me.OnMinimapButtonEnter( frame )
	GameTooltip:SetOwner( frame, "ANCHOR_NONE" )
	GameTooltip:SetPoint( "TOPRIGHT", frame, "BOTTOMRIGHT", 0, 0 )
	m_tooltip_frame = frame
	Me.RefreshMinimapTooltip()
	Me.Timer_Start( "minimap_tooltip", "push", 1.0, UpdateTooltipTicker )
end

-------------------------------------------------------------------------------
-- Handler for when mouse leaves the interactive area.
function Me.OnMinimapButtonLeave( frame )
	GameTooltip:Hide()
end

-------------------------------------------------------------------------------
-- Handler for the channel buttons.
local function ToggleChannel( self, arg1, arg2, checked )
	Me.ListenToChannel( arg1, checked )
end

-------------------------------------------------------------------------------
-- Returns the color code of one of our RP channels; `index` may be 1-9 or "W".
local function GetChannelColorCode( index )
	index = tostring(index)
	local color = Me.db.global["color_rp"..index:lower()]
	return string.format( "|cff%2x%2x%2x", color[1]*255, color[2]*255, color[3]*255 )
end

-------------------------------------------------------------------------------
-- Handler for the Relay button.
local function ToggleRelayClicked( self, arg1, arg2, checked )
	-- Toggle relay and update our caption. The checkbox is already updated
	--  by the menu side.
	Me.EnableRelay( checked )
	local caption = L.RELAY
	if Me.relay_on then
		caption = "|cFF03FF11" .. caption
	end
	self:SetText( caption )
end

-------------------------------------------------------------------------------
-- Initializer for the minimap button menu.
local function InitializeMenu( self, level, menuList )
	local info
	if level == 1 then

		-- If we aren't connected, show "Cross RP", otherwise we just show
		--  the connection label.
		if not Me.connected then
			info = UIDropDownMenu_CreateInfo()
			info.text    = L.CROSS_RP
			info.isTitle = true
			info.notCheckable = true
			UIDropDownMenu_AddButton( info, level )
		end
		
		if Me.connected then
			
			local relay_info = Me.GetRelayInfo( Me.club, Me.stream )
			-- "Connected to server" title.
			info = UIDropDownMenu_CreateInfo()
			info.isTitle      = true;
			info.text         = "|cFF03FF11" .. relay_info.clubinfo.name
			info.notCheckable = true
			UIDropDownMenu_AddButton( info, level )
			
			if relay_info.name then
				info.text         = "|cFF03FF11" .. relay_info.name
				UIDropDownMenu_AddButton( info, level )
			end

			-- Disconnect button.
			info = UIDropDownMenu_CreateInfo()
			info.text             = L.DISCONNECT
			info.notCheckable     = true
			info.func             = function() Me.Disconnect() end
			info.tooltipTitle     = info.text
			info.tooltipText      = L.DISCONNECT_TOOLTIP
			info.tooltipOnButton  = true
			UIDropDownMenu_AddButton( info, level )
			
			-- UI code always has a way to be quite bloated, doesn't it? It's
			--  a necessary evil, so things can be flexible to just how you
			--  want it. A good UI has a good feel to it.
			
			-- Relay toggle.
			info = UIDropDownMenu_CreateInfo()
			info.text             = L.RELAY
			if Me.relay_on then
				info.text = "|cFF03FF11" .. info.text
			end
			info.checked          = Me.relay_on
			info.isNotRadio       = true
			info.func             = ToggleRelayClicked
			info.tooltipTitle     = L.RELAY
			info.tooltipText      = L.RELAY_TIP
			info.tooltipOnButton  = true
			info.keepShownOnClick = true
			UIDropDownMenu_AddButton( info, level )
			
		else
		
			-- If not connected, we check to see if we have any servers to
			--  connect to. If we do, then we show the Connect dropdown
			--  button to select one. Otherwise, we let them know that they
			--  don't have any servers: "No servers available".
			if #(Me.GetServerList()) > 0 then
				-- Connect arrow-button.
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
				-- No servers available label.
				info = UIDropDownMenu_CreateInfo()
				info.text             = L.NO_SERVERS_AVAILABLE
				info.disabled         = true
				info.notCheckable     = true
				UIDropDownMenu_AddButton( info, level )
			end
		end
		
		-- Channels arrow-button.
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
		
		-- If the RP channel is muted, then we show that here too.
		if Me.connected and Me.IsMuted() then
			-- "RP is Muted"
			info = UIDropDownMenu_CreateInfo()
			info.text         = L.RP_IS_MUTED
			info.notCheckable = true
			info.keepShownOnClick = true
			info.tooltipTitle     = info.text
			info.tooltipText      = L.RP_IS_MUTED_TOOLTIP
			info.tooltipOnButton  = true
			UIDropDownMenu_AddButton( info, level )
		end
		
		-- Settings button.
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
		
		-- Buttons to connect to servers. GetServerList returns a sorted table
		--  for our convenience.
		for _,server in ipairs( Me.GetServerList() ) do
			info = UIDropDownMenu_CreateInfo()
			info.text             = server.name
			info.notCheckable     = true
			info.tooltipTitle     = server.info.clubinfo.name
			if server.info.name then
				info.tooltipText      = server.info.name .. "\n\n" .. L.CONNECT_TO_SERVER_TOOLTIP
			else
				info.tooltipText      = L.CONNECT_TO_SERVER_TOOLTIP
			end
			info.tooltipOnButton  = true
			info.func = function()
				Me.Connect( server.club, server.stream, true )
				ToggleDropDownMenu( 1, nil, Me.minimap_menu )
			end
			UIDropDownMenu_AddButton( info, level )
		end
	elseif menuList == "CHANNELS" then
		
		-- RP Warning toggle.
		info = UIDropDownMenu_CreateInfo()
		info.text             = L.RP_WARNING
		info.arg1             = "W"
		info.colorCode        = GetChannelColorCode( "W" )
		info.func             = ToggleChannel
		info.checked          = Me.db.global.show_rpw
		info.isNotRadio       = true
		info.keepShownOnClick = true
		info.tooltipTitle     = info.text
		-- I was gonna say the "global warning" channel, heh heh.
		info.tooltipText      = L.RP_WARNING_TOOLTIP
		info.tooltipOnButton  = true
		UIDropDownMenu_AddButton( info, level )
		
		-- RP1-9 toggles.
		for i = 1,9 do
			
			-- One cool thing that we can do here is not call
			--  UIDropDownMenu_CreateInfo, and the previous setup acts like a
			--  template that we inherit down here, so we can skip setting some
			--  values--all these buttons behave the same way.
			if i == 1 then
				info.text         = L.RP_CHANNEL
			else
				info.text         = L("RP_CHANNEL_X", i)
			end
			info.arg1             = i
			info.colorCode        = GetChannelColorCode( i )
			info.checked          = Me.db.global["show_rp"..i]
			info.tooltipTitle     = info.text
			if i == 1 then
				info.tooltipText  = L.RP_CHANNEL_1_TOOLTIP
			else
				info.tooltipText  = L.RP_CHANNEL_X_TOOLTIP
			end
			UIDropDownMenu_AddButton( info, level )
		end
	end
end

-------------------------------------------------------------------------------
-- Open the minimap menu under this parent frame. The parent frame must be a
--  named frame.
function Me.OpenMinimapMenu( parent )
	
	if not Me.minimap_menu then
		Me.minimap_menu = CreateFrame( "Button", "CrossRPMinimapMenu", 
		                                 UIParent, DROPDOWNMENU_TEMPLATE )
	end
	
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
	if GetOpenMenu() == Me.minimap_menu and Me.minimap_menu_parent == parent then
	
		-- The menu is already open at the same parent, so we close it.
		ToggleDropDownMenu( 1, nil, Me.minimap_menu )
		return
	end
	
	Me.minimap_menu_parent = parent
	
	UIDropDownMenu_Initialize( Me.minimap_menu, InitializeMenu, "MENU" )
	UIDropDownMenu_JustifyText( Me.minimap_menu, "LEFT" )
	
	ToggleDropDownMenu( 1, nil, Me.minimap_menu, parent:GetName(), 
	                                             offset_x or 0, offset_y or 0 )
end
