-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2019)
--
-- RP chat and group linking.
-------------------------------------------------------------------------------
local _, Me = ...
local L = Me.Locale
local DBchar
-------------------------------------------------------------------------------
-- Timing is very unpredictable when using routed messages. We want to try and
--  keep RP chat messages in order though. Each chat message has a serial
--  attached to it. If we get a serial that we aren't expecting (like, if it's
--  +2 instead of +1 from the last serial we got from them) then we will delay
--  this long to try and see if another serial will pop up. If it doesn't, then
--  we re-sync, setting our last known serial to the lowest in our queue, and
--  flush it. 5.0 seconds is a long time to buffer something, but it might
--  honestly not be enough in some cases, especially if a player has to resend
--  their message after a failure.
-- Another safety thing we have in place is that the user doesn't send multiple
--  messages at once. They're buffer locally and then sent and verified one
--  at a time.
local CHAT_BUFFER_TIMEOUT = 5.0

-------------------------------------------------------------------------------
-- RP Chat module.
local RPChat = {
	---------------------------------------------------------------------------
	-- True if we are currently in a linked group.
	enabled = false;
	---------------------------------------------------------------------------
	-- The password our linked group is using. All groups must share the same
	--  password to communicate with each other (it controls which secure
	--  Proto channel is being used).
	-- We also store a password in `db.char.rpchat_password`. The password in
	--  the db never gets overwritten automatically though. The password in
	--  here is temporary, and the one in the db is meant to be only for when
	--  the user types the password in manually, and then it's saved as a sort
	--  of preference.
	password = "";
	---------------------------------------------------------------------------
	-- This is the name of the leader that we last probed with a Check.
	--  Currently not used.
	leader_name = nil;
	---------------------------------------------------------------------------
	-- The next serial that we will attach to our outgoing chat message (see
	--  above giant wall of text).
	next_serial = 1;
	---------------------------------------------------------------------------
	-- Our queue of messages waiting to be sent. Only one is sent at a time,
	--  waiting for "CONFIRMED" from the Proto side for each one.
	outqueue = {};
	---------------------------------------------------------------------------
	-- True if we are currently sending a message, and we can't run the queue
	--  again.
	sending = false;
	
	---------------------------------------------------------------------------
	-- This is the last known serial we have from someone, and we expect their
	--  next one to be this + 1. If it isn't then we wait for
	--  CHAT_BUFFER_TIMEOUT seconds before resyncing.
	serials = {};
	
	---------------------------------------------------------------------------
	-- These are buffered messages we have waiting to be printed. Each entry
	--  contains:
	--    name    Source's fullname.
	--    rptype  The type of the RP chat messages, RPx/RPROLL.
	--    text    The text for the message.
	--    serial  The serial attached with the message.
	--    time    The time this message was received.
	-- Table entries are stored in keys, like an unordered linked list.
	-- Values are ignored.
	buffer = {};
	
	---------------------------------------------------------------------------
	-- Used for filtering messages when receiving an RPFILTER command. We
	--  mirror RP chat messages to raid chat for non-Cross RP users, and we
	--  filter these duplicates out client-side (see the chat filter).
	filters = {};
}                                                            Me.RPChat = RPChat

-------------------------------------------------------------------------------
-- Called from main OnEnabled.
function RPChat.Init()
	DBchar = Me.db.char
	
	-- Register our message handlers. Proto handlers are routed messages, such
	--  as our chat commands, rolls, and login command.
	for i = 1, 9 do
		Me.Proto.SetMessageHandler( "RP" .. i, RPChat.OnRPxMessage )
	end
	
	Me.Proto.SetMessageHandler( "RPW",    RPChat.OnRPxMessage  )
	Me.Proto.SetMessageHandler( "RPROLL", RPChat.OnRollMessage )
	-- Sent when a player connects to the linked group. We intentionally don't
	--  have a RPBYE command for when a player disconnects, because there isn't
	--  actually a reliable way to make sure that a player has disconnected or
	--  isn't listening in to the conversation anymore, and we don't want to
	--  give a false sense of privacy or security.
	-- In other words, once a player has your password (has connected to your
	--  group), always assume that they can listen to what you're saying with
	--  the /rp commands if you're using the same password, no matter their
	--  status (they could even be on an alt listening!).
	Me.Proto.SetMessageHandler( "RPHI",   RPChat.OnHiMessage )
	
	-- Lower level local commands.
	local smh = Me.Comm.SetMessageHandler -- smh
	smh( {"PARTY","WHISPER"}, "RPSTART",  RPChat.OnStartMessage  )       
	smh( "PARTY",             "RPSTOP",   RPChat.OnStopMessage   )
	smh( {"PARTY","WHISPER"}, "RPCHECK",  RPChat.OnCheckMessage  )  
	smh( "PARTY",             "RPFILTER", RPChat.OnFilterMessage )
	
	-- Our chat filter is for our mirrored raid/party messages when sending
	--  /rp chat. Whenever we send one of those, they're trailed by an addon
	--           message (LibGopher Metadata) that lets us know to filter them.
	for k, v in pairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", 
	                    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	                    "CHAT_MSG_RAID_WARNING" }) do
		ChatFrame_AddMessageEventFilter( v, RPChat.PartyChatFilter )
	end
	
	RPChat.Init = nil
end

-------------------------------------------------------------------------------
-- Called from CROSSRP_PROTO_START message - when the Proto module starts up.
function RPChat.OnProtoStart()
	if UnitInParty( "player" ) then
		Me.DebugLog2( "RPChat - In Party" )
		if UnitIsGroupLeader( "player" ) then
			-- Broadcast password if we're logging in during grace period.
			local seconds_since_logout = time() - DBchar.logout_time
			local auto_enable = DBchar.rpchat_on and seconds_since_logout < 300
			
			-- debug
			--auto_enable = true
			--DBchar.rpchat_password = 'poopie'
			
			if auto_enable then
				RPChat.Start( DBchar.rpchat_password )
			end
		else
			-- Get password from host. We only have a short amount of time
			--  during Proto's phase1 initialization, and hopefully the host
			--  response before we sent out our initial status (3 seconds).
			RPChat.Check()
		end
	else
		-- Not in a group: reset this bit.
		DBchar.rpchat_on = false
		DBchar.rpchat_relay = true
	end
end

-------------------------------------------------------------------------------
-- Called from CROSSRP_PROTO_START3 message - when the Proto module is
--  completely initialized and ready to send routed messages.
function RPChat.OnProtoStart3()
	if RPChat.enabled then
		Me.Proto.Send( "all", "RPHI", { secure = true, priority = "FAST" } )
	end
end

-------------------------------------------------------------------------------
-- Returns true if we are the controller of a linked group (in a party, and
--  group leader).
function RPChat.IsController( unit )
	if unit and unit:find('-') then unit = Ambiguate( unit, "all" ) end
	return UnitInParty( unit or "player" ) and UnitIsGroupLeader( unit or "player" )
end

-------------------------------------------------------------------------------
-- Returns true if we are in an environment suitable for RP chat. (Maybe not
--  finished).
function RPChat.CanUse()
	return UnitInParty( "player" )
end

-------------------------------------------------------------------------------
-- Returns the fullname and unit of the raid or party leader. `nil` if not in a
--  party.
function RPChat.GetPartyLeader()
	if not UnitInParty("player") then return end
	if IsInRaid( LE_PARTY_CATEGORY_HOME ) then
		return Me.GetFullName( "raid1" ), "raid1"
	else
		-- Thought there might be an easier way to do this...
		for i = 1, 4 do
			local unit = "party" .. i
			if UnitIsGroupLeader( unit ) then
				return Me.GetFullName( unit ), unit
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Joins a linked group. `password` is the shared password. This is called when
--  a group leader enables it, or when the users receive the START command,
--  either from the startup, or when they request a CHECK from the leader when
--  joining the party or logging in.
function RPChat.Start( password )
	if password == "" then return end
	if RPChat.enabled and RPChat.password == password then
		-- State already up to date.
		return
	end
	
	RPChat.enabled  = true
	RPChat.password = password
	Me.Proto.SetSecure( password )
	
	if RPChat.IsController() then
		-- If we're the leader, send a start message to everyone, so they
		--  join the linked group too.
		DBchar.rpchat_on       = true
		DBchar.rpchat_password = password
		RPChat.SendStart()
	end
	
	-- This call can be made before the Proto module is initialized
	--  completely.
	if Me.Proto.startup_complete then
		Me.Proto.Send( "all", "RPHI", { secure = true, priority = "FAST" } )
	end
	
	Me.Print( L.GROUP_LINKED )
end

-------------------------------------------------------------------------------
-- Tell other users to join the linked group that we have created. They'll
--  ignore this message if we aren't their group leader. `username` can be a
--  fullname of who we want to tell, or `nil` to broadcast the message to
--  everyone in our raid or party.
function RPChat.SendStart( username )
	local target = username or "P"
	if username then
		-- If we can't contact the user because they're on a coalesced realm,
		--  then we just broadcast anyway (and our broadcast will be ignored by
		--  anyone already in our linked group).
		if UnitRealmRelationship( target ) == LE_REALM_RELATION_COALESCED then
			target = "P"
		end
	end
	Me.Comm.SendSMF( target, "RPSTART %s", RPChat.password )
end

-------------------------------------------------------------------------------
-- Disconnect from the linked group. `suppress_link_notice` is for when the
--  user leaves the party - it seems implied that they would be disconnected
--  from the linked group as well.
function RPChat.Stop( suppress_link_notice )
	if RPChat.enabled and not suppress_link_notice then
		Me.Print( L.GROUP_UNLINKED )
	end
	RPChat.enabled   = false
	RPChat.password  = ""
	DBchar.rpchat_on = false
	Me.Proto.SetSecure( false )
	
	if RPChat.IsController() then
		Me.Comm.SendSMF( "P", "RPSTOP" )
	end
end

-------------------------------------------------------------------------------
-- Sends a message to the group leader to ask if there is any linked group
--  currently. If there is, we'll get an RPSTART message back.
function RPChat.Check()
	local target, tunit = RPChat.GetPartyLeader()
	RPChat.leader_name = target
	if not target or target == Me.fullname then return end
	if UnitRealmRelationship( tunit ) == LE_REALM_RELATION_COALESCED then
		-- Can't whisper raid leader, so just to raid.
		target = "P"
	end
	Me.Comm.SendSMF( target, "RPCHECK" )
end

-------------------------------------------------------------------------------
-- Handler for RPSTART from the group leader.
function RPChat.OnStartMessage( job, sender )
	-- Ignore it if they're not the leader, or if this is our message.
	if RPChat.IsController( sender ) and sender ~= Me.fullname then
		-- Format: RPSTART <password>
		local password = job.text:match( "RPSTART (.+)" )
		Me.DebugLog2( "Got RPSTART." )
		RPChat.Start( password )
	end
end

-------------------------------------------------------------------------------
-- Handler for RPSTOP from the group leader, when they disconnect from the
--  linked group.
function RPChat.OnStopMessage( job, sender )
	-- Make sure they're the group leader, and that this isn't our message.
	if RPChat.IsController( sender ) and sender ~= Me.fullname then
		RPChat.Stop()
	end
end

-------------------------------------------------------------------------------
-- Handler for receiving RPCHECK from someone, which means they're asking for
--  an RPSTART message if we're in a linked group.
function RPChat.OnCheckMessage( job, sender )
	-- This message is only for the controller, and we might receive it anyway
	--  if they're using a cross-realm comm fallback by messaging the party.
	-- Also make sure that this is coming from someone in our party. We're
	--  sending them our password!
	if RPChat.enabled and RPChat.IsController()
	                            and UnitInParty( Ambiguate(sender,"all") ) then
		RPChat.SendStart( sender )
	end
end

-------------------------------------------------------------------------------
-- The RPFILTER message makes it so that we ignore the next raid or party
--  message from this user, meant for ignoring mirrored group chat when using
--  /rp.
function RPChat.OnFilterMessage( job, sender )
	RPChat.filters[sender] = true
end

-------------------------------------------------------------------------------
-- RPHI is when the user is broadcasting that they've joined the linked group.
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
-- Called when a player joins a group.
function RPChat.OnGroupJoin()
	if UnitIsGroupLeader("player") then return end
	-- If we aren't the group leader, send a RPCHECK to them.
	RPChat.Check()
end

-------------------------------------------------------------------------------
-- Called when a player leaves a group.
function RPChat.OnGroupLeave()
	-- Disconnect from the linked group. Don't print a notice.
	RPChat.Stop( true )
end

-------------------------------------------------------------------------------
-- Not using this anymore.
function RPChat.OnGroupRosterUpdate()
	--local target = Me.GetFullName( "raid1" )
	--if target ~= RPChat.leader_name then
	
end

-------------------------------------------------------------------------------
function RPChat.RelayRoll( name, roll, rmin, rmax )
	name = Ambiguate( name, "all" )
	
	local show = Me.db.char.rpchat_relay and RPChat.IsController()
	                        and UnitInParty("player") and not UnitInParty(name)
	if not show then return end
	
	local inraid = IsInRaid( LE_PARTY_CATEGORY_HOME )
	local dist = inraid and "RAID" or "PARTY"
	
	local text = L( "RELAY_RP_ROLL", name, roll, rmin, rmax )
	
	LibGopher.AddMetadata( RPChat.MetadataForPartyCopy, dist, true )
	SendChatMessage( text, dist )
end

-------------------------------------------------------------------------------
function RPChat.RelayChat( rptype, text, name )
	name = Ambiguate( name, "all" )
	
	local show = Me.db.char.rpchat_relay and RPChat.IsController()
	                        and UnitInParty("player") and not UnitInParty(name)
	if not show then return end
	
	local inraid = IsInRaid( LE_PARTY_CATEGORY_HOME )
	local dist = inraid and "RAID" or "PARTY"
	
--	if dist == "RAID" and rptype == "RPW" then
--		dist = "RAID_WARNING"
--	end
	
	
	LibGopher.AddMetadata( RPChat.MetadataForPartyCopy, dist, true )
	LibGopher.SetPadding( "[" .. name .. "] " )
	SendChatMessage( text, dist )
end

-------------------------------------------------------------------------------
-- Print one of our queued messages to the chatbox.
function RPChat.OutputMessage( rptype, text, name )
	if rptype == "RPROLL" then
		-- Special case for rolls.
		local roll, rmin, rmax = strsplit( ":", text )
		name = Ambiguate( name, "all" )
		Me.Rolls.SimulateChat( name, roll, rmin, rmax )
		RPChat.RelayRoll( name, roll, rmin, rmax )
		return
	end
   
	RPChat.RelayChat( rptype, text, name )
	local lines = LibGopher.Internal.SplitLines( text )

	for k, line in ipairs( lines ) do
		-- Otherwise this is a normal chat message, and we need to cut it up.
		-- Can't just flood the chatbox with a giant message.
		local chunks = LibGopher.Internal.SplitMessage( line, 400 )
		for i = 1, #chunks do
			local text = chunks[i]
			Me.SimulateChatMessage( rptype, text, name )
			if rptype == "RPW" then
				text = C_ChatInfo.ReplaceIconAndGroupExpressions( text )
				RaidNotice_AddMessage( RaidWarningFrame, text, ChatTypeInfo["RPW"] )
				PlaySound( SOUNDKIT.RAID_WARNING )
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Routine function for processing the buffered chat. This is a self running
--  function. You just call it for a name, and it will call itself periodically
--                                  until that name is no longer in the buffer.
function RPChat.ProcessBuffer( fullname )
	local player_serial = RPChat.serials[fullname] or 0
	local lowest_entry
	
	-- The chat buffer is a single table that's shared by all incoming
	--  messages, and we filter them by the name we have. We're looking for the
	--  message with the lowest serial to print.
	for v, _ in pairs( RPChat.buffer ) do
		if v.name == fullname then
			if not lowest_entry or v.serial < lowest_entry.serial then
				lowest_entry = v
			end
		end
	end
	if not lowest_entry then
		-- No more messages by this user in the buffer.
		return
	end
	
	-- If we aren't expecting this serial (not equal to the last + 1), then we
	--  delay a number of seconds to see if any other messages show up.
	-- Not sure if any of this is necessary anymore, as the clients no longer
	--  send more than one message at a time.
	if lowest_entry.serial == player_serial+1 
	                or GetTime() > lowest_entry.time + CHAT_BUFFER_TIMEOUT then
		if player_serial + 1 ~= lowest_entry.serial then
			Me.DebugLog2( "RPChat had to resync serial.", fullname )
		end
		-- This is their next message.
		RPChat.serials[fullname] = lowest_entry.serial
		RPChat.buffer[lowest_entry] = nil
		if lowest_entry.text then
			RPChat.OutputMessage( lowest_entry.rptype, lowest_entry.text,
			                                                lowest_entry.name )
		end
		
		-- Tail call.
		return RPChat.ProcessBuffer( fullname )
	else
		
		-- start a timer to process it at a later time
		Me.Timer_Start( "rpchat_process_" .. fullname, "ignore", 1.0,
		                                       RPChat.ProcessBuffer, fullname )
	end
end

-------------------------------------------------------------------------------
-- After receiving a message, we queue it in here before it gets printed.
--  Basically this is a system for receiving messages out-of-order, and it
--  orders them. This isn't actually -too- useful, because we already wait for
--  confirmation after sending each message before sending another one, so
--  everything is sent one at a time, but there's one other possibility of
--  messages still arriving out of order.
-- If in some crazy high-load situation a link is broadcasting too much data
--  to the channel, their messages will get backed up and delayed, but
--  meanwhile we'll get the Proto confirmation and send our next message--which
--  may go through another route and then arrive before the last one gets out 
--  of the server delay queue.
function RPChat.QueueMessage( fullname, rptype, text, serial )
	RPChat.buffer[{
		name   = fullname;
		rptype = rptype;
		text   = text;
		serial = serial;
		time   = GetTime();
	}] = true
	RPChat.ProcessBuffer( fullname )
end

-------------------------------------------------------------------------------
-- Handler for RP1-9 and RPW - RP chat messages.
function RPChat.OnRPxMessage( source, message, complete, secure )
	Me.DebugLog2( "onRPxMessage", source, message, complete )
	if not complete then return end -- Transfer still in progress.
	if not secure then
		-- These should only be over a secure channel. Otherwise is malicious
		--  intent.
		return
	end 
	local rptype, continent, chat_x, chat_y, serial, text =
	                message:match( "^(RP[1-9W]) (%S+) (%S+) (%S+) (%x+) (.+)" )
	if not rptype then return end
	serial = tonumber( serial, 16 )
	continent, chat_x, chat_y = Me.ParseLocationArgs( continent, chat_x, chat_y )
	
	local username = Me.Proto.DestToFullname( source )
	
	RPChat.QueueMessage( username, rptype, text, serial )
	
	-- Can't be letting our sweet map code go to waste... Basically what it's
	--  used for now is to let you see where people in your linked group are,
	--  so long as they are chatting in /rp.
	Me.Map_SetPlayer( username, continent, chat_x, chat_y, source:sub( #source ) )
end

-------------------------------------------------------------------------------
-- Handler for RPROLL, broadcasted when a user /rolls in a linked group.
function RPChat.OnRollMessage( source, message, complete, secure )
	Me.DebugLog2( "onRpRollMessage", source, message, complete )
	if not complete then return end
	if not secure then
		-- These should only be over a secure channel. Otherwise is malicious
		--  intent.
		return
	end 
	local username = Me.Proto.DestToFullname( source )
	
	local continent, chat_x, chat_y, serial, roll, rmin, rmax =
	       message:match( "^RPROLL (%S+) (%S+) (%S+) (%x+) (%d+) (%d+) (%d+)" )
	if not serial then return end
	serial = tonumber( serial, 16 )
	continent, chat_x, chat_y = Me.ParseLocationArgs( continent, chat_x, chat_y )
	
	-- Since we have location data, we can add a feature in the future for
	--  'world rolls', where any roll done near you shows up regardless of
	--  group.
	local msg = roll .. ":" .. rmin .. ":" .. rmax
	if username == Me.fullname or UnitInParty( Ambiguate(username,"all") ) then
		msg = nil
	end
	
	RPChat.QueueMessage( username, "RPROLL", msg, serial )
end

-------------------------------------------------------------------------------
-- Chat message filter for our mirrored group chat.
function RPChat.PartyChatFilter( _, _, msg, sender, _,_,_,_,_,_,_,_, lineid )
	-- Basically whenever we send an /rp message, we mirror it to party chat,
	--  but the mirrored message is always prefix by an addon message that
	--  tells us to filter it out.
	-- Optimally, we would capture the lineid in a CHAT_MSG event handler, but
	--  the chat frames have likely hooked it before us, so we gotta do it
	--  in here.
	if RPChat.filters[sender] == true then
		RPChat.filters[sender] = lineid
	end
	
	if RPChat.filters[sender] == lineid then
		return true
	end
end

-------------------------------------------------------------------------------
-- Metadata callback for LibGopher for when we're sending our mirroed message
--  to raid or party. LibGopher will call this just before it puts the other
--  message out on the line, so if we do an URGENT Comm message in here, it
--  will be coupled with it (addon messages and raid messages have guaranteed
--                                order and respect which call is made first).
function RPChat.MetadataForPartyCopy()
	Me.Comm.SendSMU( "P", "RPFILTER" )
	return 15
end

-------------------------------------------------------------------------------
-- Callback from Proto, sender status.
function RPChat.SendCallback( sender, status, data, data2 )
	Me.DebugLog2( "RPCHATSENDCALLBACK", sender, status, data, data2 )
	if status == "TIMEOUT" then
		-- TIMEOUT is a big failure, meaning the network is unstable, and we
		--  want to cancel any further messages.
		sender.rpchat_failed = true
		Me.PrintL( "RPCHAT_TIMED_OUT", data.dest )
	elseif status == "NOBRIDGE" then
		-- We lost a bridge and can't transfer our message to a destination,
		--  and we want to cancel any further messages.
		sender.rpchat_failed = true
		Me.PrintL( "RPCHAT_NOBRIDGE", data.dest )
	elseif status == "CONFIRMED" then
		-- TODO: this isn't called by Proto when we're only sending locally.
		sender.rpchat_success = true
	elseif status == "DONE" then
		
		if sender.rpchat_failed then
			wipe( RPChat.outqueue )
		end
		RPChat.sending = false
		RPChat.RunOutqueue()
	end
end

-------------------------------------------------------------------------------
-- Called to startup the sending process. It will send one message at a time
--  waiting for confirmation messages between each message sent.
function RPChat.RunOutqueue()
	if RPChat.sending then return end
	
	local q = RPChat.outqueue[1]
	if q then
		RPChat.sending = true
		table.remove( RPChat.outqueue, 1 )
		
		local y, x = UnitPosition( "player" )
		if not y then
			y = 0
			x = 0
		end
		
		-- TODO: We need to strip some UI escape sequences on the receiving
		--  side, like textures and stuff.
		local mapid, px, py, serial = select( 8, GetInstanceInfo() ),
			                             Me.PackCoord(x), Me.PackCoord(y), 
		                                    ("%x"):format( RPChat.next_serial )
		RPChat.next_serial = RPChat.next_serial + 1
		Me.Proto.Send( "all", { q.type, mapid, px, py, serial, q.message }, 
		     { secure = true, priority = "FAST", 
			   guarantee=true, callback=RPChat.SendCallback })
		
		if Me.db.global.copy_rpchat and UnitInParty("player")
		                                            and q.type ~= "RPROLL" then
			-- Mirroring this message to raid or party.
			local inraid = IsInRaid( LE_PARTY_CATEGORY_HOME )
			local dist = inraid and "RAID" or "PARTY"
			-- LibGopher will call this function for each chunk about to be
			--  sent, allowing us to tag each one with a FILTER message so that
			--  Cross RP clients can ignore them.
			LibGopher.AddMetadata( RPChat.MetadataForPartyCopy, dist, true )
			SendChatMessage( q.message, dist )
		end
	end
end

-------------------------------------------------------------------------------
-- Insert a message into the output queue and start the sending process.
function RPChat.QueueOutgoing( rptype, msg )
	table.insert( RPChat.outqueue, { type = rptype, message = msg } )
	RPChat.RunOutqueue()
end

-------------------------------------------------------------------------------
-- GopherNew is when Gopher hears a new chat message trying to be sent. It's
--  the first step in the system. We intercept any RP chat types in here, and
--  then cancel them in the normal chat queue and handle them ourselves.
-- This is actually a sub-fuction, and the parent function (CrossRP.lua) is
--  what detects the RP type, calls us, and then cancels the original chat
--  message.
function RPChat.OnGopherNew( rptype, msg, arg3, target )
	if not Me.Proto.startup_complete then
		-- We /could/ queue the message until we're initialized, but that's an
		--  extra pain in the butt.
		Me.Print( L.CROSSRP_NOT_DONE_INITIALIZING )
		return
	end
	
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
	
	RPChat.QueueOutgoing( rptype, msg )
end

-------------------------------------------------------------------------------
-- "OKAY" callback for the group linking dialog.
function RPChat.OnLinkGroupAccept( password )
	if password == "" then return end
	
	if RPChat.IsController() then
		RPChat.Start( password )
	end
end

-------------------------------------------------------------------------------
-- Popup for asking the user for a password to link the groups.
StaticPopupDialogs["CROSSRP_LINK_GROUP"] = {
	text         = L.LINK_GROUP_DIALOG; -- "Enter a password for your linked 
	button1      = OKAY;                --  group. Groups using the same 
	button2      = CANCEL;              --  password will be linked."
	hasEditBox   = true;
	hideOnEscape = true;
	whileDead    = true;
	timeout      = 0;
	---------------------------------------------------------------------------
	-- Kind of dumb that we need to add this function, even though hideOnEscape
	--  is set.
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end;
	---------------------------------------------------------------------------
	OnShow = function( self )
		self.editBox:SetText( DBchar.rpchat_password )
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
-- Show the popup asking for the group password, meant for the group leader
--  only when they press "link group" in the minimap menu.
function RPChat.ShowStartPrompt()
	StaticPopup_Show( "CROSSRP_LINK_GROUP" )
end

-------------------------------------------------------------------------------
-- Queue a roll message to broadcast (called from roll.lua after detecting a
--  player /roll).
function RPChat.SendRoll( roll, rmin, rmax )
	if not Me.Proto.startup_complete then
		return
	end
	
	if not RPChat.enabled then return end
	RPChat.QueueOutgoing( "RPROLL", roll .. " " .. rmin .. " " .. rmax )
end

-------------------------------------------------------------------------------
-- Custom chat stuff for game chatboxes.
-------------------------------------------------------------------------------
-- Turn an RP chat type on or off in a chatbox. `chatbox` is an index
--  corresponding to the game's chatboxes. `on` turns the RP chat type
--  specified on or off.
function RPChat.ShowChannel( rptype, chatbox, on )
	rptype = tostring( rptype )
	local settings = DBchar.rpchat_windows[chatbox] or ""
	if on and not settings:find( rptype ) then
		settings = settings .. rptype
	elseif not on and settings:find( rptype ) then
		settings = settings:gsub( rptype, "" )
	end
	DBchar.rpchat_windows[chatbox] = settings
end

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

-------------------------------------------------------------------------------
-- /rp1 is the same as /rp, and RP1 shows up as just "RP".
-- We also have /rpw for "RP Warning"
ChatTypeInfo["RPW"]           = { r = 1, g = 1, b = 1, sticky = 1 }
hash_ChatTypeInfoList["/RP"]  = "RP1"
hash_ChatTypeInfoList["/RPW"] = "RPW"
CHAT_RP1_SEND                 = "RP: "
CHAT_RP1_GET                  = "[RP] %s: "
CHAT_RPW_SEND                 = L.RP_WARNING .. ": "
CHAT_RPW_GET                  = "["..L.RP_WARNING.."] %s: "
