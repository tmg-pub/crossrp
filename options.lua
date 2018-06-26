
local _, Me = ...

local AceConfig       = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local DBIcon          = LibStub:GetLibrary( "LibDBIcon-1.0" )

-------------------------------------------------------------------------------
local function Hexc( hex )
	return {
		tonumber( "0x"..hex:sub(1,2) )/255;
		tonumber( "0x"..hex:sub(3,4) )/255;
		tonumber( "0x"..hex:sub(5,6) )/255;
	}
end

-------------------------------------------------------------------------------
local DB_DEFAULTS = {
	global = {
		minimapbutton = {};
		
		bubbles       = true;
		whisper_horde = true;
		indicator     = true;
		
		color_rp1 = Hexc "Ffbb11";
		color_rpw = Hexc "EA3556";
		color_rp2 = Hexc "d78d46";
		color_rp3 = Hexc "cbd746";
		color_rp4 = Hexc "80d746";
		color_rp5 = Hexc "46d7ac";
		color_rp6 = Hexc "4691d7";
		color_rp7 = Hexc "9c53ff";
		color_rp8 = Hexc "c449e3";
		color_rp9 = Hexc "d15ea2";
		
		show_rp1 = Hexc "BAE4E5";
		show_rp2 = Hexc "BAE4E5";
		show_rp3 = Hexc "BAE4E5";
		show_rp4 = Hexc "BAE4E5";
		show_rp5 = Hexc "BAE4E5";
		show_rp6 = Hexc "BAE4E5";
		show_rp7 = Hexc "BAE4E5";
		show_rp8 = Hexc "BAE4E5";
		show_rp9 = Hexc "BAE4E5";
		show_rpw = Hexc "EA3556";
	};
}

-------------------------------------------------------------------------------
local m_next_chat_color_order = 0

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
local OPTIONS_TABLE = {
	
	type = "group";
	name = "Cross RP";
	args = {
		desc = { 
			order = 10; 
			name = L( "VERSION_LABEL", GetAddOnMetadata( "CrossRP", "Version" ))
			       .. "|n" .. L.BY_AUTHOR;
			type = "description";
		};
		
		minimap_button = {
			order = 20;
			name = L.OPTION_MINIMAP_BUTTON;
			desc = L.OPTION_MINIMAP_BUTTON_TIP;
			width = "full";
			type = "toggle";
			set = function( info, val )
				Me.db.global.minimapbutton.hide = not val
				Me.ApplyOptions()
			end;
			get = function( info )
				return not Me.db.global.minimapbutton.hide
			end;
		};
		
		translate_bubbles = {
			order = 30;
			name = L.OPTION_TRANSLATE_CHAT_BUBBLES;
			desc = L.OPTION_TRANSLATE_CHAT_BUBBLES_TIP;
			width = "full";
			type = "toggle";
			set = function( info, val )
				Me.db.global.bubbles = val;
			end;
			get = function( info ) return Me.db.global.bubbles end;
		};
		
		whisper_horde = {
			order = 31;
			name = L.OPTION_WHISPER_BUTTON;
			desc = L.OPTION_WHISPER_BUTTON_TIP;
			width = "full";
			type = 'toggle';
			set = function( info, val )
				Me.db.global.whisper_horde = val;
			end;
			get = function( info ) return Me.db.global.whisper_horde end;
		};
		indicator = {
			order = 32;
			name = L.OPTION_INDICATOR;
			desc = L.OPTION_INDICATOR_TIP;
			width = "full";
			type = 'toggle';
			set = function( info, val )
				Me.db.global.indicator = val;
				if Me.connected and val then
					Me.indicator:Show()
				else
					Me.indicator:Hide()
				end
			end;
			get = function( info ) return Me.db.global.indicator end;
		};
		
		colors = {
			type = "group";
			name = L.OPTION_CHAT_COLORS;
			inline = true;
			args = {
				rp1 = ChatColorOption( "rp1", L.RP_CHANNEL, L.RP_CHANNEL_1_TOOLTIP );
				rpw = ChatColorOption( "rpw", L.RP_WARNING, L.RP_WARNING_TOOLTIP );
				rp2 = ChatColorOption( "rp2", L("RP_CHANNEL_X", "2"), L.RP_CHANNEL_X_TOOLTIP );
				rp3 = ChatColorOption( "rp3", L("RP_CHANNEL_X", "3"), L.RP_CHANNEL_X_TOOLTIP );
				rp4 = ChatColorOption( "rp4", L("RP_CHANNEL_X", "4"), L.RP_CHANNEL_X_TOOLTIP );
				rp5 = ChatColorOption( "rp5", L("RP_CHANNEL_X", "5"), L.RP_CHANNEL_X_TOOLTIP );
				rp6 = ChatColorOption( "rp6", L("RP_CHANNEL_X", "6"), L.RP_CHANNEL_X_TOOLTIP );
				rp7 = ChatColorOption( "rp7", L("RP_CHANNEL_X", "7"), L.RP_CHANNEL_X_TOOLTIP );
				rp8 = ChatColorOption( "rp8", L("RP_CHANNEL_X", "8"), L.RP_CHANNEL_X_TOOLTIP );
				rp9 = ChatColorOption( "rp9", L("RP_CHANNEL_X", "9"), L.RP_CHANNEL_X_TOOLTIP );
			};
		};
	}
}

-------------------------------------------------------------------------------
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
function Me.ApplyOptions()
	Me.ApplyColorOptions()
	if Me.db.global.minimapbutton.hide then
		DBIcon:Hide( "CrossRP" )
	else
		DBIcon:Show( "CrossRP" )
	end
	
	Me.UpdateChatTypeHashes()
end

-------------------------------------------------------------------------------
function Me.CreateDB()
	Me.db = LibStub( "AceDB-3.0" ):New( "CrossRP_Saved", 
	                                       DB_DEFAULTS, true )
	AceConfig:RegisterOptionsTable( "CrossRP", OPTIONS_TABLE )
	AceConfigDialog:AddToBlizOptions( "CrossRP", L.CROSS_RP )
end

local first = true
-------------------------------------------------------------------------------
function Me.OpenOptions()
	if first then
		InterfaceOptionsFrame_OpenToCategory( "Cross RP" )
		first = false
	end
	InterfaceOptionsFrame_OpenToCategory( "Cross RP" )
end
