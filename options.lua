-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- The options panel.
-------------------------------------------------------------------------------
local _, Me           = ...
local L               = Me.Locale
local AceConfig       = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local DBIcon          = LibStub( "LibDBIcon-1.0" )

-------------------------------------------------------------------------------
-- Converts a hex color RRGGBB into an array {r, g, b} with normalized (0-1)
--  values.
local function Hexc( hex )
	return {
		tonumber( hex:sub(1,2), 16 )/255;
		tonumber( hex:sub(3,4), 16 )/255;
		tonumber( hex:sub(5,6), 16 )/255;
	}
end

-------------------------------------------------------------------------------
-- Database template/default values.
local DB_DEFAULTS = {
	---------------------------------------------------------------------------
	-- Per-character variables.
	char = {
		-----------------------------------------------------------------------
		-- The club that they're currently connected to. Used for the
		--  autoconnect feature.
		connected_club = nil; 
		-----------------------------------------------------------------------
		-- The time when the user logged out. This is unixtime, not GameTime.
		--  Saved during PLAYER_LOGOUT. This is used with `relay_on` to tell
		--  if we should enable the relay or not (we give a small grace period
		--  to let someone relog).
		logout_time    = 0;
		-----------------------------------------------------------------------
		-- If we should try to enable the relay when they log in. Mimics the
		--  `Me.relay_on` value.
		relay_on       = nil;
	};
	
	---------------------------------------------------------------------------
	-- Global variables (shared accountwide).
	global = {
		-----------------------------------------------------------------------
		-- Section for LibDBIcon to save its minimap button data.
		minimapbutton = {};
		-----------------------------------------------------------------------
		-- Enable chat bubble translations.
		bubbles       = true;
		-----------------------------------------------------------------------
		-- Enable the "Whisper" button in the target frame's context menu.
		--  This only hides that button. With this off, you can still /w Horde
		--  characters so long as you have them on battletag. If you hate UI
		--  taint, you might want to turn this off.
		whisper_horde = true;
		-----------------------------------------------------------------------
		-- Enables the relay indicator at the top of the screen, meant to
		--  remind you that your chat isn't as private as you might think it
		--  is.
		indicator     = true;
		-----------------------------------------------------------------------
		-- Enables drawing map blips on the map of player's last seen
		--  locations, pulled from the relay data.
		map_blips     = true;
		-----------------------------------------------------------------------
		-- Colors for the RP channels, inserted into the ChatTypeInfo table
		--  so everything gets colored by them.
		color_rpw = Hexc "EA3556"; -- RP Warning
		color_rp1 = Hexc "Ffbb11"; -- RP
		color_rp2 = Hexc "d78d46"; -- RP2
		color_rp3 = Hexc "cbd746"; -- RP3
		color_rp4 = Hexc "80d746"; -- RP4
		color_rp5 = Hexc "46d7ac"; -- RP5
		color_rp6 = Hexc "4691d7"; -- RP6
		color_rp7 = Hexc "9c53ff"; -- RP7
		color_rp8 = Hexc "c449e3"; -- RP8
		color_rp9 = Hexc "d15ea2"; -- RP9
		-----------------------------------------------------------------------
		-- Toggles for filtering the RP channels from your chat boxes. These
		--  don't apply to Listener, as it has its own filters built-in.
		show_rpw = true; -- RP Warning
		show_rp1 = true; -- RP
		show_rp2 = true; -- RP2
		show_rp3 = true; -- RP3
		show_rp4 = true; -- RP4
		show_rp5 = true; -- RP5
		show_rp6 = true; -- RP6
		show_rp7 = true; -- RP7
		show_rp8 = true; -- RP8
		show_rp9 = true; -- RP9
	};
}

-------------------------------------------------------------------------------
-- Helper function to create a chat color option. Above it's not so bad, just
--  one line per each thing, but if we repeated the toggle option structure
--                                      like that, it'd get messy quick.
local m_next_chat_color_order = 1
local function ChatColorOption( key, name, desc )
	m_next_chat_color_order = m_next_chat_color_order + 10
	return {
		order = m_next_chat_color_order;
		name = name;
		desc = desc;
		type = "color";
		set = function( info, r, g, b )
			Me.db.global["color_"..key] = { r, g, b }
			Me.ApplyColorOptions()
		end;
		get = function( info )
			local color = Me.db.global["color_"..key]
			return color[1], color[2], color[3]
		end;
	};
end

-------------------------------------------------------------------------------
-- AceConfig-3.0 options table.
local OPTIONS_TABLE = {
	type = "group";
	-- I'm not even sure why we localize this string. The addon name shouldn't
	--  be changed to prevent any confusion.
	name = L.CROSS_RP;
	args = {
		-- This page is added into the Interface panel addon options.
		desc = { 
			order = 10; 
			name = L( "VERSION_LABEL", GetAddOnMetadata( "CrossRP", "Version" ))
			       .. "|n" .. L.BY_AUTHOR;
			type = "description";
		};
		
		-- Minimap button toggle.
		minimap_button = {
			order = 20;
			name  = L.OPTION_MINIMAP_BUTTON;
			desc  = L.OPTION_MINIMAP_BUTTON_TIP;
			-- We use width="full" for a lot of these to make the checkboxes
			--  each take up one line. I don't really like how the default
			--  layout throws multiple things together on the same line. ONly
			--  ugly thing about this is that the tooltip pops up too far
			--  to the right (at the end of this "full width").
			width = "full";
			type  = "toggle";
			set   = function( info, val )
				Me.db.global.minimapbutton.hide = not val
				Me.ApplyOptions()
			end;
			get = function( info )
				return not Me.db.global.minimapbutton.hide
			end;
		};
		
		-- Whisper horde button.
		whisper_horde = {
			order = 31;
			name  = L.OPTION_WHISPER_BUTTON;
			desc  = L.OPTION_WHISPER_BUTTON_TIP;
			width = "full";
			type  = 'toggle';
			set   = function( info, val )
				Me.db.global.whisper_horde = val;
			end;
			get = function( info ) return Me.db.global.whisper_horde end;
		};
		
	}
}

-------------------------------------------------------------------------------
-- Inserts our color codes into ChatTypeInfo. When we initialize that, we just
--  insert dummy colors, waiting for this function to insert the proper colors
--                                                    from the saved settings.
function Me.ApplyColorOptions()
	for i = 1, 9 do
		ChatTypeInfo["RP"..i].r  = Me.db.global["color_rp"..i][1]
		ChatTypeInfo["RP"..i].g  = Me.db.global["color_rp"..i][2]
		ChatTypeInfo["RP"..i].b  = Me.db.global["color_rp"..i][3]
	end
	ChatTypeInfo["RPW"].r = Me.db.global.color_rpw[1]
	ChatTypeInfo["RPW"].g = Me.db.global.color_rpw[2]
	ChatTypeInfo["RPW"].b = Me.db.global.color_rpw[3]
end

-------------------------------------------------------------------------------
-- Apply all options. We separate the colors one above because it can get very
--             spammy with dragging the color wheel/selector around in the UI.
function Me.ApplyOptions()
	Me.ApplyColorOptions()
	
	if Me.db.global.minimapbutton.hide then
		DBIcon:Hide( "CrossRP" )
	else
		DBIcon:Show( "CrossRP" )
	end

	Me.UpdateIndicators()
end

-------------------------------------------------------------------------------
-- Called before most of everything else to initialize our database. Must be
--             called after ADDON_LOADED, so that it can fetch our saved data.
function Me.CreateDB()
	Me.db = LibStub( "AceDB-3.0" ):New( "CrossRP_Saved", DB_DEFAULTS, true )
	AceConfig:RegisterOptionsTable( "CrossRP", OPTIONS_TABLE )
	AceConfigDialog:AddToBlizOptions( "CrossRP", L.CROSS_RP )
end

-------------------------------------------------------------------------------
-- Open the interface options and navigate to our section.
--
function Me.OpenOptions()
	-- If you don't manually call Show() then the panel won't open right
	--  the first time. It's OnShow hook tests to see if anything is displayed,
	--  and your OpenToCategory call will be overwritten.
	InterfaceOptionsFrame:Show()
	InterfaceOptionsFrame_OpenToCategory( "Cross RP" )
end
