-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- The Alliance Protocol.
-------------------------------------------------------------------------------
local _, Main = ...

-- terminology:
--  band: set of people by faction and their realm
--  link: a link between two players over battlenet
--  bridge: an available player to carry data
--  toon: a player's character
--  local: your band
--  global: all active bands
local Me = {
	channel_name = "crossrp";
	
	-- bands that have been touched
	active_bands = {};
	
	-- links to bnet friends on other bands
	links   = {};
	hosting = false;
	
	-- list of bands we can access, indexed by band
	bridges = {};
	
	next_status_broadcast = 0;
	
	VERSION = 1;
}
Main.Protocol = Me

local START_DELAY = 1.0 -- should be something more like 10

-------------------------------------------------------------------------------
function Me.Init()
	Main.Timer_Start( "join_broadcast_channel", "push", START_DELAY, 
		                                          Me.JoinBroadcastChannel, 10 )
end

-------------------------------------------------------------------------------
-- try to join the broadcast channel
function Me.JoinBroadcastChannel( retries )
	if GetChannelName( "crossrp" ) == 0 then
		if retries <= 0 then
			print( "Couldn't join broadcast channel." )
			return
		end
		JoinTemporaryChannel( "crossrp" )
		Main.Timer_Start( "join_broadcast_channel", "push", 1.0, 
		                                 Me.JoinBroadcastChannel, retries - 1 )
	else
		-- move to bottom
		local crossrp_channel = GetChannelName( "crossrp" )
		for i = crossrp_channel+1, MAX_WOW_CHAT_CHANNELS do
			if GetChannelName(i) ~= 0 then
				C_ChatInfo.SwapChatChannelsByChannelIndex( i, i-1 )
			else
				break
			end
		end
		
		Me.Start()
	end
end

-------------------------------------------------------------------------------
function Me.Start()
	C_ChatInfo.RegisterAddonMessagePrefix( "+RP" )
	
	Me.OpenLinks()
	
	Me.Update()
end

function Me.Update()
	Main.Timer_Start( "protocol_update", "push", 1.0, Me.Update )
	
	if GetTime() > Me.next_status_broadcast then
		Me.next_status_broadcast = GetTime() + 120
		Me.BroadcastStatus()
	end
end

-------------------------------------------------------------------------------
function Me.GameAccounts( bnet_account_id )
	local account = 1
	local friend_index = BNGetFriendIndex( bnet_account_id )
	local num_accounts = BNGetNumFriendGameAccounts( friend_index )
	return function()
		while account <= num_accounts do
			local _, char_name, client, realm,_, faction, 
					_,_,_,_,_,_,_,_,_, game_account_id 
				       = BNGetFriendGameAccountInfo( friend_index, account )
			account = account + 1
			
			if client == BNET_CLIENT_WOW then
				realm = realm:gsub( "%s*%-*", "" )
				return char_name .. "-" .. realm, faction, game_account_id
			end
		end
	end
end

-------------------------------------------------------------------------------
function Me.FriendsGameAccounts()
	
	local friend = 1
	local friends_online = select( 2, BNGetNumFriends() )
	local account_iterator = nil
		
	return function()
		while friend <= friends_online do
			if not account_iterator then
				local id, _,_,_,_,_,_, is_online = BNGetFriendInfo( friend )
				if is_online then
					account_iterator = Me.GameAccounts( id )
				end
			end
			
			if account_iterator then
				local name, faction, id = account_iterator()
				if not name then
					account_iterator = nil
					friend = friend + 1
				else
					return name, faction, id
				end
			else
				friend = friend + 1
			end
		end
	end
end

-------------------------------------------------------------------------------
function Me.OpenLinks()
	if Me.hosting then return end
	
	if BNGetNumFriends() == 0 then
		-- Battle.net is bugged during this session.
		return
	end
	
	local my_faction = UnitFactionGroup( "player" )
	
	Me.hosting = true
	--Me.next_status_broadcast = GetTime() + 5
	Me.next_status_broadcast = GetTime() + 1 -- debug bypass
	
	for charname, faction, game_account in Me.FriendsGameAccounts() do
		
		local realm = charname:match( "%-(.+)" )
		if realm ~= Main.realm or faction ~= my_faction then
			Me.SendBnetMessage( game_account, "HI" )
		end
	end
end

-------------------------------------------------------------------------------
function Me.CloseLinks()
	if not Me.hosting then return end
	Me.hosting = false
	Me.Send( "local", "ST -" )
	
	for k, v in pairs( Me.links ) do
		Me.SendBnetMessage( v.gameid, "BYE" )
	end
	wipe( Me.links )
end

-------------------------------------------------------------------------------
function Me.BroadcastStatus()
	if not Me.hosting then return end
	local bands = {}
	local deststring = ""
	for band, set in pairs( Me.links ) do
		local avg = set:GetLoadAverage()
		if avg then
			deststring = deststring .. " " .. band .. avg
		end
	end
	
	-- ST <band list>
	Me.Send( "local", "ST" .. deststring )
end

-------------------------------------------------------------------------------
function Me.Send( destination, message )
	if destination == "all" then
		-- todo
		return
	elseif destination == "active" then
		-- todo
		return
	elseif destination == "local" then
		-- add header
		Me.SendAddonMessage( "*", message )
		return
	end
	
	-- find a bridge
	local dest_band = destination:match( "%d[AH]$" )
	if not dest_band then
		error( "Invalid Band." )
	end
	
	local bridge = Me.SelectBridge( dest_band )
	if not bridge then
		-- No available route.
		return
	end
	
	-- todo, bypass this for self (but it should work both ways)
	-- VV R1 F DEST MESSAGE
	Me.SendAddonMessage( bridge, "R1", Main.faction, destination, message )
end

-------------------------------------------------------------------------------
function Me.SelectBridge( band )
	local bridge = Me.bridges[band]
	if not bridge then return end
	
	return bridge:Select()
end

-------------------------------------------------------------------------------
function Me.SendBnetMessage( gameid, ... )
	local data = table.concat( {...}, " " )
	Main.Comm.SendBnetPacket( gameid, nil, true, data )
end

-------------------------------------------------------------------------------
function Me.SendAddonMessage( target, ... )
	local data = table.concat( {...}, " " )
	Main.Comm.SendAddonPacket( target, nil, true, data )
end

-------------------------------------------------------------------------------
function Me.FindLinkByGameAccount( gameid )
	for k, v in pairs( Me.links ) do
		if v.gameid == gameid then
			return v, k
		end
	end
end

-------------------------------------------------------------------------------
function Me.AddLink( gameid, load )
	load = load or 99
	local _, charname, _, realm, _, faction = BNGetGameAccountInfo( gameid )
	Main.DebugLog2( "Adding link.", charname, realm, gameid )
	realm = realm:gsub( "%s*%-*", "" )
	charname = charname .. "-" .. realm
	local band = Main.GetBandFromRealmFaction( realm, faction )
	if band == Me.band then return end -- Same band as us.
	
	if not Me.links[band] then
		Me.links[band] = Main.NodeSet.Create()
	end
	
	Me.links[band]:Add( gameid, load )
end

-------------------------------------------------------------------------------
function Me.RemoveLink( gameid )
	for k, v in pairs( Me.links ) do
		v:Remove( gameid )
	end
end

-------------------------------------------------------------------------------
function Me.UpdateBridge( sender, bands )
	local loads = {}
	local erasing = true
	for band, load in bands:gmatch( "(%d+[AH])([0-9]+)" ) do
		load = tonumber(load)
		
		if load < 1 or load > 99 then
			-- invalid input. cancel this user.
			loads = {}
			break
		end
		
		loads[band] = tonumber(load)
		erasing = false
	end
	
	-- create any nonexistant bridges.
	for band, load in pairs( loads ) do
		if not Me.bridges[band] then
			Me.bridges[band] = Main.NodeSet.Create()
		end
	end
	
	for band, bridge in pairs( Me.bridges ) do
		local load = loads[band]
		if load then
			bridge:Add( sender, load )
		else
			bridge:Remove( sender )
		end
	end
end

-------------------------------------------------------------------------------
Me.BroadcastPacketHandlers = {
	ST = function( job, sender )
		-- register or update a bridge.
		
		Me.UpdateBridge( sender, job.text:sub(3) )
	end;
}

-------------------------------------------------------------------------------
Me.BnetPacketHandlers = {
	HI = function( job, sender )
		if not job.complete then return end
		
		if not Me.hosting then return false end
		Me.AddLink( sender )
		-- reply
		
		local load = math.max( #Me.links, 1 )
		load = math.min( load, 99 )
		Me.SendBnetMessage( sender, "HO", load )
	end;
	
	HO = function( job, sender )
		if not job.complete then return end
		
		if not Me.hosting then return false end
		local load = job.text:match( "^HO ([0-9]+)" )
		if not load then return false end
		load = tonumber(load)
		if load < 1 or load > 99 then return false end
		Me.AddLink( sender, load )
	end;
	
	BYE = function( job, sender )
		if not job.complete then return end
		Me.RemoveLink( sender )
	end;
	
	R2 = function( job, sender )
		
		if not job.forwarder then
			local source, dest, message_data = job.text:match( "^R2 ([A-Za-z]+%d+[AH]) ([A-Za-z]*%d+[AH]) (.+)" )
			if not dest then return false end
			local send_to = Main.DestinationToFullname( dest )
		
			job.forwarder = Main.Comm.SendAddonPacket( send_to )
			job.forwarder:AddText( job.complete, "R3 " .. source .. " " .. message_data )
			job.text = ""
		else
			job.forwarder:AddText( job.complete, job.text )
			job.text = ""
		end
	end;
}

-------------------------------------------------------------------------------
Me.WhisperPacketHandlers = {
	R1 = function( job, sender )
		if not job.forwarder then
			local faction, dest_name, dest_band, message_data = job.text:match( "^R1 ([AH]) ([A-Za-z]*)(%d+[AH]) (.+)" )
			if not dest_band then
				Main.DebugLog( "Bad R1 message." )
				return false
			end
				
			local link = Me.links[dest_band]
			if not link then
				-- No link.
				-- in the future we might reply to the user to remove us as a bridge?
				return false
			end
			
			link = link:Select()
			if not link then
				-- No link available.
				return false
			end
			
			job.forwarder = Main.Comm.SendBnetPacket( link )
			local source = Main.FullnameToDestination( sender, faction )
			job.forwarder:AddText( job.complete, "R2 " .. source .. " " .. dest_name..dest_band .. " " .. message_data )
			job.text = ""
		else
			job.forwarder:AddText( job.complete, job.text )
			job.text = ""
		end
	end;
	
	R3 = function( job, sender )
		if not job.complete then return end
		
		local source, message = job.text:match( "^R3 ([A-Za-z]+%d+[AH]) (.+)" )
		if not source then return false end
		
		Main.DebugLog2( "GOT MESSAGE!", source, message )
	end;
}
--[[
-------------------------------------------------------------------------------
function Me.OnBnChatMsgAddon( event, prefix, message, _, sender )
	if prefix ~= "+RP" then return end
	Main.DebugLog2( "BNMSG:", message, sender )
	
	local version, command, rest = message:match( "([0-9]+) (%S+)%s*(.*)" )
	if not version or tonumber(version) ~= Me.VERSION then
		Main.DebugLog( "Invalid BNET message from " .. sender )
		return
	end
	
	local handler = Me.BnetPacketHandlers[command]
	if handler then handler( command, rest, sender ) end
end]]
--[[
-------------------------------------------------------------------------------
function Me.OnChatMsgAddon( event, prefix, message, dist, sender )
	if prefix ~= "+RP" then return end
	Main.DebugLog2( "ADDONMSG:", message, dist, sender )
	
	local version, command, rest = message:match( "([0-9]+) (%S+)%s*(.*)" )
	if not version or tonumber(version) ~= Me.VERSION then
		Main.DebugLog( "Invalid ADDON message from " .. sender )
		return
	end
	
	if dist == "CHANNEL" then
		local handler = Me.BroadcastPacketHandlers[command]
		if handler then
			handler( command, message, sender )
		end
	elseif dist == "WHISPER" then
		local handler = Me.WhisperPacketHandlers[command]
		if handler then
			handler( command, message, sender )
		end
	end
end]]


-- todo: on logout, let everyone know.

function Me.TouchUnitBand( unit )
	local band = Main.BandFromUnit( unit )
	if band ~= Main.band then
		Me.active_bands[band] = GetTime()
	end
end

-------------------------------------------------------------------------------
-- hooks
function Me.OnMouseoverUnit()
	Me.TouchUnitBand( "mouseover" )
end

function Me.OnTargetUnit()
	Me.TouchUnitBand( "target" )
end

function Me.Test()
	--Me.BnetPacketHandlers.HO( "HO", "1", 1443 )
	Me.Send( "Bradice1H", "Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky. Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky.Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky. Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky.Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky. Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky.Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky. Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky.Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky. Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky.Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky. Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky.Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky. Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky.Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky. Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky." )
	--Main.Comm.SendAddonPacket( "Tammya-MoonGuard", nil, true, "Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky. Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky." )
	--Main.Comm.SendAddonPacket( "Tammya-MoonGuard", nil, true, "Shankle pig pork loin, ham salami landjaeger sirloin rump turducken. Beef ribs pork belly ground round, filet mignon pork kielbasa boudin corned beef picanha kevin. Tail ribeye swine venison. Short ribs leberkas flank, jerky ribeye drumstick cow sirloin sausage.Shankle pig pork loin, ham salami landjaeger sirloin rump turducken. Beef ribs pork belly ground round, filet mignon pork kielbasa boudin corned beef picanha kevin. Tail ribeye swine venison. Short ribs leberkas flank, jerky ribeye drumstick cow sirloin sausage." )
	--Main.Comm.SendAddonPacket( "Tammya-MoonGuard", nil, true, "Jerky tail cow jowl burgdoggen, short loin kevin sirloin porchetta. Meatloaf strip steak salami cupim leberkas, andouille hamburger landjaeger tongue swine beef filet mignon meatball. Chuck pork belly tenderloin strip steak sausage flank, pork turducken jowl tri-tip. Jerky tail cow jowl burgdoggen, short loin kevin sirloin porchetta. Meatloaf strip steak salami cupim leberkas, andouille hamburger landjaeger tongue swine beef filet mignon meatball. Chuck pork belly tenderloin strip steak sausage flank, pork turducken jowl tri-tip. " )
	--Main.Comm.SendAddonPacket( "Tammya-MoonGuard", nil, true, "Pork loin chicken cow sirloin, ham pancetta andouille. Fatback biltong jerky ground round turducken. Pancetta jowl capicola picanha spare ribs shankle bresaola.Pork loin chicken cow sirloin, ham pancetta andouille. Fatback biltong jerky ground round turducken. Pancetta jowl capicola picanha spare ribs shankle bresaola." )
end

-------------------------------------------------------------------------------
function Me.OnDataReceived( job, dist, sender )
	if job.proto_abort then return end
	Main.DebugLog2( "DATA RECEIVED", job.type, job.complete and "COMPLETE" or "PROGRESS", sender, job.text )
	
	if job.firstpage then
		local command = job.text:match( "^(%S+)" )
		if not command then
			job.proto_abort = true
			return
		end
		job.command = command
	end
	
	local handler_result
	if job.type == "BNET" then
		local handler = Me.BnetPacketHandlers[ job.command ]
		if handler then handler_result = handler( job, sender ) end
	elseif job.type == "ADDON" then
		if dist == "CHANNEL" then
			local handler = Me.BroadcastPacketHandlers[ job.command ]
			if handler then handler_result = handler( job, sender ) end
		elseif dist == "WHISPER" then
			local handler = Me.WhisperPacketHandlers[ job.command ]
			if handler then handler_result = handler( job, sender ) end
		end
	end
	
	if handler_result == false then
		job.proto_abort = true
	end
end
