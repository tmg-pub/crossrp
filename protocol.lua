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
	secure_code    = nil;
	secure_channel = nil;
	secure_hash    = nil;
	secure_myhash  = nil;
	
	do_status_request       = true;
	next_status_broadcast   = 0;
	status_broadcast_urgent = false;
	status_last_sent_empty  = false;
	
	registered_addon_prefixes = {};
	
	my_dest    = nil;
	my_band    = nil;
	my_realmid = nil;
	
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
	first_status_time = nil;
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
	local name, realm = dest:match( "([A-Za-z]+)(%d+)" )
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
	for dist, set in pairs( Proto.handlers ) do
		for command, handler in pairs( set ) do
			Me.Comm.SetMessageHandler( dist, command, handler )
		end
	end
	Proto.handlers = nil
	
	Proto.my_dest = Proto.DestFromFullname( Me.fullname, Me.faction )
	Proto.my_band = Proto.GetBandFromDest( Proto.my_dest )
	
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
	Proto.start_time = GetTime()
	if not Me.db.char.proto_crossrp_channel_added then
		Me.db.char.proto_crossrp_channel_added = true
		ChatFrame_AddChannel( DEFAULT_CHAT_FRAME, Proto.channel_name )
	end
	C_ChatInfo.RegisterAddonMessagePrefix( "+RP" )
	--Proto.SetSecure( 'henlo' ) -- debug
	Me.DebugLog2( "Proto Start" )
	-- because start hosting might not work if their battlenet is down:
	Proto.next_status_broadcast = 0
	
	Me:SendMessage( "CROSSRP_PROTO_START" )
	
	Proto.StartHosting()
	Proto.Update()
end

function Proto.PostStatusInitialization()
	Me.DebugLog2( "Post Status Initialization." )
	Proto.post_status_init = true
	Me:SendMessage( "CROSSRP_POST_STATUS_INIT" )
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
			Proto.next_status_broadcast = 0
			Proto.status_broadcast_urgent = true
		end
	end
	
	Proto.PurgeOfflineLinks( false )
	
	local time = GetTime()
	-- give a few seconds after the proto start for things to initialize
	-- such as the RPCHECK message getting a response. otherwise we're gonna
	-- be sending out two status messages.
	if time > Proto.next_status_broadcast and time > Proto.start_time + 2.0 then
		if Proto.hosting then
			Proto.next_status_broadcast = time + 120 -- debug value
			Proto.BroadcastStatus()
			Proto.PingLinks()
		elseif Proto.do_status_request then
			Proto.BroadcastStatus()
		end
	end
	
end

-------------------------------------------------------------------------------
function Proto.PurgeOfflineLinks( run_update )
	for gameid,_ in pairs( Proto.link_ids ) do
		local _, charname, _, realm, _, faction = BNGetGameAccountInfo( gameid )
		if not charname or charname == "" then
			Proto.RemoveLink( gameid )
		end
	end
	
	if Proto.next_status_broadcast == 0 then
		Proto.status_broadcast_urgent = true
		if run_update then
			Proto.Update()
		end
	end
end

-------------------------------------------------------------------------------
function Proto.OnBnFriendInfoChanged()
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
	Proto.next_status_broadcast = 0
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
		if not Proto.warned_bnet_down then
			Proto.warned_bnet_down = true
			Me.DebugLog2( "Battle.net is down for this session. Cannot host." )
		end
		return
	end
	
	local my_faction = UnitFactionGroup( "player" )
	
	Proto.hosting = true
	Proto.hosting_time = GetTime()
	--Proto.next_status_broadcast = GetTime() + 5
	Proto.next_status_broadcast = GetTime() + 2 -- debug bypass
	
	local send_to = {}
	for charname, faction, game_account in Proto.FriendsGameAccounts() do
		local realm = charname:match( "%-(.+)" )
		if realm ~= Me.realm or faction ~= my_faction then
			send_to[game_account] = true
		end
	end
	
	Proto.SendHI( send_to, true, 5 )
end

-------------------------------------------------------------------------------
function Proto.PingLinks()
	local send_to = {}
	for k, v in pairs( Proto.links ) do
		for gameid, _ in pairs( v.nodes ) do
			if not send_to[gameid] then
				send_to[gameid] = true
			end
		end
	end
	Proto.SendHI( send_to, false )
end

-------------------------------------------------------------------------------
function Proto.SendHI( gameids, request, load_override )
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
		     {"HI", Me.version, request_mode, load, short_passhash, passhash}, false, "LOW" )
		job.tags = {"hi"}
	end
end

-------------------------------------------------------------------------------
function Proto.StopHosting()
	if not Proto.hosting then return end
	Proto.hosting = false
	Proto.BroadcastStatusOff()
	
	Me.Comm.CancelSendByTag( "hi" )
	Proto.PingLinks()
	--for id, _ in pairs( send_to ) do
	--	Proto.SendBnetMessage( id, "BYE", false, "LOW" )
	--end
end

-------------------------------------------------------------------------------
function Proto.BroadcastStatusOff()
	if Proto.hosting then
		error( "Shouldn't call this while hosting." )
	end
	
	Me.Comm.CancelSendByTag( "st" )
	local job = Proto.SendAddonMessage( "*", "ST -", false, "LOW" )
	job.tags = {"st"}
end

-------------------------------------------------------------------------------
function Proto.BroadcastStatus( target )
	if not Proto.first_status_time then
		Proto.first_status_time = GetTime()
		Me.Timer_Start( "proto_status_wait", "ignore", 3.0, Proto.PostStatusInitialization )
	end
	
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
	
	
	bands = table.concat( bands, " " )
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
			       false, Proto.status_broadcast_urgent and "URGENT" or "NORMAL" )
	job.tags = {"st"}
	Proto.status_broadcast_urgent = false
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



-------------------------------------------------------------------------------
-- destinations can be
-- local: to local crossrp channel
-- all: to all crossrp channels we can reach
-- active: to all "touched" crossrpchannels we can reach
-- <band>: to the crossrp channel for this band
-- <user><band>: to this specific user
-- <user><myband>: local addon message (not implemented/used)
function Proto.Send( dest, msg, secure, priority )
	if secure and not Proto.secure_code then return end
	
	if type(msg) == "table" then
		msg = table.concat( msg, " " )
	end
	
	if dest == "local" then dest = Proto.my_band end
	
	if dest == "all" or dest == "active" then
		-- todo
		local send_to = { "local" }
		local time = GetTime()
		for k, v in pairs( Proto.bridges ) do
			if not v:Empty( secure and "secure" ) then
				local active = time < (Proto.active_bands[k] or 0) + BAND_TOUCH_ACTIVE
				if dest == "all" or (dest == "active" and active) then
					table.insert( send_to, k )
				end
			end
		end
		
		for k, v in ipairs( send_to ) do
			Proto.Send( v, msg, secure, priority )
		end
		return
	elseif Proto.IsDestLocal(dest) then
		-- this should be an r0, because this function is for forwarded messages that end up in a different handler.
		
		local localplayer = dest:match( "([A-Za-z]*)%d+[AH]" )
		local target
		
		if localplayer ~= "" then
			target = Proto.DestToFullname( dest )
		else
			target = "*"
		end
		
		Proto.SendAddonMessage( target, {"R0", msg}, secure, priority )
		return
	end
	
	-- Find a bridge.
	local bridge = Proto.SelectBridge( dest )
	if not bridge then
		-- No available route.
		return
	end
	
	if bridge == Me.fullname then
		local link = Proto.SelectLink( dest )
		if not link then
			-- No link.
			-- in the future we might reply to the user to remove us as a bridge?
			return
		end
		Proto.SendBnetMessage( link, {"R2", Proto.my_dest, dest, msg}, secure, priority )
	else
		-- todo, bypass this for self (but it should work both ways)
		-- VV R1 F DEST MESSAGE
		Proto.SendAddonMessage( bridge, {"R1", Me.faction, dest, msg}, secure, priority )
	end
end

-------------------------------------------------------------------------------
function Proto.SelectBridge( destination )
	local band = destination:match( "[A-Za-z]*(%d+[AH])" )
	if not band then error( "Invalid destination." ) end
	band = Proto.GetLinkedBand( band )
	local bridge = Proto.bridges[band]
	if not bridge then return end
	return bridge:Select()
end

-------------------------------------------------------------------------------
function Proto.SelectLink( destination )
	local user, band = destination:match( "([A-Za-z]*)(%d+[AH])" )
	if not band then error( "Invalid destination." ) end
	band = Proto.GetLinkedBand( band )
	local link = Proto.links[band]
	if not link then return end
	
	if user ~= "" then
		-- if user is set, try to get a direct link to that user.
		local direct = link:HasBnetLink( destination )
		if direct then return direct end
	end
	
	return link:Select()
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
	
	realm = realm:gsub( "%s*%-*", "" )
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
	
	Proto.links[band]:Add( gameid, load, subset )
	
	Proto.UpdateSelfBridge()
end

-------------------------------------------------------------------------------
function Proto.RemoveLink( gameid )
	Me.DebugLog2( "Removing link.", gameid )
	for k, v in pairs( Proto.links ) do
		if v:Remove( gameid ) then
			Proto.next_status_broadcast = 0
			Proto.status_broadcast_urgent = true
		end
	end
	Proto.link_ids[gameid] = nil
	
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
	realm = realm:gsub( "[%s%-]", "" )
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
	
	if job.text == "ST -" then
		Proto.node_secure_data[sender] = nil
		Proto.RemoveBridge( sender )
		return
	end
	
	-- register or update a bridge.
	local version, request, secure_hash1, secure_hash2, bands = job.text:match( "ST (%S+) (%S) (%S+) (%S+) (.+)" )
	if not version then return end
	
	Proto.UpdateNodeSecureData( sender, secure_hash1, secure_hash2 )
	
	if bands == "-" then
		Proto.RemoveBridge( sender )
	else
		Proto.UpdateBridge( sender, bands )
	end
	
	if request == "?" then
		Me.DebugLog2( "status requets" )
		Proto.BroadcastStatus( sender )
	end
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
	
	
	Proto.UpdateNodeSecureData( sender, short_hash, personal_hash )
	
	if load > 0 then
		Proto.AddLink( sender, load )
	else
		Proto.RemoveLink( sender, load )
	end
	
	if request == "?" then
		Proto.SendHI( sender, false )
	end
end
	
---------------------------------------------------------------------------
--[[
function Proto.handlers.BNET.BYE( job, sender )
	if not job.complete then return end
	Proto.other_secure_hashes[sender] = nil
	Proto.other_secure_hashes_personal[sender] = nil
	Proto.RemoveLink( sender )
end]]

---------------------------------------------------------------------------
function Proto.handlers.BNET.R2( job, sender )
	if not job.skip_r3_for_self then
		if not job.forwarder then
			local source, dest_name, dest_band, message_data = job.text:match( "^R2 ([A-Za-z]+%d+[AH]) ([A-Za-z]*)(%d+[AH]) (.+)" )
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
				job.forwarder:SetPrefix( job.prefix )
				job.forwarder:SetPriority( "LOW" )
				job.forwarder:AddText( job.complete, "R3 " .. source .. " " .. message_data )
				job.text = ""
			end
		else
			job.forwarder:AddText( job.complete, job.text )
			job.text = ""
		end
	end
	
	if job.skip_r3_for_self then
		
		local source, message_data = job.text:match( "^R2 ([A-Za-z]+%d+[AH]) [A-Za-z]*%d+[AH] (.+)" )
		-- handle message.
		Proto.OnMessageReceived( source, message_data, job )
	end
end

-------------------------------------------------------------------------------
-- Whisper Packet Handlers
-------------------------------------------------------------------------------
function Proto.handlers.WHISPER.R0( job, sender )
	-- R0 <message>
	local message = job.text:sub(4)
	Proto.OnMessageReceived( Proto.DestFromFullname(sender, Me.faction), message, job )
end;
-------------------------------------------------------------------------------
function Proto.handlers.WHISPER.R1( job, sender )
	if not Proto.IsHosting( true ) then
		-- likely a logical error
		Me.DebugLog( "Ignored R1 message because we aren't hosting." )
		return
	end
	
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
		job.forwarder:SetPrefix( job.prefix )
		job.forwarder:SetPriority( "LOW" )
		local source = Proto.DestFromFullname( sender, faction )
		job.forwarder:AddText( job.complete, "R2 " .. source .. " " .. destination .. " " .. message_data )
		job.text = ""
	else
		job.forwarder:AddText( job.complete, job.text )
		job.text = ""
	end
end;
-------------------------------------------------------------------------------
function Proto.handlers.WHISPER.R3( job, sender )
	
	local source, message = job.text:match( "^R3 ([A-Za-z]+%d+[AH]) (.+)" )
	if not source then return false end
	
	Proto.OnMessageReceived( source, message, job )
end

-------------------------------------------------------------------------------
Proto.handlers.BROADCAST.R3 = Proto.handlers.WHISPER.R3
Proto.handlers.BROADCAST.R0 = Proto.handlers.WHISPER.R0
Proto.handlers.WHISPER.ST = Proto.handlers.BROADCAST.ST

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

function Proto.OnTargetUnit()
	Proto.TouchUnitBand( "target" )
end

function Proto.OnMessageReceived( source, text, job )
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
--[[
-------------------------------------------------------------------------------
function Proto.SetRawHandler( channel, command, handler )
	if channel == "BROADCAST" then
		Proto.BroadcastPacketHandlers[command] = handler
	elseif channel == "DIRECT" then
		Proto.WhisperPacketHandlers[command] = handler
	elseif channel == "BNET" then
		Proto.BnetPacketHandlers[command] = handler
	end
end]]
--[[
-------------------------------------------------------------------------------
function Proto.OnDataReceived( job, dist, sender )
	if job.proto_abort then return end
	Me.DebugLog2( "DATA RECEIVED", job.prefix, job.type, job.complete and "COMPLETE" or "PROGRESS", sender, job.text )
	
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
end]]
