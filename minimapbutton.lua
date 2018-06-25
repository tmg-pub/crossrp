
local _, Me = ...

local LDB          = LibStub:GetLibrary( "LibDataBroker-1.1" )
local DBIcon       = LibStub:GetLibrary( "LibDBIcon-1.0"     )

function Me.SetupMinimapButton()

	Me.ldb = LDB:NewDataObject( "RPLink", {
		type = "data source";
		text = "RP Link";
		icon = "Interface\\Icons\\Spell_Shaman_SpiritLink";
		OnClick = Me.OnMinimapButtonClick;
		OnEnter = Me.OnEnter;
		OnLeave = Me.OnLeave;
		iconR = 0.5;
		iconG = 0.5;
		iconB = 0.5;
	--	OnTooltip = Me.OnTooltip;
	})
	DBIcon:Register( "RPLink", Me.ldb, Me.db.global.minimapbutton )
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

-------------------------------------------------------------------------------
function Me.OnEnter( frame )
	GameTooltip:SetOwner( frame, "ANCHOR_NONE" )
	GameTooltip:SetPoint( "TOPRIGHT", frame, "BOTTOMRIGHT", 0, 0 )
	
	GameTooltip:AddDoubleLine( "RP Link", GetAddOnMetadata( "RPLink", "Version" ), 1, 1, 1, 1, 1, 1 )
	GameTooltip:AddLine( " " )
	GameTooltip:AddLine( "|cff00ff00Left-click|r to open menu.", 1, 1, 1 )
	GameTooltip:AddLine( "|cff00ff00Right-click|r for options.", 1, 1, 1 )
	GameTooltip:Show()
end

-------------------------------------------------------------------------------
function Me.OnLeave( frame )
	GameTooltip:Hide()
end

--[[


local function InitializeMenu2( self, level, menuList )
	if level == 1 then
		local info
		info = UIDropDownMenu_CreateInfo()
		info.text    = "Windows"
		info.isTitle = true
		info.notCheckable = true
		UIDropDownMenu_AddButton( info, level )
		
		local frames = {}
		
		-- we add everything but first frame
		for _, f in pairs( Main.frames ) do
			if f.frame_index > 2 then
				table.insert( frames, f )
			end
		end
		-- we sort the frames by their name
		table.sort( frames, function( a, b )
			local an, bn = Main.db.char.frames[a.frame_index].name or "", Main.db.char.frames[b.frame_index].name or ""
			return an < bn
		end)
		
		-- and the first/primary frame always appears at the top.
		table.insert( frames, 1, Main.frames[2] )
		table.insert( frames, 1, Main.frames[1] )
		
		for _, f in ipairs( frames ) do
			local name = f.charopts.name
			if f.frame_index == 1 then name = L["Main"] end
			if f.frame_index == 2 then name = L["Snooper"] end
			
			info = UIDropDownMenu_CreateInfo()
			info.text = name
			info.func = function()
				f.combat_ignore = true
				f:Toggle()
			end
			info.notCheckable = false
			info.isNotRadio   = true
			info.hasArrow     = true
			if f.frame_index ~= 2 then
				info.menuList   = "FRAMEOPTS_" .. f.frame_index
			else
				info.menuList   = "SNOOPER"
			end
			info.tooltipTitle     = name
			info.tooltipText      = L["Click to toggle frame."]
			info.tooltipOnButton  = true
			info.checked      = not f.charopts.hidden
			info.keepShownOnClick = true
			UIDropDownMenu_AddButton( info, level )
		end
		
		info = UIDropDownMenu_CreateInfo()
		if C_Club then -- 7.x compat
			UIDropDownMenu_AddSeparator( level )
		else
			UIDropDownMenu_AddSeparator( info, level )
		end
		
		info = UIDropDownMenu_CreateInfo()
		info.text             = L["DM Tags"]
		info.notCheckable     = false
		info.isNotRadio       = true
		info.hasArrow         = true
		info.menuList         = "DMTAGS"
		info.checked          = Main.db.char.dmtags
		info.func             = function( self, a1, a2, checked )
			Main.DMTags.Enable( checked )
		end
		info.keepShownOnClick = true
		info.tooltipTitle     = L["Enable DM tags."]
		info.tooltipText      = L["This is a helper feature for dungeon masters. It tags your unit frames with whoever has unmarked messages."]
		info.tooltipOnButton  = true
		UIDropDownMenu_AddButton( info, level )
		
		info = UIDropDownMenu_CreateInfo()
		if C_Club then -- 7.x compat
			UIDropDownMenu_AddSeparator( level )
		else
			UIDropDownMenu_AddSeparator( info, level )
		end
		
		info = UIDropDownMenu_CreateInfo()
		info.text = L["Settings"]
		info.func = function()
			Main.OpenConfig()
		end
		info.notCheckable = true
		UIDropDownMenu_AddButton( info, level )
		
	elseif menuList == "DMTAGS" then
		
		info = UIDropDownMenu_CreateInfo()
		info.text             = L["Mark All"]
		info.notCheckable     = true
		info.hasArrow         = false
		info.func             = function( self, a1, a2, checked )
			Main.DMTags.MarkAll()
		end
		info.tooltipTitle     = L["Mark all players."]
		info.tooltipText      = L["Clears any waiting DM tags."]
		info.tooltipOnButton  = true
		UIDropDownMenu_AddButton( info, level )
	elseif menuList and menuList:find("FILTERS") then
		Main.PopulateFilterMenu( level, menuList )
	elseif menuList and menuList:find( "FRAMEOPTS" ) then
		Main.Frame.PopulateFrameMenu( level, menuList )
	elseif menuList and menuList:find("SNOOPER") then
		Main.Snoop2.PopulateMenu( level, menuList )
	end
end

-------------------------------------------------------------------------------
-- Initializer for the frames menu. This is the menu that shows up when you
-- left-click.
--
local function InitializeFramesMenu( self, level, menuList )
	
	if level == 1 then
		local info
		

		
		
	end
end

-------------------------------------------------------------------------------
-- Initializer for the options menu. This is the right-click menu.
--
local function InitializeOptionsMenu( self, level, menuList )
	if level == 1 then
		local info
		info = UIDropDownMenu_CreateInfo()
		info.text         = "Listener"
		info.isTitle      = true
		info.notCheckable = true
		UIDropDownMenu_AddButton( info, level )
		
		info = UIDropDownMenu_CreateInfo()
		info.text             = L["Snooper"]
		info.notCheckable     = true
		info.hasArrow         = true
		info.menuList         = "SNOOPER"
		info.keepShownOnClick = true
		UIDropDownMenu_AddButton( info, level )
		
	elseif menuList and menuList:find("FILTERS") then
		Main.PopulateFilterMenu( level, menuList )
	elseif menuList and menuList:find( "SNOOPER" ) then
		Main.Snoop2.PopulateMenu( level, menuList )
	end
end

-------------------------------------------------------------------------------
-- Open up one of the minimap menus.
--
-- @param menu "FRAMES" or "OPTIONS"
--
function Me.ShowMenu( parent, menu )

	local menus = {
		MENU2   = InitializeMenu2;
	}
	
	Main.ToggleMenu( parent, "minimap_menu_" .. menu, menus[menu] )
end

-------------------------------------------------------------------------------
-- OnEnter script handler, for setting up the tooltip.
--
function Me.OnEnter( frame ) 
	Main.StartTooltip( frame )
	
	GameTooltip:AddDoubleLine("Listener", Main.version, 0, 0.7, 1, 1, 1, 1)
	GameTooltip:AddLine( " " )
--[-[	
	local window_count = 0
	for _,_ in pairs( Main.frames ) do
		window_count = window_count + 1
	end]-]
	
--	if window_count < 3 then
		GameTooltip:AddLine( L["|cff00ff00Left-click|r to open menu."], 1, 1, 1 )
--	else
--		GameTooltip:AddLine( L["|cff00ff00Left-click|r to toggle windows."], 1, 1, 1 )
--	end
	
	GameTooltip:AddLine( L["|cff00ff00Right-click|r to open settings."], 1, 1, 1 )
	GameTooltip:Show()
end
 

]]
local function ToggleChannel( self, arg1, arg2, checked )
	Me.ListenToChannel( arg1, checked )
end

local function GetChannelColorCode( index )
	index = tostring(index)
	local color = Me.db.global["color_rp"..index:lower()]
	return string.format( "|cff%2x%2x%2x", color[1]*255, color[2]*255, color[3]*255 )
end

local function InitializeMenu( self, level, menuList )
	local info
	if level == 1 then
	
		if not Me.connected then
			info = UIDropDownMenu_CreateInfo()
			info.text    = "RP Link"
			info.isTitle = true
			info.notCheckable = true
			UIDropDownMenu_AddButton( info, level )
		end
		
		if Me.connected then
				
			local club_info = C_Club.GetClubInfo( Me.club )
			if club_info then
				info = UIDropDownMenu_CreateInfo()
				--info.colorCode    = 
				info.isTitle      = true;
				info.text         = "|cFF03FF11Connected to " .. club_info.shortName or club_info.name
				info.notCheckable = true
				UIDropDownMenu_AddButton( info, level )
			end
			info = UIDropDownMenu_CreateInfo()
			info.text         = "Disconnect"
			info.notCheckable = true
			info.func         = Me.Disconnect
			UIDropDownMenu_AddButton( info, level )
		else
		
			if #(Me.GetServerList()) > 0 then
				info = UIDropDownMenu_CreateInfo()
				info.text             = "Connect"
				info.hasArrow         = true
				info.notCheckable     = true
				info.keepShownOnClick = true
				info.menuList         = "CONNECT"
				UIDropDownMenu_AddButton( info, level )
			else
				info = UIDropDownMenu_CreateInfo()
				info.text             = "No servers available."
				info.disabled         = true
				info.notCheckable     = true
				UIDropDownMenu_AddButton( info, level )
			end
		end
		
		UIDropDownMenu_AddSeparator( level )
		info = UIDropDownMenu_CreateInfo()
		info.text             = "RP Channels"
		info.hasArrow         = true
		info.notCheckable     = true
		info.keepShownOnClick = true
		info.menuList         = "CHANNELS"
		UIDropDownMenu_AddButton( info, level )
		
		UIDropDownMenu_AddSeparator( level )
		info = UIDropDownMenu_CreateInfo()
		info.text         = "Settings"
		info.notCheckable = true
		info.func         = Me.OpenOptions
		UIDropDownMenu_AddButton( info, level )
	
	elseif menuList == "CONNECT" then
		
		local servers = Me.GetServerList()
		for _,server in ipairs(servers) do
			info = UIDropDownMenu_CreateInfo()
			info.text             = server.name
			info.notCheckable     = true
			info.tooltipTitle     = server.name
			info.tooltipText      = "Click to connect."
			info.tooltipOnButton  = true
			info.checked          = Me.connected 
			                        and Me.club == server.club 
									and Me.stream == server.stream
			info.func = function()
				Me.Connect( server.club )
				Me.minimap_menu:Hide()
			end
			UIDropDownMenu_AddButton( info, level )
		end
	elseif menuList == "CHANNELS" then
		
		info = UIDropDownMenu_CreateInfo()
		info.text             = "RP Warning"
		info.arg1             = "W"
		info.colorCode        = GetChannelColorCode( "W" )
		info.func             = ToggleChannel
		info.checked          = Me.db.global.show_rpw
		info.isNotRadio       = true
		info.keepShownOnClick = true
		info.tooltipTitle     = info.text
		-- i was gonna say the "global warning" channel, heh heh
		info.tooltipText      = "The global alert channel. This is accessed by community Leaders only with /rpw."
		info.tooltipOnButton  = true
		UIDropDownMenu_AddButton( info, level )
		
		for i = 1,9 do
			
			info = UIDropDownMenu_CreateInfo()
			if i == 1 then
				info.text         = "RP Channel"
			else
				info.text         = "RP Channel " .. i
			end
			info.arg1             = i
			info.colorCode        = GetChannelColorCode( i )
			info.func             = ToggleChannel
			info.checked          = Me.db.global["show_rp"..i]
			info.isNotRadio       = true
			info.keepShownOnClick = true
			info.tooltipTitle     = info.text
			if i == 1 then
				info.tooltipText  = "The global RP channel for this community. May be limited to announcements only. Access through /rp."
			else
				info.tooltipText  = "Channels 2-9 are meant for smaller sub-events. Access through /rp#."
			end
			info.tooltipOnButton  = true
			UIDropDownMenu_AddButton( info, level )
		end
	end
end
		

function Me.OpenMinimapMenu( parent )
	
	if not Me.minimap_menu then
		Me.minimap_menu = CreateFrame( "Button", "RPLinkMinimapMenu", 
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