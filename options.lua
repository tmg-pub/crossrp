
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
		color_rp = Hexc "BAE4E5";
		color_rpw = Hexc "EA3556";
	};
}

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
				};
			};
		};
	}
}

-------------------------------------------------------------------------------
function Me.ApplyColorOptions()
	ChatTypeInfo["RP"].r  = Me.db.global.color_rp[1]
	ChatTypeInfo["RP"].g  = Me.db.global.color_rp[2]
	ChatTypeInfo["RP"].b  = Me.db.global.color_rp[3]
	ChatTypeInfo["RPW"].r = Me.db.global.color_rpw[1]
	ChatTypeInfo["RPW"].g = Me.db.global.color_rpw[2]
	ChatTypeInfo["RPW"].b = Me.db.global.color_rpw[3]
end

function Me.ApplyOptions()
	Me.ApplyColorOptions()
	if Me.db.global.minimapbutton.hide then
		DBIcon:Hide( "RPLink" )
	else
		DBIcon:Show( "RPLink" )
	end	
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