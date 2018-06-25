
local _, Me = ...

local AceConfig       = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local DBIcon       = LibStub:GetLibrary( "LibDBIcon-1.0"     )

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
		bubbles = true;
		color_rp1 = Hexc "BAE4E5";
		color_rpw = Hexc "EA3556";
		color_rp2 = Hexc "BAE4E5";
		color_rp3 = Hexc "BAE4E5";
		color_rp4 = Hexc "BAE4E5";
		color_rp5 = Hexc "BAE4E5";
		color_rp6 = Hexc "BAE4E5";
		color_rp7 = Hexc "BAE4E5";
		color_rp8 = Hexc "BAE4E5";
		color_rp9 = Hexc "BAE4E5";
		
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
	name = "RP Link";
	args = {
		desc = { 
			order = 10; 
			name = "Version: " .. GetAddOnMetadata( "RPLink", "Version" )
			       .. "|n" .. "by Tammya-MoonGuard";
			type = "description";
		};
		
		minimap_button = {
			order = 20;
			name = "Show Minimap Button";
			desc = "Show or hide the minimap button (if you're using something else like Titan Panel to access it).";
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
			name = "Translate Chat Bubbles";
			desc = "Try and translate chat bubbles alongside text.";
			width = "full";
			type = "toggle";
			set = function( info, val )
				Me.db.global.bubbles = val;
			end;
			get = function( info ) return Me.db.global.bubbles end;
		};
		
		colors = {
			type = "group";
			name = "Chat Colors";
			inline = true;
			args = {
				rp1 = ChatColorOption( "rp1", "RP Channel", "The main RP broadcast channel accessed with /rp." );
				rpw = ChatColorOption( "rpw", "RP Warning", "The RP warning broadcast channel accessed with /rpw." );
				rp2 = ChatColorOption( "rp2", "RP Channel 2", "RP Channel 2 - /rp2." );
				rp3 = ChatColorOption( "rp3", "RP Channel 3", "RP Channel 3 - /rp3." );
				rp4 = ChatColorOption( "rp4", "RP Channel 4", "RP Channel 4 - /rp4." );
				rp5 = ChatColorOption( "rp5", "RP Channel 5", "RP Channel 5 - /rp5." );
				rp6 = ChatColorOption( "rp6", "RP Channel 6", "RP Channel 6 - /rp6." );
				rp7 = ChatColorOption( "rp7", "RP Channel 7", "RP Channel 7 - /rp7." );
				rp8 = ChatColorOption( "rp8", "RP Channel 8", "RP Channel 8 - /rp8." );
				rp9 = ChatColorOption( "rp9", "RP Channel 9", "RP Channel 9 - /rp9." );
			--[[
				rp = {
					order = 10;
					name = "RP Channel";
					desc = "The RP broadcast channel accessed with /rp.";
					type = "color";
					width = "full";
					set = function( info, r, g, b )
						Me.db.global.color_rp = { r, g, b }
						Me.ApplyColorOptions()
					end;
					get = function( info )
						return Me.db.global.color_rp[1],  Me.db.global.color_rp[2], Me.db.global.color_rp[3]
					end;
				};
				rpw = {
					order = 20;
					name = "RP Warning Channel";
					desc = "The RP warning broadcast channel accessed with /rpw.";
					type = "color";
					width = "full";
					set = function( info, r, g, b )
						Me.db.global.color_rpw = { r, g, b }
						Me.ApplyColorOptions()
					end;
					get = function( info )
						return Me.db.global.color_rpw[1],  Me.db.global.color_rpw[2], Me.db.global.color_rpw[3]
					end;
				};]]
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
		DBIcon:Hide( "RPLink" )
	else
		DBIcon:Show( "RPLink" )
	end
	
	Me.UpdateChatTypeHashes()
end

-------------------------------------------------------------------------------
function Me.CreateDB()
	Me.db = LibStub( "AceDB-3.0" ):New( "RPLinkSaved", 
	                                       DB_DEFAULTS, true )
	AceConfig:RegisterOptionsTable( "RPLink", OPTIONS_TABLE )
	AceConfigDialog:AddToBlizOptions( "RPLink", "RP Link" )
end

-------------------------------------------------------------------------------
function Me.OpenOptions()
	InterfaceOptionsFrame_OpenToCategory( "RP Link" )
	InterfaceOptionsFrame_OpenToCategory( "RP Link" )
end