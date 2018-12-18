-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- The Alliance Protocol.
-------------------------------------------------------------------------------
local _, Me = ...

-- terminology:
--  band: set of people by faction and their realm
--  link: a link between two players over battlenet
--  bridge: an available player to carry data
--  toon: a player's character
--  local: your band
--  global: all active bands
local Proto = {
	channel_name = "crossrp";
	
	-- bands that have been touched
	active_bands = {};
	
	hosting = false;
	
	-- these are indexed by band
	links   = {};
	bridges = {};
	
	secure_links   = {};
	secure_bridges = {};
	secure_code    = nil;
	secure_channel = nil;
	secure_hash    = nil;
	
	next_status_broadcast = 0;
	
	VERSION = 1;
}
Me.Proto = Proto

local START_DELAY = 1.0 -- should be something more like 10

-------------------------------------------------------------------------------
function Proto.Init()
	Me.Timer_Start( "join_broadcast_channel", "push", START_DELAY, 
		                                          Proto.JoinBroadcastChannel, 10 )
end

-------------------------------------------------------------------------------
-- try to join the broadcast channel
function Proto.JoinBroadcastChannel( retries )
	if GetChannelName( "crossrp" ) == 0 then
		if retries <= 0 then
			print( "Couldn't join broadcast channel." )
			return
		end
		JoinTemporaryChannel( "crossrp" )
		Me.Timer_Start( "join_broadcast_channel", "push", 1.0, 
		                                 Proto.JoinBroadcastChannel, retries - 1 )
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
		
		Proto.Start()
	end
end

-------------------------------------------------------------------------------
function Proto.Start()
	C_ChatInfo.RegisterAddonMessagePrefix( "+RP" )
	
	Proto.StartHosting()
	
	Proto.Update()
end

function Proto.Update()
	Me.Timer_Start( "protocol_update", "push", 1.0, Proto.Update )
	
	if Me.hosting and IsInInstance() then
		Me.StopHosting()
	elseif not Me.hosting and not IsInInstance() then
		Me.StartHosting()
	end
	
	-- check link health
	for k, v in pairs( Proto.links ) do
		if v:RemoveExpiredNodes() then
			if v.node_count == 0 then
				-- we lost a link completely.
				Proto.next_status_broadcast = 0
			end
		end
	end
	
	if GetTime() > Proto.next_status_broadcast then
		Proto.next_status_broadcast = GetTime() + 60 -- debug value
		Proto.BroadcastStatus()
		Proto.PingLinks()
	end
end

-------------------------------------------------------------------------------
function Proto.GameAccounts( bnet_account_id )
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
function Proto.FriendsGameAccounts()
	
	local friend = 1
	local friends_online = select( 2, BNGetNumFriends() )
	local account_iterator = nil
		
	return function()
		while friend <= friends_online do
			if not account_iterator then
				local id, _,_,_,_,_,_, is_online = BNGetFriendInfo( friend )
				if is_online then
					account_iterator = Proto.GameAccounts( id )
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
function Proto.StartHosting()
	if Proto.hosting then return end
	
	if BNGetNumFriends() == 0 then
		-- Battle.net is bugged during this session.
		return
	end
	
	local my_faction = UnitFactionGroup( "player" )
	
	Proto.hosting = true
	--Proto.next_status_broadcast = GetTime() + 5
	Proto.next_status_broadcast = GetTime() + 1 -- debug bypass
	
	for charname, faction, game_account in Proto.FriendsGameAccounts() do
		
		local realm = charname:match( "%-(.+)" )
		if realm ~= Me.realm or faction ~= my_faction then
			Proto.SendBnetMessage( game_account, "HI", Me.secure_hash or "-" )
		end
	end
end

function Proto.PingLinks()
	local load = math.max( #Proto.links, 1 )
	load = math.min( load, 99 )
	for k, v in pairs( Proto.links ) do
		for gameid, _ in pairs( v.nodes ) do
			Proto.SendBnetMessage( gameid, "HO", load )
		end
	end
end

-------------------------------------------------------------------------------
function Proto.StopHosting()
	if not Proto.hosting then return end
	Proto.hosting = false
	Proto.Send( "local", "ST -" )
	
	for k, v in pairs( Proto.links ) do
		Proto.SendBnetMessage( v.gameid, "BYE" )
	end
	wipe( Proto.links )
end

-------------------------------------------------------------------------------
function Proto.BroadcastStatus()
	if not Proto.hosting then return end
	local bands = {}
	local deststring = ""
	for band, set in pairs( Proto.links ) do
		local avg = set:GetLoadAverage()
		if avg then
			deststring = deststring .. " " .. band .. avg
		end
	end
	
	-- ST <band list>
	Proto.Send( "local", "ST" .. deststring )
end

-------------------------------------------------------------------------------
function Proto.Send( destination, message )
	if destination == "all" then
		-- todo
		return
	elseif destination == "active" then
		-- todo
		return
	elseif destination == "local" then
		-- add header
		Proto.SendAddonMessage( "*", message )
		return
	end
	
	-- Find a bridge.
	local bridge = Proto.SelectBridge( destination )
	if not bridge then
		-- No available route.
		return
	end
	
	if bridge == Me.fullname then
		local link = Proto.SelectLink( destination )
		if not link then
			-- No link.
			-- in the future we might reply to the user to remove us as a bridge?
			return
		end
		Proto.SendBnetMessage( link, "R2", Me.protoname, destination, message )
	else
		-- todo, bypass this for self (but it should work both ways)
		-- VV R1 F DEST MESSAGE
		Proto.SendAddonMessage( bridge, "R1", Me.faction, destination, message )
	end
end

-------------------------------------------------------------------------------
function Proto.SelectBridge( destination )
	local band = destination:match( "[A-Za-z]*(%d+[AH])" )
	if not band then error( "Invalid destination." ) end
	local bridge = Proto.bridges[band]
	if not bridge then return end
	return bridge:Select()
end

-------------------------------------------------------------------------------
function Proto.SelectLink( destination, bias )
	local band = destination:match( "[A-Za-z]*(%d+[AH])" )
	if not band then error( "Invalid destination." ) end
	local link = Proto.links[band]
	if not link then return end
	if bias then
		if link:HasBnetLink( bias ) then
			return bias
		end
	end
	return link:Select()
end

-------------------------------------------------------------------------------
function Proto.SendBnetMessage( gameid, ... )
	local data = table.concat( {...}, " " )
	Me.Comm.SendBnetPacket( gameid, nil, true, data )
end

-------------------------------------------------------------------------------
function Proto.SendAddonMessage( target, ... )
	local data = table.concat( {...}, " " )
	Me.Comm.SendAddonPacket( target, nil, true, data )
end

-------------------------------------------------------------------------------
function Proto.FindLinkByGameAccount( gameid )
	for k, v in pairs( Proto.links ) do
		if v.gameid == gameid then
			return v, k
		end
	end
end

-------------------------------------------------------------------------------
function Proto.AddLink( gameid, load )
	load = load or 99
	local _, charname, _, realm, _, faction = BNGetGameAccountInfo( gameid )
	Me.DebugLog2( "Adding link.", charname, realm, gameid )
	realm = realm:gsub( "%s*%-*", "" )
	charname = charname .. "-" .. realm
	local band = Me.GetBandFromRealmFaction( realm, faction )
	if band == Proto.band then return end -- Same band as us.
	
	if not Proto.links[band] then
		Proto.links[band] = Me.NodeSet.Create()
	end
	
	Proto.links[band]:Add( gameid, load )
end

-------------------------------------------------------------------------------
function Proto.RemoveLink( gameid )
	for k, v in pairs( Proto.links ) do
		v:Remove( gameid )
	end
end

-------------------------------------------------------------------------------
function Proto.UpdateBridge( sender, bands )
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
		if not Proto.bridges[band] then
			Proto.bridges[band] = Me.NodeSet.Create()
		end
	end
	
	for band, bridge in pairs( Proto.bridges ) do
		local load = loads[band]
		if load then
			bridge:Add( sender, load )
		else
			bridge:Remove( sender )
		end
	end
end

-------------------------------------------------------------------------------
Proto.BroadcastPacketHandlers = {
	ST = function( job, sender )
		-- register or update a bridge.
		
		Proto.UpdateBridge( sender, job.text:sub(3) )
	end;
}

-------------------------------------------------------------------------------
Proto.BnetPacketHandlers = {
	HI = function( job, sender )
		if not job.complete then return end
		
		if not Proto.hosting then return false end
		Proto.AddLink( sender )
		-- reply
		
		local load = math.max( #Proto.links, 1 )
		load = math.min( load, 99 )
		Proto.SendBnetMessage( sender, "HO", load )
	end;
	
	HO = function( job, sender )
		if not job.complete then return end
		
		if not Proto.hosting then return false end
		local load = job.text:match( "^HO ([0-9]+)" )
		if not load then return false end
		load = tonumber(load)
		if load < 1 or load > 99 then return false end
		Proto.AddLink( sender, load )
	end;
	
	BYE = function( job, sender )
		if not job.complete then return end
		Proto.RemoveLink( sender )
	end;
	
	R2 = function( job, sender )
		
		if not job.skip_r3_for_self then
			if not job.forwarder then
				local source, dest_name, dest_band, message_data = job.text:match( "^R2 ([A-Za-z]+%d+[AH]) ([A-Za-z]*)(%d+[AH]) (.+)" )
				if not dest_name then return false end
				
				local destination = dest_name .. dest_band
				
				if destination:lower() == Me.protoname:lower() then
					-- we are the destination. Don't need R3 message.
					job.skip_r3_for_self = true
				else
					local send_to
					if dest_name ~= "" then
						send_to = Me.DestinationToFullname( destination )
					else
						send_to = "*"
					end
					
					job.forwarder = Me.Comm.SendAddonPacket( send_to )
					job.forwarder:AddText( job.complete, "R3 " .. source .. " " .. message_data )
					job.text = ""
				end
			else
				job.forwarder:AddText( job.complete, job.text )
				job.text = ""
			end
		end
		
		if job.skip_r3_for_self then
			if job.complete then
				local source, message_data = job.text:match( "^R2 ([A-Za-z]+%d+[AH]) [A-Za-z]*%d+[AH] (.+)" )
				-- handle message.
				Proto.OnMessageReceived( source, message_data )
			end
		end
	end;
}

-------------------------------------------------------------------------------
Proto.WhisperPacketHandlers = {
	R1 = function( job, sender )
		if not job.forwarder then
			local faction, destination, message_data = job.text:match( "^R1 ([AH]) ([A-Za-z]*%d+[AH]) (.+)" )
			if not destination then
				Me.DebugLog( "Bad R1 message." )
				return false
			end
			
			local link = Proto.SelectLink( destination )
			if not link then
				-- No link.
				-- in the future we might reply to the user to remove us as a bridge?
				return false
			end
			
			job.forwarder = Me.Comm.SendBnetPacket( link )
			local source = Me.FullnameToDestination( sender, faction )
			job.forwarder:AddText( job.complete, "R2 " .. source .. " " .. destination .. " " .. message_data )
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
		Proto.OnMessageReceived( source, message )
	end;
}

Proto.BroadcastPacketHandlers.R3 = Proto.WhisperPacketHandlers.R3
--[[
-------------------------------------------------------------------------------
function Proto.OnBnChatMsgAddon( event, prefix, message, _, sender )
	if prefix ~= "+RP" then return end
	Me.DebugLog2( "BNMSG:", message, sender )
	
	local version, command, rest = message:match( "([0-9]+) (%S+)%s*(.*)" )
	if not version or tonumber(version) ~= Proto.VERSION then
		Me.DebugLog( "Invalid BNET message from " .. sender )
		return
	end
	
	local handler = Proto.BnetPacketHandlers[command]
	if handler then handler( command, rest, sender ) end
end]]
--[[
-------------------------------------------------------------------------------
function Proto.OnChatMsgAddon( event, prefix, message, dist, sender )
	if prefix ~= "+RP" then return end
	Me.DebugLog2( "ADDONMSG:", message, dist, sender )
	
	local version, command, rest = message:match( "([0-9]+) (%S+)%s*(.*)" )
	if not version or tonumber(version) ~= Proto.VERSION then
		Me.DebugLog( "Invalid ADDON message from " .. sender )
		return
	end
	
	if dist == "CHANNEL" then
		local handler = Proto.BroadcastPacketHandlers[command]
		if handler then
			handler( command, message, sender )
		end
	elseif dist == "WHISPER" then
		local handler = Proto.WhisperPacketHandlers[command]
		if handler then
			handler( command, message, sender )
		end
	end
end]]


-- todo: on logout, let everyone know.

function Proto.TouchUnitBand( unit )
	local band = Me.BandFromUnit( unit )
	if band ~= Me.band then
		Proto.active_bands[band] = GetTime()
	end
end

-------------------------------------------------------------------------------
-- hooks
function Proto.OnMouseoverUnit()
	Proto.TouchUnitBand( "mouseover" )
end

function Proto.OnTargetUnit()
	Proto.TouchUnitBand( "target" )
end

function Proto.Test()
	--Proto.BnetPacketHandlers.HO( "HO", "1", 1443 )
	Proto.Send( "Catnia1H", "to catnia." )
	Proto.Send( "1H", "to all( baon)." )
	--Me.Comm.SendAddonPacket( "Tammya-MoonGuard", nil, true, "Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky. Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky." )
	--Me.Comm.SendAddonPacket( "Tammya-MoonGuard", nil, true, "Shankle pig pork loin, ham salami landjaeger sirloin rump turducken. Beef ribs pork belly ground round, filet mignon pork kielbasa boudin corned beef picanha kevin. Tail ribeye swine venison. Short ribs leberkas flank, jerky ribeye drumstick cow sirloin sausage.Shankle pig pork loin, ham salami landjaeger sirloin rump turducken. Beef ribs pork belly ground round, filet mignon pork kielbasa boudin corned beef picanha kevin. Tail ribeye swine venison. Short ribs leberkas flank, jerky ribeye drumstick cow sirloin sausage." )
	--Me.Comm.SendAddonPacket( "Tammya-MoonGuard", nil, true, "Jerky tail cow jowl burgdoggen, short loin kevin sirloin porchetta. Meatloaf strip steak salami cupim leberkas, andouille hamburger landjaeger tongue swine beef filet mignon meatball. Chuck pork belly tenderloin strip steak sausage flank, pork turducken jowl tri-tip. Jerky tail cow jowl burgdoggen, short loin kevin sirloin porchetta. Meatloaf strip steak salami cupim leberkas, andouille hamburger landjaeger tongue swine beef filet mignon meatball. Chuck pork belly tenderloin strip steak sausage flank, pork turducken jowl tri-tip. " )
	--Me.Comm.SendAddonPacket( "Tammya-MoonGuard", nil, true, "Pork loin chicken cow sirloin, ham pancetta andouille. Fatback biltong jerky ground round turducken. Pancetta jowl capicola picanha spare ribs shankle bresaola.Pork loin chicken cow sirloin, ham pancetta andouille. Fatback biltong jerky ground round turducken. Pancetta jowl capicola picanha spare ribs shankle bresaola." )
end

function Proto.OnMessageReceived( source, text )
	Me.DebugLog2( "Proto Msg", source, text )
end

-------------------------------------------------------------------------------
function Proto.OnDataReceived( job, dist, sender )
	if job.proto_abort then return end
	Me.DebugLog2( "DATA RECEIVED", job.type, job.complete and "COMPLETE" or "PROGRESS", sender, job.text )
	
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
		local handler = Proto.BnetPacketHandlers[ job.command ]
		if handler then handler_result = handler( job, sender ) end
	elseif job.type == "ADDON" then
		if dist == "CHANNEL" then
			local handler = Proto.BroadcastPacketHandlers[ job.command ]
			if handler then handler_result = handler( job, sender ) end
		elseif dist == "WHISPER" then
			local handler = Proto.WhisperPacketHandlers[ job.command ]
			if handler then handler_result = handler( job, sender ) end
		end
	end
	
	if handler_result == false then
		job.proto_abort = true
	end
end
