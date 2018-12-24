-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- RP chat and group linking.
-------------------------------------------------------------------------------
local _, Me = ...
local L = Me.Locale

local CHAT_BUFFER_TIMEOUT = 5.0

-------------------------------------------------------------------------------
local RPChat = {
	enabled      = false;
	password     = "";
	group_leader = false;
	leader_name  = nil;
	next_serial  = 1;
	
	serials     = {};
	buffer      = {};
	filters     = {};
}
Me.RPChat = RPChat

-------------------------------------------------------------------------------
function RPChat.Init()
	for i = 1, 9 do
		Me.Proto.SetMessageHandler( "RP" .. i, RPChat.OnRPxMessage )
	end
	Me.Proto.SetMessageHandler( "RPW", RPChat.OnRPxMessage )
	Me.Proto.SetMessageHandler( "RP-HI", RPChat.OnHiMessage )
	Me.Proto.SetMessageHandler( "RPROLL", RPChat.OnRollMessage )
	
	Me.Comm.SetMessageHandler( {"PARTY","WHISPER"}, "RP-START", RPChat.OnStartMessage )
	Me.Comm.SetMessageHandler( "PARTY", "RP-STOP", RPChat.OnStopMessage )
	Me.Comm.SetMessageHandler( {"PARTY","WHISPER"}, "RP-CHECK", RPChat.OnCheckMessage )
	Me.Comm.SetMessageHandler( "PARTY", "RP-FILTER", RPChat.OnFilterMessage )
	
	for k, v in pairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", 
	                    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	                    "CHAT_MSG_RAID_WARNING" }) do
		ChatFrame_AddMessageEventFilter( v, RPChat.PartyChatFilter )
	end
	
	RPChat.Init = nil
end

-------------------------------------------------------------------------------
-- called from proto start
function RPChat.OnProtoStart()
	if UnitInParty( "player" ) or true then -- debug bypasses! or true
		Me.DebugLog2( "RPChat - In Party" )
		if UnitIsGroupLeader( "player" ) or true then-- debug bypasses! or true
			-- broadcast password if we're logging in during grace period.
			local seconds_since_logout = time() - Me.db.char.logout_time
			local auto_enable = Me.db.char.rpchat_on and seconds_since_logout < 300
			
			-- debug
			auto_enable = true
			Me.db.char.rpchat_password = 'poopie'
			
			if auto_enable then
				RPChat.Start( Me.db.char.rpchat_password )
			end
		else
			-- get password from host
			RPChat.Check()
		end
	end
end

function RPChat.PostStatusInit()
	if Me.RPChat.enabled then
		Me.Proto.Send( "all", "RP-HI", true, "FAST" )
	end
end

-------------------------------------------------------------------------------
function RPChat.IsController( unit )
	if unit and unit:find('-') then unit = Ambiguate( unit, "all" ) end
	return UnitInParty( unit or "player" ) and UnitIsGroupLeader( unit or "player" )
end

-------------------------------------------------------------------------------
function RPChat.CanUse()
	return UnitInParty( "player" )
end

-------------------------------------------------------------------------------
function RPChat.GetPartyLeader()
	if not UnitInParty("player") then return end
	if IsInRaid( LE_PARTY_CATEGORY_HOME ) then
		return Me.GetFullName( "raid1" ), "raid1"
	else
		for i = 1,4 do
			local unit = "party" .. i
			if UnitIsGroupLeader( unit ) then
				return Me.GetFullName( unit ), unit
			end
		end
	end
end

-------------------------------------------------------------------------------
function RPChat.Start( password )
	if password == "" then return end
	if RPChat.enabled and RPChat.password == password then return end
	
	RPChat.enabled  = true
	RPChat.password = password
	Me.Proto.SetSecure( password )
	
	if RPChat.IsController() then
		Me.db.char.rpchat_on       = true
		Me.db.char.rpchat_password = password
		RPChat.SendStart()
	end
	
	if Me.Proto.post_status_init then
		Me.Proto.Send( "all", "RP-HI", true, "FAST" )
	end
	
	Me.Print( L.GROUP_LINKED )
end

-------------------------------------------------------------------------------
function RPChat.SendStart( username )
	local target = username or "P"
	if username then
		if UnitRealmRelationship( target ) == LE_REALM_RELATION_COALESCED then
			target = "P"
		end
	end
	Me.Comm.SendSMF( target, "RP-START %s", RPChat.password )
end

-------------------------------------------------------------------------------
function RPChat.Stop( suppress_link_notice )
	if RPChat.enabled and not suppress_link_notice then
		Me.Print( L.GROUP_UNLINKED )
	end
	RPChat.enabled       = false
	RPChat.password      = ""
	Me.db.char.rpchat_on = false
	
	if RPChat.IsController() then
		Me.Comm.SendSMF( "P", "RP-STOP" )
	end
end

-------------------------------------------------------------------------------
function RPChat.Check()
	local target, tunit = RPChat.GetPartyLeader()
	RPChat.leader_name = target
	if not target or target == Me.fullname then return end
	if UnitRealmRelationship( tunit ) == LE_REALM_RELATION_COALESCED then
		-- can't whisper raid leader
		target = "P"
	end
	Me.Comm.SendSMF( target, "RP-CHECK" )
end

-------------------------------------------------------------------------------
function RPChat.OnStartMessage( job, sender )
	if RPChat.IsController( sender ) and sender ~= Me.fullname then
		local password = job.text:match( "RP%-START (.+)" )
		Me.DebugLog2( "Got RP-START." )
		RPChat.Start( password )
	end
end

-------------------------------------------------------------------------------
function RPChat.OnStopMessage( job, sender )
	if RPChat.IsController( sender ) and sender ~= Me.fullname then
		RPChat.Stop()
	end
end

-------------------------------------------------------------------------------
function RPChat.OnCheckMessage( job, sender )
	if RPChat.enabled and RPChat.IsController() and UnitInParty(Ambiguate(sender,"all")) then
		RPChat.SendStart( sender )
	end
end

-------------------------------------------------------------------------------
function RPChat.OnFilterMessage( job, sender )
	RPChat.filters[sender] = true
end

function RPChat.OnHiMessage( source, message, complete )
	if not complete then return end
	Me.DebugLog2( source, message, complete )
	local fullname = Me.Proto.DestToFullname( source )
	if Me.fullname ~= fullname and not UnitInParty(Ambiguate( fullname, "all" )) then
		Me.Print( L( "USER_CONNECTED_TO_YOUR_GROUP", fullname ))
	end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

function RPChat.OnGroupJoin()
	if UnitIsGroupLeader("player") then return end
	RPChat.Check()
end

-------------------------------------------------------------------------------
function RPChat.OnGroupLeave()
	RPChat.Stop( true )
end

-------------------------------------------------------------------------------
function RPChat.OnGroupRosterUpdate()
	--local target = Me.GetFullName( "raid1" )
	--if target ~= RPChat.leader_name then
	
end

-------------------------------------------------------------------------------
function RPChat.OnHi( source, message, complete )
	Me.DebugLog2( "On RP HI", source, message )
end

-------------------------------------------------------------------------------
function RPChat.OutputMessage( rptype, text, name )
	if rptype == "ROLL" then
		-- special case!
		local roll, rmin, rmax = strsplit( ":", text )
		name = Ambiguate( name, "all" )
		Me.Rolls.SimulateChat( name, roll, rmin, rmax )
		return
	end
	
	-- otherwise this is a normal chat message, and we need to cut it up.
	local chunks = LibGopher.Internal.SplitMessage( text, 400 )
	for i = 1, #chunks do
		Me.SimulateChatMessage( rptype, chunks[i], name )
	end
end

-------------------------------------------------------------------------------
function RPChat.ProcessBuffer( fullname )
	local player_serial = RPChat.serials[fullname] or 0
	local lowest_entry
	local lowest_entry_key
	for k, v in pairs( RPChat.buffer ) do
		if v.name == fullname then
			if not lowest_entry or v.serial < lowest_entry.serial then
				lowest_entry = v
				lowest_entry_key = k
			end
		end
	end
	if not lowest_entry then
		return
	end
	
	if lowest_entry.serial == player_serial+1 or GetTime() > lowest_entry.time + CHAT_BUFFER_TIMEOUT then
		-- this is their next message
		RPChat.serials[fullname] = lowest_entry.serial
		table.remove( RPChat.buffer, lowest_entry_key )
		RPChat.OutputMessage( lowest_entry.rptype, lowest_entry.text, lowest_entry.name )
		return RPChat.ProcessBuffer( fullname )
	else
		-- start a timer to process it at a later time
		Me.Timer_Start( "rpchat_process_" .. fullname, "ignore", 1.0, RPChat.ProcessBuffer, fullname )
	end
end

function RPChat.QueueMessage( fullname, rptype, text, serial )
	RPChat.buffer[#RPChat.buffer+1] = {
		name   = fullname;
		rptype = rptype;
		text   = text;
		serial = serial;
		time   = GetTime();
	}
	RPChat.ProcessBuffer( fullname )
end

-------------------------------------------------------------------------------
function RPChat.OnRPxMessage( source, message, complete )
	Me.DebugLog2( "onrpxmessage", source, message, complete )
	if not complete then return end
	local rptype, continent, chat_x, chat_y, serial, text = message:match( "(RP[1-9W]) (%S+) (%S+) (%S+) (%x+) (.+)" )
	if not rptype then return end
	serial = tonumber( "0x" .. serial )
	continent, chat_x, chat_y = Me.ParseLocationArgs( continent, chat_x, chat_y )
	
	local username = Me.Proto.DestToFullname( source )
	
	RPChat.QueueMessage( username, rptype, text, serial )
	--Me.SimulateChatMessage( rptype, text, username )
	Me.Map_SetPlayer( username, continent, chat_x, chat_y, source:sub( #source ) )
	
	if rptype == "RPW" then
		text = ChatFrame_ReplaceIconAndGroupExpressions( text )
		RaidNotice_AddMessage( RaidWarningFrame, text, ChatTypeInfo["RPW"] )
		PlaySound( SOUNDKIT.RAID_WARNING )
	end
end

function RPChat.OnRollMessage( source, message, complete )
	Me.DebugLog2( "onrprollmessage", source, message, complete )
	if not complete then return end
	local username = Me.Proto.DestToFullname( source )
	if username == Me.fullname then return end
	
	local continent, chat_x, chat_y, serial, roll, rmin, rmax = message:match( "(%S+) (%S+) (%S+) (%x+) (%d+) (%d+) (%d+)" )
	if not serial then return end
	serial = tonumber( "0x" .. serial )
	--roll, rmin, rmax = tonumber(roll), tonumber(rmin), tonumber(rmax)
	continent, chat_x, chat_y = Me.ParseLocationArgs( continent, chat_x, chat_y )
	
	-- can do range filtering here if we add "world rolls"
	
	RPChat.QueueMessage( username, "ROLL", roll .. ":" .. rmin .. ":" .. rmax, serial )
end

-------------------------------------------------------------------------------
function RPChat.PartyChatFilter( _, _, msg, sender, _,_,_,_,_,_,_,_, lineid )
	if RPChat.filters[sender] == true then
		RPChat.filters[sender] = lineid
	end
	
	if RPChat.filters[sender] == lineid then
		return true
	end
end

-------------------------------------------------------------------------------
function RPChat.MetadataForPartyCopy()
	Me.Comm.SendSMF( "P", "RP-FILTER" )
	return 15
end

-------------------------------------------------------------------------------
function RPChat.OnGopherNew( rptype, msg, arg3, target )
	if not RPChat.enabled then
		Me.Print( L.NOT_IN_LINKED_GROUP )
		return
	end
	
	if rptype == "RPW" then
		local cansend = UnitIsGroupLeader( "player" ) or UnitIsGroupAssistant("player")
		if not cansend then
			Me.Print( L.CANT_POST_RPW2 )
			return
		end
	end
	
	local y, x = UnitPosition( "player" )
	if not y then
		y = 0
		x = 0
	end
	--msg = Me.StripChatMessage( msg )
	--todo: we should strip some codes on the receiving side
	local mapid, px, py, serial = select( 8, GetInstanceInfo() ),
	       Me.PackCoord(x), Me.PackCoord(y), ("%x"):format( RPChat.next_serial )
	
	RPChat.next_serial = RPChat.next_serial + 1
	Me.Proto.Send( "all", { rptype, mapid, px, py, serial, msg }, true, "FAST" )
	
	if Me.db.global.copy_rpchat and UnitInParty("player") then
		local dist = IsInRaid( LE_PARTY_CATEGORY_HOME ) and "RAID" or "PARTY"
		LibGopher.AddMetadata( RPChat.MetadataForPartyCopy, dist, true )
		SendChatMessage( msg, dist )
	end
end

-- Todo: On group join (whisper leader, get reply)
-- Todo: On group leave (disconnect)
-- Todo: On reload (check for group, whisper leader, get reply)
-- for leader:
--   whisper new joiners
--   raid chat everyone upon setup/converting to raid
--   when group leaders change

function RPChat.OnLinkGroupAccept( password )
	if password == "" then return end
	
	if RPChat.IsController() then
		RPChat.Start( password )
	end
end

-------------------------------------------------------------------------------
StaticPopupDialogs["CROSSRP_LINK_GROUP"] = {
	text         = "Enter a password for your linked group. Groups using the same password will be linked.";
	button1      = OKAY;
	button2      = CANCEL;
	hasEditBox   = true;
	hideOnEscape = true;
	whileDead    = true;
	timeout      = 0;
	---------------------------------------------------------------------------
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end;
	---------------------------------------------------------------------------
	OnShow = function( self )
		self.editBox:SetText( Me.db.char.rpchat_password )
	end;
	---------------------------------------------------------------------------
	OnAccept = function( self )
		RPChat.OnLinkGroupAccept( self.editBox:GetText() )
	end;
	---------------------------------------------------------------------------
	EditBoxOnEnterPressed = function(self, data)
		RPChat.OnLinkGroupAccept( self:GetText() )
		self:GetParent():Hide()
	end;
}

-------------------------------------------------------------------------------
function RPChat.ShowStartPrompt()
	StaticPopup_Show( "CROSSRP_LINK_GROUP" )
end

function RPChat.SendRoll( roll, rmin, rmax )
	if not RPChat.enabled then return end
	
	local y, x = UnitPosition( "player" )
	if not y then
		x, y = 0, 0
	end
	local mapid, px, py, serial = select( 8, GetInstanceInfo() ),
	      Me.PackCoord(x), Me.PackCoord(y), ("%x"):format( RPChat.next_serial )
	RPChat.next_serial = RPChat.next_serial + 1
		   
	Me.Proto.Send( "all", { "RPROLL", mapid, px, py, serial, roll, rmin, rmax }, true, "FAST" )
end

-------------------------------------------------------------------------------
-- Custom chat stuff for game chatboxes.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Called after our chat settings change.
--
-- Chat Type hashes are what the chat system uses internally to see what sort 
--  of chat types exist. We can insert chat types into them, so that the chat
--  boxes will accommodate for our special/custom types ("/rp" etc.). We only
--  add entries that are enabled. If we aren't connected or if they're disabled
--  in the menu, we don't let the user type with them.
--[[function RPChat.UpdateChatTypeHashes()
	if Me.db.global.show_rpw and RPChat.enabled then
		hash_ChatTypeInfoList["/RPW"] = "RPW"
	else
		hash_ChatTypeInfoList["/RPW"] = nil
	end
	for i = 1, 9 do
		if Me.db.global["show_rp"..i] and RPChat.enabled then
			hash_ChatTypeInfoList["/RP"..i] = "RP"..i
			if i == 1 then
				hash_ChatTypeInfoList["/RP"] = "RP1"
			end
		else
			hash_ChatTypeInfoList["/RP"..i] = nil
			if i == 1 then
				hash_ChatTypeInfoList["/RP"] = nil
			end
		end
	end
	
	-- We also want to reset any chat boxes that are already using types that
	--  have just been disabled. It'll switch back even if you have it open
	--  typing in it.
	for i = 1, NUM_CHAT_WINDOWS do
		local editbox = _G["ChatFrame"..i.."EditBox"]
		local chat_type = editbox:GetAttribute( "chatType" )
		local show = Me.db.global["show_"..chat_type:lower()] 
		              and RPChat.enabled
					 
		if not show and chat_type:match( "^RP." ) then
			editbox:SetAttribute( "chatType", "SAY" )
			if editbox:IsShown() then
				ChatEdit_UpdateHeader(editbox)
			end
		end
	end
end]]

-------------------------------------------------------------------------------
-- Steps to insert your own chat type:
--  Insert data into ChatTypeInfo[type]
--    r,g,b = Color for this entry.
--    sticky = When the user chats with this, the next time they open the chat
--              box, it'll remain to that type, "sticky". If this isn't set,
--              then the chatbox is reset to /say after.
--  Insert your command for it into hash_ChatTypeInfoList.
--    e.g. hash_ChatTypeInfoList["/rp"] = "RP"
--  Set the global CHAT_<type>_SEND to what it shows in the editbox header.
--    e.g. CHAT_RPW_SEND = "RP Warning: "
--  Set the global CHAT_<type>_GET to what it shows when your message is
--   received and printed. %s is substituted with the player name.
--    e.g. CHAT_RPW_GET = "[RP Warning] %s: " - when the type RPW is seen
--     it prints in the chatbox like:
--       [RP Warning] Tammya: Hello!
--       [RP Warning] Tammya: Bye!
--  It doesn't work magically though, you need to intercept the outgoing
--   SendChatMessage calls (we use Gopher for it), and then cancel
--   the original ones, send the message over your special medium, and then
--   call the ChatFrame_MessageEventHandler manually for your type.
--   (See SimulateChatMessage in CrossRP.lua)
--
-- Basic setup for /rp1 ... /rp9
for i = 1, 9 do
	local key = "RP" .. i
	ChatTypeInfo[key]               = { r = 1, g = 1, b = 1, sticky = 1 }
	hash_ChatTypeInfoList["/"..key] = key
	_G["CHAT_"..key.."_SEND"]       = key..": "
	_G["CHAT_"..key.."_GET"]        = "["..key.."] %s: "
end

-- /rp1 is the same as /rp, and RP1 shows up as just "RP".
-- We also have /rpw for "RP Warning"
ChatTypeInfo["RPW"]           = { r = 1, g = 1, b = 1, sticky = 1 }
hash_ChatTypeInfoList["/RP"]  = "RP1"
hash_ChatTypeInfoList["/RPW"] = "RPW"
CHAT_RP1_SEND                 = "RP: "
CHAT_RP1_GET                  = "[RP] %s: "
CHAT_RPW_SEND                 = L.RP_WARNING .. ": "
CHAT_RPW_GET                  = "["..L.RP_WARNING.."] %s: "
