-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- The Alliance Protocol.
-------------------------------------------------------------------------------
local _, Me        = ...
local LibRealmInfo = LibStub("LibRealmInfo")

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
	hosting_time = 0;
	
	-- these are indexed by band
	links   = {};
	bridges = {};
	
	link_ids = {};
	crossrp_gameids = {};
	secure_code    = nil;
	secure_channel = nil;
	secure_hash    = nil;
	secure_myhash  = nil;
	
	do_status_request       = true;
	status_broadcast_time   = 0;
	status_broadcast_fast   = false;
	status_last_sent_empty  = false;
	
	registered_addon_prefixes = {};
	
	my_dest    = nil;
	my_band    = nil;
	my_realmid = nil;
	linked_realms = {};
	
	message_handlers = {};
	
	handlers = {
		BROADCAST = {};
		BNET      = {};
		WHISPER   = {};
	};
	
	realm_names = {
		ArgentDawn     = "AD";
		EmeraldDream   = "ED";
		MoonGuard      = "MG";
		WyrmrestAccord = "WRA";
	};
	
	-- indexed by both fullnames and gameids
	node_secure_data = {};
	
	start_time  = nil;
	
	umid_prefix = "";
	next_umid_serial = 1;
	seen_umids  = {};
	senders     = {};
	
	init_state = -1;
}
Me.Proto = Proto

-------------------------------------------------------------------------------
-- These servers get a special single digit realm identifier because they're
--  very popular. This may change if we decide to support non RP servers
--                                     (these IDs are overwriting PvE servers).
Proto.PRIMO_RP_SERVERS = {
	[1] = 1365; -- Moon Guard US
	[2] = 536;  -- Argent Dawn EU
	[3] = 1369; -- Wyrmrest Accord US
}
Proto.PRIMO_RP_SERVERS_R = {}
for k,v in pairs( Proto.PRIMO_RP_SERVERS ) do
	Proto.PRIMO_RP_SERVERS_R[v] = k
end

local START_DELAY          = 1.0 -- should be something more like 10 (or not?)
local HOSTING_GRACE_PERIOD = 60 * 5
local BAND_TOUCH_ACTIVE    = 60 * 15

-------------------------------------------------------------------------------
-- Destination utility functions.
-------------------------------------------------------------------------------
function Proto.GetBandFromUnit( unit )
	if not UnitIsPlayer( unit ) then return end
	local guid = UnitGUID( unit )
	if not guid then return end
	local realm = LibRealmInfo:GetRealmInfoByGUID( guid )
	local faction = UnitFactionGroup( unit )
	if realm <= 3 then
		realm = "0" .. realm
	else
		realm = Proto.PRIMO_RP_SERVERS_R[realm] or realm
	end
	return realm .. faction:sub(1,1)
end

-------------------------------------------------------------------------------
function Proto.GetBandFromDest( destination )
	return destination:match( "%d+[AH]" )
end

-------------------------------------------------------------------------------
function Proto.IsDestLocal( dest )
	return Proto.IsDestLinked( Proto.my_dest, dest )
end

-------------------------------------------------------------------------------
function Proto.DestFromFullname( fullname, faction )
	local realm = LibRealmInfo:GetRealmInfo( fullname:match("%-(.+)") or Me.realm )
	if realm <= 3 then
		realm = "0" .. realm
	else
		realm = Proto.PRIMO_RP_SERVERS_R[realm] or realm
	end
	return fullname:match( "^[^-]*" ) .. realm .. faction
end

-------------------------------------------------------------------------------
function Proto.DestToFullname( dest )
	local name, realm = dest:match( "(%a+)(%d+)" )
	name = name:lower()
	name = name:gsub( "^[%z\1-\127\194-\244][\128-\191]*", string.upper )
	local primo = realm.byte(1) ~= 48
	realm = tonumber(realm)
	realm = primo and Proto.PRIMO_RP_SERVERS[realm] or realm
	local _, _, realm_apiname = LibRealmInfo:GetRealmInfoByID( realm )
	return name .. "-" .. realm_apiname
end

-------------------------------------------------------------------------------
function Proto.IsDestLinked( dest1, dest2 )
	if dest1:byte(#dest1) ~= dest2:byte(#dest2) then
		-- factions not same
		return false
	end
	local band1, band2 = dest1:match( "(%d+)[AH]" ), dest2:match( "(%d+)[AH]" )
	if not band1 or not band2 then return end
	if band1 == band2 then return true end
	
	if Proto.GetLinkedBand(dest1) == Proto.GetLinkedBand(dest2) then
		return true
	end
end

-------------------------------------------------------------------------------
function Proto.GetLinkedBand( dest1 )
	local realm, faction = dest1:match( "(%d+)([AH])" )
	local primo = realm.byte(1) ~= 48
	realm = tonumber(realm)
	if primo and Proto.PRIMO_RP_SERVERS[realm] then
		-- primo servers aren't linked.
		return realm .. faction
	end
	local realmid, _,_,_,_,_,_,_,connections = LibRealmInfo:GetRealmInfoByID( realm )
	for _, v in pairs( connections ) do
		realm = math.min( realm, v )
	end
	return realm .. faction
end

-------------------------------------------------------------------------------
function Proto.GetBandName( band )
	local realm, faction = band:match( "(%d+)([AH])" )
	if not realm then return UNKNOWN end
	local primo = realm.byte(1) ~= 48
	realm = tonumber(realm)
	realm = primo and Proto.PRIMO_RP_SERVERS[realm] or realm
	local realmid,_,apiname = LibRealmInfo:GetRealmInfoByID( realm )
	apiname = Proto.realm_names[apiname] or apiname:sub(1,5)
	return (apiname .. "-" .. faction):upper()
end

-------------------------------------------------------------------------------
function Proto.Init()
	local prefix_digits = 
	           "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
	local umid_prefix = ""
	for i = 1, 5 do
		local digit = math.random( 1, #prefix_digits )
		umid_prefix = umid_prefix .. prefix_digits:sub( digit, digit )
	end
	Proto.umid_prefix = umid_prefix
	
	Proto.my_dest = Proto.DestFromFullname( Me.fullname, Me.faction )
	Proto.my_band = Proto.GetBandFromDest( Proto.my_dest )
	
	Proto.linked_realms[Me.realm] = true
	for k, v in pairs( GetAutoCompleteRealms() ) do
		Proto.linked_realms[v] = true
	end
	
	Proto.init_state = 0
	Me.Timer_Start( "proto_start", "push", START_DELAY, function()
		Proto.JoinGameChannel( "crossrp", Proto.Start )
	end)
	
	Proto.Init = nil
end

-------------------------------------------------------------------------------
function Proto.GameChannelExists( name )
	return GetChannelName( name ) ~= 0
end

-------------------------------------------------------------------------------
function Proto.MoveGameChannelToBottom( name )
	
	local index = GetChannelName( name )
	local last_channel = index
	if index == 0 then return end
	for i = last_channel, MAX_WOW_CHAT_CHANNELS do
		if GetChannelName( i ) ~= 0 then
			last_channel = i
		end
	end
	
	for i = index, last_channel-1 do
		C_ChatInfo.SwapChatChannelsByChannelIndex( i, i + 1 )
	end
end

-------------------------------------------------------------------------------
function Proto.JoinGameChannel( name, onjoin, retries )
	if Proto.GameChannelExists( name ) then
		Proto.MoveGameChannelToBottom( name )
		if onjoin then
			onjoin( name )
		end
	else
		if retries and retries <= 0 then
			if name == "crossrp" then
				Me.Print( "Error: couldn't join broadcast channel." )
			else
				Me.Print( "Error: couldn't join channel '%s'.", name )
			end
			return
		end
		JoinTemporaryChannel( name )
		Me.Timer_Start( "joinchannel_" .. name, "push", 1.0, Proto.JoinGameChannel, name, onjoin or false, (retries or 10) - 1 )
	end
end

-------------------------------------------------------------------------------
function Proto.LeaveGameChannel( name )
	Me.Timer_Cancel( "joinchannel_" .. name )
	if Proto.GameChannelExists( name ) then
		LeaveChannelByName( name )
	end
end

-------------------------------------------------------------------------------
function Proto.Start()
	Me.DebugLog2( "PROTO STARTUP 1" )
	Proto.init_state = 1
	Proto.start_time = GetTime()
	if not Me.db.char.proto_crossrp_channel_added then
		Me.db.char.proto_crossrp_channel_added = true
		ChatFrame_AddChannel( DEFAULT_CHAT_FRAME, Proto.channel_name )
	end
	
	C_ChatInfo.RegisterAddonMessagePrefix( "+RP" )
	--Proto.SetSecure( 'henlo' ) -- debug
	
	-- this is the only command we want to listen to until after this initialization step
	Me.Comm.SetMessageHandler( "BNET", "HI", Proto.handlers.BNET.HI )

	Me:SendMessage( "CROSSRP_PROTO_START" )
	Proto.BroadcastBnetStatus( true, true, nil, "FAST" )
	
	-- debug: should be 2.5 wait time
	Me.Timer_Start( "proto_startup2", "ignore", 3, Proto.Start2 )
	Proto.Start = nil
end

-------------------------------------------------------------------------------
function Proto.Start2()
	Me.DebugLog2( "PROTO STARTUP 2" )
	Proto.init_state = 2
	
	-- register the rest of our commands
	for dist, set in pairs( Proto.handlers ) do
		for command, handler in pairs( set ) do
			Me.Comm.SetMessageHandler( dist, command, handler )
		end
	end
	Proto.handlers = nil
	
	if not Proto.HasUnsuitableLag() then
		Proto.StartHosting()
	end
	
	Me:SendMessage( "CROSSRP_PROTO_START2" )
	
	Proto.BroadcastStatus( nil, "FAST" )
	if Proto.hosting then
		Proto.BroadcastBnetStatus( false, false )
	end
	
	-- debug : should be 3.0 wait time
	Me.Timer_Start( "proto_startup3", "ignore", 3.0, Proto.Start3 )
	Proto.Start2 = nil
end

-------------------------------------------------------------------------------
function Proto.Start3()
	Me.DebugLog2( "PROTO STARTUP 3" )
	Proto.init_state = 3
	Proto.startup_complete = true
	Me:SendMessage( "CROSSRP_PROTO_START3" )
	Proto.Update()
	Me.Timer_Start( "proto_clean_umids", "push", 35.0, Proto.CleanSeenUMIDs )
	Proto.Start3 = nil
end

function Proto.HasUnsuitableLag()
	local _,_, home_lag, world_lag = GetNetStats()
	return math.max( home_lag, world_lag ) > 500
end

-------------------------------------------------------------------------------
function Proto.Shutdown()
	Me.Comm.SendAddonPacket( "*", nil, true, "BYE", nil, "URGENT" )
	for charname, faction, game_account in Proto.FriendsGameAccounts() do
		local realm = charname:match( "%-(.+)" )
		if not Proto.linked_realms[realm] or faction ~= Me.faction then
			Me.Comm.SendBnetPacket( game_account, nil, true, "BYE", nil, "URGENT" )
		end
	end
end

-------------------------------------------------------------------------------
function Proto.IsHosting( include_grace_period )
	if Proto.hosting then
		return true
	else
		if include_grace_period and (GetTime() < Proto.hosting_time + HOSTING_GRACE_PERIOD) then
			return true
		end
	end
end

-------------------------------------------------------------------------------
function Proto.CleanSeenUMIDs()
	Me.Timer_Start( "proto_clean_umids", "push", 35.0, Proto.CleanSeenUMIDs )
	local time, seen_umids = GetTime() + 300, Proto.seen_umids
	
	for k,v in pairs( seen_umids ) do
		if time > v then
			seen_umids[k] = nil
		end
	end
end

-------------------------------------------------------------------------------
function Proto.Update()
	Me.Timer_Start( "protocol_update", "push", 1.0, Proto.Update )
	
	if Proto.hosting and IsInInstance() then
		Proto.StopHosting()
	elseif not Proto.hosting and not IsInInstance() then
		Proto.StartHosting()
	end
	
	if Proto.hosting then
		Proto.hosting_time = GetTime()
	end
	
	-- check link health
	for k, v in pairs( Proto.links ) do
		if v:RemoveExpiredNodes() then
			-- we lost a link completely.
			Proto.status_broadcast_time = 0
			Proto.status_broadcast_fast = true
		end
	end
	
	Proto.PurgeOfflineLinks( false )
	
	local senders_copy = {}
	for _, sender in pairs( Proto.senders ) do
		senders_copy[ #senders_copy ] = sender
	end
	for _, v in pairs( senders_copy ) do
		Proto.ProcessSender( v )
	end
	
	local time = GetTime()
	-- give a few seconds after the proto start for things to initialize
	-- such as the RPCHECK message getting a response. otherwise we're gonna
	-- be sending out two status messages.
	if Proto.hosting and time > Proto.status_broadcast_time + 120 then
		Proto.status_broadcast_time = time + 120
		Proto.BroadcastStatus()
		Proto.BroadcastBnetStatus()
	end
end

-------------------------------------------------------------------------------
function Proto.PurgeOfflineLinks( run_update )
	for gameid,_ in pairs( Proto.link_ids ) do
		local _, charname, _, realm, _, faction = BNGetGameAccountInfo( gameid )
		if not charname or charname == "" then
			Proto.RemoveLink( gameid, true )
		end
	end
	
	if Proto.status_broadcast_time == 0 then
		Proto.status_broadcast_fast = true
		if run_update then
			Proto.Update()
		end
	end
end

-------------------------------------------------------------------------------
function Proto.OnBnFriendInfoChanged()
	if not Proto.startup_complete then return end
	Me.Timer_Start( "purge_offline", "ignore", 0.01, Proto.PurgeOfflineLinks, true )
end

-------------------------------------------------------------------------------
function Proto.UpdateSecureNodeSets()
	
	for k, v in pairs( Proto.node_secure_data ) do
		Proto.UpdateNodeSecureData( k, v.h1, v.h2 )
	end
	
	for band, bridge in pairs( Proto.bridges ) do
		for k, v in pairs( bridge.nodes ) do
			if Proto.node_secure_data[k] and Proto.node_secure_data[k].secure then
				bridge:ChangeNodeSubset( k, "secure" )
			end
		end
	end
	
	for band, link in pairs( Proto.links ) do
		for k, v in pairs( link.nodes ) do
			if Proto.node_secure_data[k] and Proto.node_secure_data[k].secure then
				link:ChangeNodeSubset( k, "secure" )
			end
		end
	end
	
	Proto.UpdateSelfBridge()
end

-------------------------------------------------------------------------------
function Proto.SetSecure( code )
	Proto.ResetSecureState()
	Proto.secure_code = code
	if code then
		Proto.secure_channel = Proto.GetSecureChannel()
		Proto.secure_hash    = Me.Sha256( Proto.secure_code )
		Proto.secure_myhash  = Me.Sha256( Me.fullname .. Proto.secure_code )
		if not Proto.registered_addon_prefixes[Proto.secure_channel] then
			Proto.registered_addon_prefixes[Proto.secure_channel] = true
			C_ChatInfo.RegisterAddonMessagePrefix( Proto.secure_channel .. "+RP" )
		end
		Proto.UpdateSecureNodeSets()
	else
		Proto.secure_channel = nil
		Proto.secure_hash    = nil
		Proto.secure_myhash  = nil
	end
	Proto.status_broadcast_time = 0
end

-------------------------------------------------------------------------------
function Proto.ResetSecureState()
	for k,v in pairs( Proto.links ) do
		v:EraseSubset( "secure" )
	end
end

-------------------------------------------------------------------------------
function Proto.GetSecureChannel()
	local sha1, sha2 = Me.Sha256Data( "channel" .. Proto.secure_code )
	local channel = tostring( sha1 % 1073741824, 32 ) .. tostring( sha2 % 1073741824, 32 )
	return channel:sub( 1,10 )
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
				realm = realm:gsub( "[ -]", "" )
				return char_name .. "-" .. realm, faction:sub(1,1), game_account_id
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
		if not Proto.warned_bnet_down then
			Proto.warned_bnet_down = true
			Me.DebugLog2( "Battle.net is down for this session. Cannot host." )
		end
		return
	end
	
	Proto.hosting               = true
	Proto.hosting_time          = GetTime()
	Proto.status_broadcast_time = 0
end

-------------------------------------------------------------------------------
function Proto.StopHosting()
	if not Proto.hosting then return end
	Proto.hosting = false
	Proto.BroadcastStatus()
	Proto.BroadcastBnetStatus( false, false )
end

-------------------------------------------------------------------------------
function Proto.BroadcastStatus( target, priority )
	local secure_hash1, secure_hash2 = "-", "-"
	local bands = {}
	
	if Proto.hosting then
		if Proto.secure_code then
			secure_hash1, secure_hash2 = Proto.secure_hash:sub(1,12),
										  Proto.secure_myhash:sub(1,8)
		end
		
		for band, set in pairs( Proto.links ) do
			local avg = set:GetLoadAverage()
			if avg then
				local secure_mark = ""
				if Proto.secure_code then
					if set:SubsetCount( "secure" ) > 0 then
						secure_mark = "#"
					end
				end
				table.insert( bands, secure_mark .. band .. avg )
			end
		end
	end
	
	
	bands = table.concat( bands, ":" )
	if bands == "" then bands = "-" end
	local request = "-"
	if not target and Proto.do_status_request then
		request = "?"
		Proto.do_status_request = nil
	end
	
	if bands == "-" then
		-- for targeted status, we never send an empty band list (becausethe target request is only made on addon load, when their state is fresh)
		-- if we sent an empty band list on the last status, then dont do it again
		if target or Proto.status_last_sent_empty then
			return
		end
		
		Proto.status_last_sent_empty = true
	end
	
	if not target then
		Me.Comm.CancelSendByTag( "st" )
	end
	Me.DebugLog2( "Sending status.", target )
	local job = Proto.SendAddonMessage( target or "*", 
	          {"ST", Me.version, request, secure_hash1, secure_hash2, bands},
			       false, Proto.status_broadcast_fast and "FAST" or priority or "NORMAL" )
	job.tags = {"st"}
	Proto.status_broadcast_fast = false
	Proto.status_broadcast_time = GetTime()
end

-------------------------------------------------------------------------------
function Proto.BroadcastBnetStatus( all, request, load_override, priority )
	local send_to
	if all then
		send_to = {}
		for charname, faction, game_account in Proto.FriendsGameAccounts() do
			local realm = charname:match( "%-(.+)" )
			if not Proto.linked_realms[realm] or faction ~= Me.faction then
				send_to[game_account] = true
			end
		end
	else
		send_to = Proto.crossrp_gameids
		--[[for k, v in pairs( Proto.crossrp_gameids ) do
			for gameid, _ in pairs( v.nodes ) do
				if not send_to[gameid] then
					send_to[gameid] = true
				end
			end
		end]]
	end
	
	Me.Comm.CancelSendByTag( "hi" )
	Proto.SendHI( send_to, request, load_override, priority )
end

-------------------------------------------------------------------------------
function Proto.SendHI( gameids, request, load_override, priority )
	if type(gameids) == "number" then
		gameids = {[gameids] = true}
	end
	
	local load
	if Proto.hosting then
		load = math.min( math.max( load_override or #Proto.links, 1 ), 99 )
	else
		load = 0
	end
	
	local short_passhash = (Proto.secure_hash or "-"):sub(1,12)
	local passhash       = (Proto.secure_myhash or "-"):sub(1,8)
	
	local request_mode = request and "?" or "-"
	
	for id, _ in pairs( gameids ) do
		local job = Proto.SendBnetMessage( id, 
		     {"HI", Me.version, request_mode, load, short_passhash, passhash}, false, priority or "LOW" )
		job.tags = {"hi"}
	end
end

-------------------------------------------------------------------------------
function Proto.GetNetworkStatus()
	-- TODO add check here for call-caching every second
	local status = {}
	for band, set in pairs( Proto.bridges ) do
		local qsum = math.ceil(set.quota_sums.all * 10 / 1000)
		local secure = set.node_counts.secure > 0
		local includes_self = set.nodes[Me.fullname]
		table.insert( status, {
			band  = band;
			quota = qsum;
			secure = secure;
			direct = includes_self;
			active = GetTime() < (Proto.active_bands[band] or 0) + BAND_TOUCH_ACTIVE
		})
	end
	
	table.sort( status, function( a, b ) 
		return a.band < b.band
	end)
	
	return status
end

local ACK_TIMEOUT = 10.0
local ACK_TIMEOUT_PER_BYTE = 2.0/250
local ONLINE_TIMEOUT = 3.0

-------------------------------------------------------------------------------
function Proto.OnAckReceived( umid )
	Me.DebugLog( "Got ACK for %s.", umid )
	for k, sender in pairs( Proto.senders ) do
		for sender_umid, data in pairs( sender.umids ) do
			if sender_umid == umid then
				sender.umids[umid] = nil
				if sender.callback then
					sender.callback( sender, "CONFIRMED_DEST", data.dest )
				end
				
				if not next( sender.umids ) then
					if sender.callback then
						sender.callback( sender, "CONFIRMED" )
						sender.callback( sender, "DONE" )
					end
					Proto.senders[sender] = nil
				end
				return
			end
		end
	end
	
	Me.DebugLog( "Got ACK but couldn't match the UMID (%s).", umid )
end

-------------------------------------------------------------------------------
--[[ old method
function Proto.OnUMIDFailed( umid )
	Me.DebugLog( "UMID failure. %s", umid )
	for k, sender in pairs( Proto.senders ) do
		for sender_umid, data in pairs( sender.umids ) do
			if sender_umid == umid then
				data.time      = nil
				data.r1_bridge = nil
				-- this will cause it to be resent
				Proto.ProcessSender( sender )
				return
			end
		end
	end
end]]
local SYSTEM_PLAYER_NOT_FOUND_PATTERN = ERR_CHAT_PLAYER_NOT_FOUND_S:gsub( "%%s", "(.+)" )

-------------------------------------------------------------------------------
function Proto.OnChatMsgSystem( event, msg )
	if not Proto.startup_complete then return end
	
	local name = msg:match(SYSTEM_PLAYER_NOT_FOUND_PATTERN)
	Proto.suppress_player_not_found_chat = GetTime()
	-- this might be an ambiguated name, and in that case we shouldnt end up doing anything.
	-- because our senders always use fullnames
	if name then
		Me.DebugLog( "Removing offline bridge %s.", name )
		Proto.RemoveBridge( name )
		for k, sender in pairs( Proto.senders ) do
			for sender_umid, data in pairs( sender.umids ) do
				if data.r1_bridge == name then
					data.time = nil
					-- this will cause it to be resent
					Proto.ProcessSender( sender )
					break
				end
			end
		end
		
	end
end

-------------------------------------------------------------------------------
function Proto.ProcessSenderUMID( sender, umid )
	local data = sender.umids[umid]
	if not data.time or (sender.guarantee and GetTime() > data.time + ACK_TIMEOUT + ACK_TIMEOUT_PER_BYTE * #sender.msg) then
		if data.tries >= 5 then
			if sender.callback then
				sender.callback( sender, "TIMEOUT", data )
			end
			sender.umids[umid] = nil
			return
		end
		
		if Proto.IsDestLocal( data.dest ) then
			if sender.ack then
				error( "Internal error." )
			end
			local localplayer = data.dest:match( "(%a*)%d+[AH]" )
			local target
			
			if localplayer ~= "" then
				target = Proto.DestToFullname( data.dest )
			else
				target = "*"
			end
			
			Proto.SendAddonMessage( target, {"R0", sender.msg}, sender.secure, sender.priority )
			if sender.callback then
				sender.callback( sender, "LOCAL_SENT", data )
			end
			sender.umids[umid] = nil
			return
		end
		
		-- remove defunct bridge.
		if data.r1_bridge and data.r1_bridge ~= Me.fullname then
			assert( data.r1_bridge ~= Me.fullname, "R1 bridge shouldn't have been used." )
			-- this bridge failed us...
			Proto.RemoveBridge( data.r1_bridge )
			data.r1_bridge = nil
		end
		
		-- send message (or resend)
		
		-- Find a bridge.
		local bridge = Proto.SelectBridge( data.dest, sender.secure )
		if not bridge then
			if sender.callback then
				sender.callback( sender, "NOBRIDGE", data )
			end
			sender.umids[umid] = nil
			-- No available route.
			return
		end
		
		local flags = Me.faction
		if sender.guarantee then flags = flags .. "G" end
		
		if bridge == Me.fullname then
			local link = Proto.SelectLink( data.dest, sender.secure )
			if not link then
				if sender.callback then
					sender.callback( sender, "NOBRIDGE", data )
				end
				
				-- todo: this should be a logical error, as we SHOULD have link data if we are a valid bridge selected above
				sender.umids[umid] = nil
				-- No link.
				-- in the future we might reply to the user to remove us as a bridge?
				return
			end
			
			if sender.ack then
				Proto.SendBnetMessage( link, {"A2", umid, data.dest}, sender.secure, sender.priority )
			else
				Proto.SendBnetMessage( link, {"R2", umid, flags, Proto.my_dest, data.dest, sender.msg}, sender.secure, sender.priority )
			end
			
		else
			-- todo, bypass this for self (but it should work both ways)
			-- VV R1 F DEST MESSAGE
			if sender.ack then
				Proto.SendAddonMessage( bridge, {"A1", umid, data.dest}, sender.secure, sender.priority )
			else
				Proto.SendAddonMessage( bridge, {"R1", umid, flags, data.dest, sender.msg}, sender.secure, sender.priority )
			end
			
			data.r1_bridge = bridge
		end
		
		data.tries = data.tries + 1
		data.time = GetTime()
		
		if sender.callback then
			sender.callback( sender, "SENT", data )
		end
	elseif data.time and (not sender.guarantee and GetTime() >= data.time + ONLINE_TIMEOUT) then
		-- this is only for non guaranteed things
		-- otherwise this is done when the ACK is received.
		sender.umids[umid] = nil
		if not next( sender.umids ) then
			Proto.senders[sender] = nil
			if sender.callback then
				sender.callback( sender, "DONE" )
			end
		end
	end
end

-------------------------------------------------------------------------------
function Proto.ProcessSender( sender )
	for umid, _ in pairs( sender.umids ) do
		Proto.ProcessSenderUMID( sender, umid )
	end
	
	if not next(sender.umids) then
		Proto.senders[sender] = nil
		if sender.callback then
			sender.callback( sender, "DONE" )
		end
	end
end

function Proto.CheckSenderRoutes( route_fullname )
	if #Proto.senders == 0 then return end
	
	local senders_copy = {}
	for _, sender in pairs( Proto.senders ) do
		senders_copy[ #senders_copy ] = sender
	end
	
	
	for _, sender in pairs( senders_copy ) do
		local process = false
		for umid, data in pairs( sender.umids ) do 
			if data.r1_bridge == route_fullname then
				if not Proto.BridgeValid( data.r1_bridge ) then
					data.time = nil
					data.r1_bridge = nil
					data.tries = data.tries - 1
					process = true
				end
			end
			if process then
				Proto.ProcessSender( sender )
			end
		end
	end
end

-------------------------------------------------------------------------------
function Proto.GenerateUMID()
	local umid = Proto.umid_prefix .. Proto.next_umid_serial
	Proto.next_umid_serial = Proto.next_umid_serial + 1
	return umid
end

-------------------------------------------------------------------------------
-- destinations can be
-- local: to local crossrp channel
-- all: to all crossrp channels we can reach
-- active: to all "touched" crossrpchannels we can reach
-- <band>: to the crossrp channel for this band
-- <user><band>: to this specific user
-- <user><myband>: local addon message (not implemented/used)
function Proto.Send( dest, msg, options ) --secure, priority, guarantee, callback )
	local secure = options.secure
	if secure and not Proto.secure_code then
		Me.DebugLog2( "Tried to send secure message outside of secure mode." )
		return
	end
	
	if type(msg) == "table" then
		msg = table.concat( msg, " " )
	end
	
	if dest == "local" then dest = { Proto.my_band } end
	
	if dest == "all" or dest == "active" then
		-- todo
		local send_to = { Proto.my_band }
		local time = GetTime()
		for k, v in pairs( Proto.bridges ) do
			if not v:Empty( secure and "secure" ) then
				local active = time < (Proto.active_bands[k] or 0) + BAND_TOUCH_ACTIVE
				if dest == "all" or (dest == "active" and active) then
					table.insert( send_to, k )
				end
			end
		end
		
		dest = send_to
		
		--for k, v in ipairs( send_to ) do
		--	Proto.Send( v, msg, secure, priority, guarantee )
		--end
		--return
		
		--[[
	elseif Proto.IsDestLocal(dest) then
		-- this should be an r0, because this function is for forwarded messages that end up in a different handler.
		
		local localplayer = dest:match( "(%a*)%d+[AH]" )
		local target
		
		if localplayer ~= "" then
			target = Proto.DestToFullname( dest )
		else
			target = "*"
		end
		
		Proto.SendAddonMessage( target, {"R0", msg}, secure, priority )
		return]]
	end
	
	local sender = options
	sender.umids = {}
	sender.msg   = msg
	
	if type(dest) == "string" then dest = {dest} end
	
	for k, v in ipairs( dest ) do
		local umid = Proto.GenerateUMID()
		sender.umids[umid] = { umid = umid, dest = v, tries = 0 }
	end
	
	Proto.senders[sender] = sender
	Proto.ProcessSender( sender )
end

-------------------------------------------------------------------------------
function Proto.SendAck( dest, umid )
	Me.DebugLog2( "Sending ACK", dest, umid )
	local sender = {
		ack   = true;
		umids = { [umid] = { umid = umid, dest = dest, tries = 0} };
		msg   = "";
	}
	
	Proto.senders[sender] = sender
	Proto.ProcessSender( sender )
end

function Proto.BridgeValid( destination, secure, fullname )
	local band = destination:match( "%a*(%d+[AH])" )
	band = Proto.GetLinkedBand( band )
	local bridge = Proto.bridges[band]
	if not bridge then return end
	return bridge:KeyExists( fullname, secure )
end

-------------------------------------------------------------------------------
function Proto.SelectBridge( destination, secure )
	local band = destination:match( "%a*(%d+[AH])" )
	band = Proto.GetLinkedBand( band )
	local bridge = Proto.bridges[band]
	if not bridge then return end
	return bridge:Select( secure and "secure" )
end

-------------------------------------------------------------------------------
function Proto.SelectLink( destination, secure )
	local user, band = destination:match( "(%a*)(%d+[AH])" )
	band = Proto.GetLinkedBand( band )
	local link = Proto.links[band]
	if not link then return end
	
	if user ~= "" then
		-- if user is set, try to get a direct link to that user.
		local direct = link:HasBnetLink( destination )
		if direct then return direct end
	end
	
	return link:Select( secure and "secure")
end

-------------------------------------------------------------------------------
local function SpaceConcat( data )
	if type(data) == "table" then
		data = table.concat( data, " " )
	end
	return data
end

-------------------------------------------------------------------------------
function Proto.SendBnetMessage( gameid, msg, secure, priority )
	if secure and not Proto.secure_code then return end
	return Me.Comm.SendBnetPacket( gameid, nil, true, SpaceConcat(msg), secure and Proto.secure_channel, priority )
end

-------------------------------------------------------------------------------
function Proto.SendAddonMessage( target, msg, secure, priority )
	if secure and not Proto.secure_code then return end
	return Me.Comm.SendAddonPacket( target, nil, true, SpaceConcat(msg), secure and Proto.secure_channel, priority )
end

-------------------------------------------------------------------------------
function Proto.AddLink( gameid, load, secure )
	load = load or 99
	local _, charname, _, realm, _, faction = BNGetGameAccountInfo( gameid )
	Me.DebugLog2( "Adding link.", charname, realm, gameid, "secure?", secure )
	if not charname then
		-- No Battle.net information available.
		return
	end
	
	realm = realm:gsub( "[ -]", "" )
	charname = charname .. "-" .. realm
	local band = Proto.DestFromFullname( "-" .. realm, faction )
	if Proto.IsDestLinked( band, Proto.my_band ) then
		-- same band as us
		return
	end
	
	band = Proto.GetLinkedBand( band )
	
	if not Proto.links[band] then
		Proto.links[band] = Me.NodeSet.Create( { "secure" } )
	end
	
	local subset
	if Proto.node_secure_data[gameid] and Proto.node_secure_data[gameid].secure then
		subset = "secure"
	end
	Proto.link_ids[gameid] = true
	Proto.crossrp_gameids[gameid] = true
	
	Proto.links[band]:Add( gameid, load, subset )
	
	Proto.UpdateSelfBridge()
end

-------------------------------------------------------------------------------
function Proto.RemoveLink( gameid, unset_crossrp )
	Me.DebugLog2( "Removing link.", gameid )
	for k, v in pairs( Proto.links ) do
		if v:Remove( gameid ) then
			Proto.status_broadcast_time = 0
			Proto.status_broadcast_fast = true
		end
	end
	Proto.link_ids[gameid] = nil
	
	if unset_crossrp then
		Proto.crossrp_gameids[gameid] = nil
	else
		Proto.crossrp_gameids[gameid] = true
	end
	
	Proto.UpdateSelfBridge()
end

-------------------------------------------------------------------------------
function Proto.UpdateSelfBridge()
	local loads        = {}
	local secure_bands = {}
	for band, set in pairs( Proto.links ) do
		local avg = set:GetLoadAverage()
		if avg then
			if Proto.secure_code then
				if set:SubsetCount( "secure" ) > 0 then
					secure_bands[band] = "secure"
				end
			end
			loads[band] = avg
		end
	end
	
	for band, load in pairs( loads ) do
		if not Proto.bridges[band] then
			Proto.bridges[band] = Me.NodeSet.Create( {"secure"} )
		end
	end
	
	for band, bridge in pairs( Proto.bridges ) do
		local load = loads[band]
		if load then
			bridge:Add( Me.fullname, load, secure_bands[band] )
		else
			bridge:Remove( Me.fullname )
		end
	end
end

-------------------------------------------------------------------------------
function Proto.UpdateBridge( sender, bands )
	-- all of the bands in here should be LINKED bands
	-- if not then the user may have received a bad message.
	local loads = {}
	local secure_bands = {}
	local secure_bridge = Proto.node_secure_data[sender] and Proto.node_secure_data[sender].secure
	
	for secure, band, load in bands:gmatch( "(#?)(%d+[AH])([0-9]+)" ) do
		load = tonumber(load)
		
		if load < 1 or load > 99 then
			-- invalid input. cancel this user.
			loads = {}
			break
		end
		
		loads[band] = tonumber(load)
		if secure_bridge and secure ~= "" then
			secure_bands[band] = "secure"
		end
	end
	
	-- create any nonexistant bridges.
	for band, load in pairs( loads ) do
		if not Proto.bridges[band] then
			Proto.bridges[band] = Me.NodeSet.Create( {"secure"} )
		end
	end
	
	for band, bridge in pairs( Proto.bridges ) do
		local load = loads[band]
		if load then
			bridge:Add( sender, load, secure_bands[band] )
		else
			bridge:Remove( sender )
		end
	end
end

function Proto.RemoveBridge( sender )
	for band, bridge in pairs( Proto.bridges ) do
		bridge:Remove( sender )
	end
end

-------------------------------------------------------------------------------
function Proto.GetFullnameFromGameID( gameid )
	local _, charname, _, realm, _, faction = BNGetGameAccountInfo( gameid )
	realm = realm:gsub( "[ -]", "" )
	charname = charname .. "-" .. realm
	return charname, faction
end

function Proto.UpdateNodeSecureData( id, hash1, hash2 )
	if not hash1 or hash1 == "" or hash1 == "-" then
		Proto.node_secure_data[id] = nil
	else
		local sd = Proto.node_secure_data[id] or {}
		Proto.node_secure_data[id] = sd
		if sd.code ~= Proto.secure_code or sd.h1 ~= hash1 or sd.h2 ~= hash2 then
			sd.code = Proto.secure_code
			sd.h1   = hash1
			sd.h2   = hash2
			
			if Proto.secure_code and hash1 == Proto.secure_hash:sub(1,12) then
				local name = type(id) == "number" and Proto.GetFullnameFromGameID( id ) or id
				local hash = Me.Sha256( name .. Proto.secure_code )
				sd.secure = hash:sub(1,8) == hash2
			else
				sd.secure = false
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Broadcast Packet Handlers
-------------------------------------------------------------------------------
function Proto.handlers.BROADCAST.ST( job, sender )
	if not job.complete then return end
	
	-- ignore for self
	if sender == Me.fullname then return end
	
	-- register or update a bridge.
	local version, request, secure_hash1, secure_hash2, bands = job.text:match( "ST (%S+) (%S) (%S+) (%S+)(%S+)" )
	if not version then return end
	
	Proto.UpdateNodeSecureData( sender, secure_hash1, secure_hash2 )
	
	if bands == "-" then
		Proto.RemoveBridge( sender )
	else
		Proto.UpdateBridge( sender, bands )
	end
	
	if request == "?" then
		Me.DebugLog2( "status requets" )
		Proto.BroadcastStatus( sender, "FAST" )
	end
	
	-- sometimes someone will send a status message when they cant route our
	--  data.  it should be a whisper message but we check in broadcast too for
	--  prudence
	Proto.CheckSenderRoutes( sender )
end

-------------------------------------------------------------------------------
-- Bnet Packet Handlers
-------------------------------------------------------------------------------
function Proto.handlers.BNET.HI( job, sender )
	if not job.complete then return end
	-- HI <version> <request> <load> <secure short hash> <personal hash>
	local version, request, load, short_hash, personal_hash = job.text:match( 
										 "^HI (%S+) (.) ([0-9]+) (%S+) (%S+)" )
	if not load then return false end
	load = tonumber(load)
	if load > 99 then return false end
	
	local _, charname, _, realm, _, faction = BNGetGameAccountInfo( sender )
	realm = realm:gsub( "[ -]", "" )
	if Proto.linked_realms[realm] and faction:sub(1,1) == Me.faction then
		-- this is a local target, and this message should never be sent to us.
		return
	end
	
	Proto.UpdateNodeSecureData( sender, short_hash, personal_hash )
	
	if load > 0 then
		Proto.AddLink( sender, load )
	else
		Proto.RemoveLink( sender )
	end
	
	if request == "?" then
		Proto.SendHI( sender, false, nil, "FAST" )
	end
end
	
---------------------------------------------------------------------------
function Proto.handlers.BNET.BYE( job, sender )
	Proto.node_secure_data[sender] = nil
	Proto.crossrp_gameids[sender] = nil
	Proto.RemoveLink( sender )
end

---------------------------------------------------------------------------
function Proto.handlers.BROADCAST.BYE( job, sender )
	Proto.node_secure_data[sender] = nil
	Proto.RemoveBridge( sender )
end

---------------------------------------------------------------------------
function Proto.OnR3Sent( job )
	Proto.SendAck( job.ack_dest, job.umid )
end

---------------------------------------------------------------------------
function Proto.handlers.WHISPER.A1( job, sender )
	if not Proto.IsHosting( true ) then
		-- likely a logical error
		Me.DebugLog( "Ignored A1 message because we aren't hosting." )
		return
	end
	local umid, dest = job.text:match( "^A1 (%S+) (%a*%d+[AH])" )

	if not dest then
		return false
	end
	
	local secure = job.prefix ~= ""
	if secure then
		if Proto.secure_channel ~= job.prefix then
			-- not listening to this secure channel.
			Me.DebugLog( "Couldn't send A1 message because of secure mismatch." )
			Proto.BroadcastStatus( sender )
			return false
		end
	end
	
	local link = Proto.SelectLink( dest, secure )
	if not link then
		-- todo: respond to requester.
		Proto.BroadcastStatus( sender )
		return false
	end
	
	Proto.SendBnetMessage( link, { "A2", umid, dest }, secure, "FAST" )
end

---------------------------------------------------------------------------
function Proto.handlers.BNET.A2( job, sender )
	if not Proto.IsHosting( true ) then
		-- likely a logical error
		Me.DebugLog( "Ignored A2 message because we aren't hosting." )
		return
	end
	local umid, dest = job.text:match( "^A2 (%S+) (%a*%d+[AH])" )
	if not dest then return end
	
	if dest:lower() == Proto.my_dest:lower() then
		-- this message is for us.
		Proto.OnAckReceived( umid )
	else
		local send_to = Proto.DestToFullname( dest )
		if not send_to then return end
		-- we can broadcast to secure channels we aren't listening to
		local job = Me.Comm.SendAddonPacket( send_to, nil, true, "A3 " .. umid, job.prefix, "FAST" )
	end
end

---------------------------------------------------------------------------
function Proto.handlers.WHISPER.A3( job, sender )
	local umid = job.text:match( "^A3 (%S+)" )
	if not umid then return end
	Proto.OnAckReceived( umid )
end

---------------------------------------------------------------------------
function Proto.handlers.BNET.R2( job, sender )
	if not job.skip_r3_for_self then
		if not job.forwarder then
			local umid, flags, source, dest_name, dest_band, message_data = job.text:match( "^R2 (%S+) (%S+) (%a+%d+[AH]) (%a*)(%d+[AH]) (.+)" )
			if not dest_name then return false end
			
			local destination = dest_name .. dest_band
			
			if destination:lower() == Proto.my_dest:lower() then
				-- we are the destination. Don't need R3 message.
				job.skip_r3_for_self = true
			else
				-- don't forward if we aren't hosting.
				if not Proto.IsHosting( true ) then
					-- likely a logical error
					Me.DebugLog( "Ignored R2 message because we aren't hosting." )
					return
				end
				
				local send_to
				if dest_name ~= "" then
					send_to = Proto.DestToFullname( destination )
				else
					send_to = "*"
				end
				
				job.forwarder = Me.Comm.SendAddonPacket( send_to )
				if flags:find("G") then
					job.forwarder:SetSentCallback( Proto.OnR3Sent )
					job.forwarder.umid     = umid
					job.forwarder.ack_dest = source
				end
				job.forwarder:SetPrefix( job.prefix )
				job.forwarder:SetPriority( job.prefix ~= "" and "FAST" or "LOW" )
				job.forwarder:AddText( job.complete, ("R3 %s %s %s"):format( umid, source, message_data ))
				job.text = ""
			end
		else
			job.forwarder:AddText( job.complete, job.text )
			job.text = ""
		end
	end
	
	if job.skip_r3_for_self then
		
		local umid, flags, source, message_data = job.text:match( "^R2 (%S+) (%S+) (%a+%d+[AH]) %a*%d+[AH] (.+)" )
		-- handle message.
		if flags:find("G") then
			Proto.SendAck( source, umid )
		end
		Proto.OnMessageReceived( source, umid, message_data, job )
	end
end

-------------------------------------------------------------------------------
-- Whisper Packet Handlers
-------------------------------------------------------------------------------
function Proto.handlers.WHISPER.R0( job, sender )
	-- R0 <message>
	local message = job.text:sub(4)
	Proto.OnMessageReceived( Proto.DestFromFullname(sender, Me.faction), nil, message, job )
end;
-------------------------------------------------------------------------------
function Proto.handlers.WHISPER.R1( job, sender )
	if not Proto.IsHosting( true ) then
		-- likely a logical error
		Me.DebugLog( "Ignored R1 message because we aren't hosting." )
		return
	end
	
	if not job.forwarder then
		local umid, flags, destination, message_data = job.text:match( "^R1 (%S+) (%S+) (%a*%d+[AH]) (.+)" )
		if not destination then
			Me.DebugLog( "Bad R1 message." )
			return false
		end
		
		local secure = job.prefix ~= ""
		if secure then
			if Proto.secure_channel ~= job.prefix then
				-- can't forward secure channels that we aren't currently on
				Me.DebugLog( "Couldn't send R1 message because of secure mismatch." )
				Proto.BroadcastStatus( sender )
				return false
			end
		end
		
		local link = Proto.SelectLink( destination, secure )
		if not link then
			-- No link. send the requester our status so they dont do this again.
			Proto.BroadcastStatus( sender )
			return false
		end
		
		job.forwarder = Me.Comm.SendBnetPacket( link )
		job.forwarder:SetPrefix( job.prefix )
		job.forwarder:SetPriority( job.prefix ~= "" and "FAST" or "LOW" )
		
		local source = Proto.DestFromFullname( sender, flags:sub(1,1) )
		job.forwarder:AddText( job.complete, ("R2 %s %s %s %s %s"):format( umid, flags, source, destination, message_data ))
		job.text = ""
	else
		job.forwarder:AddText( job.complete, job.text )
		job.text = ""
	end
end;
-------------------------------------------------------------------------------
function Proto.handlers.WHISPER.R3( job, sender )
	
	local umid, source, message = job.text:match( "^R3 (.+) (%a+%d+[AH]) (.+)" )
	if not source then return false end
	
	Proto.OnMessageReceived( source, umid, message, job )
end

-------------------------------------------------------------------------------
Proto.handlers.BROADCAST.R3 = Proto.handlers.WHISPER.R3
Proto.handlers.BROADCAST.R0 = Proto.handlers.WHISPER.R0
Proto.handlers.WHISPER.ST   = Proto.handlers.BROADCAST.ST

-------------------------------------------------------------------------------
-- todo: on logout, let everyone know.

function Proto.TouchUnitBand( unit )
	local band = Proto.GetBandFromUnit( unit )
	if not band then return end
	
	if not Proto.IsDestLocal( band ) then
		band = Proto.GetLinkedBand( band )
		Proto.active_bands[band] = GetTime()
	end
end

-------------------------------------------------------------------------------
-- hooks
function Proto.OnMouseoverUnit()
	Proto.TouchUnitBand( "mouseover" )
end

-------------------------------------------------------------------------------
function Proto.OnTargetUnit()
	Proto.TouchUnitBand( "target" )
end

-------------------------------------------------------------------------------
function Proto.OnMessageReceived( source, umid, text, job )
	if umid then
		local sumid = source .. "-" .. umid
		local seen = Proto.seen_umids[sumid]
		if seen and GetTime() < seen + 60*10 then
			-- we might get duplicate messages if they are resent due to network
			--  problems, and we only process them once.
			Me.DebugLog2( "Ignoring duplicate UMID." )
			return
		end
		Proto.seen_umids[sumid] = GetTime()
	end
	
	Me.DebugLog2( "Proto Msg", job.complete, source, text )
	local command = text:match( "^%S+" )
	if not command then return end
	if job.prefix ~= "" and Proto.secure_channel ~= job.prefix then
		Me.DebugLog2( "Got secure message, but we aren't listening to it." )
		return
	end
	
	local handler = Proto.message_handlers[command]
	if handler then
		handler( source, text, job.complete )
	end
end

-------------------------------------------------------------------------------
function Proto.SetMessageHandler( command, handler )
	Proto.message_handlers[command] = handler
end
