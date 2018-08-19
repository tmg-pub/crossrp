-------------------------------------------------------------------------------
-- Club Message
-- by Tammya-MoonGuard (© 2018)
--
-- Redistribution and use in source and binary forms, with or without 
-- modification, are permitted provided that the following conditions are met:
--
-- 1. Redistributions of source code must retain the above copyright notice, 
-- this list of conditions and the following disclaimer.
--
-- 2. Redistributions in binary form must reproduce the above copyright 
-- notice, this list of conditions and the following disclaimer in the 
-- documentation and/or other materials provided with the distribution.
--
-- 3. Neither the name of the copyright holder nor the names of its 
-- contributors may be used to endorse or promote products derived from this
-- software without specific prior written permission.
-------------------------------------------------------------------------------
-- This is a simple library to fetch data from community descriptions.
-- Basically, you can fetch info from any community if you have a ticket for 
--  it, so this is essentially a new way to distribute custom data to your
--  addon from an external source.
-- You create a community, enter what data you want into the group description,
--  share a permanent invite link with your addon release, and then you can 
--  request it any time, and if you update the community "description", your 
--  addon gets the updated data. Great for MOTDs, version numbers, etc.
-- The Battle.net client allows 500-character group descriptions. WoW ingame
--  only lets you input 250. I'm pretty sure the "ingame", faction-based groups
--  can also be fetched by anyone, regardless of faction. They can't join, but
--  they can still read about it.
-- One major caveat (for addons with large userbases) is that communities are
--  region-based, so you would need region detection in the addon to pick the
--  right invite code (tricky!), and multiple communities set up for each 
--  region you want to serve. Keep in mind that GetCurrentRegion just 
--  references a number hardcoded into the client, and may not reflect the
--  actual region the user is connected to. A safe way to get the region is
--  LibRealmInfo.
-- 
-- The main function to request data is:
--   LibClubMessage.Request( invite_code, callback )
--
-- The API documentation is at the bottom of the file, under PUBLIC API.
-------------------------------------------------------------------------------
-- ClubMessage library revision.
local VERSION = 1
-------------------------------------------------------------------------------
-- Only allow this many requests per second per ticket ID. If another request
--  for the same ticket is made within this period, then we just return the
--  cached data; otherwise we can make another request and refresh the cache.
local REQUEST_COOLDOWN = 10
-------------------------------------------------------------------------------
-- How long to wait for the server response before we give up and allow new
--  requests.
local REQUEST_TIMEOUT  = 20
-------------------------------------------------------------------------------
-- How fast we can make requests. For example if three different requests are 
--  made at once, then the first will be instant and the latter two will be
--  made in a delayed sequence.
local REQUEST_PERIOD = 0.2
-------------------------------------------------------------------------------
-- LibClubMessage is the public API. Internal is our "private" namespace to
--  work in (Me).
if not LibClubMessage then
	LibClubMessage = {}
	LibClubMessage.Internal = {}
end
-------------------------------------------------------------------------------
local Me = LibClubMessage.Internal
local Public = LibClubMessage
-------------------------------------------------------------------------------
if Me.version >= VERSION then
	-- Already have a newer or existing version loaded; cancel.
	Me.load = false
	return
else
	-- Save old version so any sub files can reference it and make upgrades.
	Me.old_version = Me.version
	-- Me.load is a simple switch for sub files to continue loading or not. If
	--  it's false then it means we're up-to-date and any sub files should exit
	--  out immediately.
	Me.load = true
end

-------------------------------------------------------------------------------
Me.version = VERSION
--
-- << Do upgrades here for anything that needs it. >>
--
-------------------------------------------------------------------------------
-- Our main controller frame. Currently just listens to the ticket event. This
--  is triggered when the client receives data from the club server regarding
--  a ticket request, paired with each call to C_Club.RequestTicket().
-- It will trigger multiple times if multiple calls are made, even if the
--                                  ticket is the same or a duplicate request.
Me.frame = Me.frame or CreateFrame( "Frame" )
Me.frame:UnregisterAllEvents()
Me.frame:RegisterEvent( "CLUB_TICKET_RECEIVED" )
Me.frame:SetScript( "OnEvent", function( self, event, ... )
	if Me.Events[event] then
		Me.Events[event]( ... )
	end
end)
Me.Events = Me.Events or {}
-------------------------------------------------------------------------------
-- This is our list of active requests or cached request results, indexed by
--  a ticket ID. Inner table data is as follows:
--     waiting: A request has been made and we're waiting for the server.
--     info: The ClubInfo data that was received. Nil if there was an error.
--     result_code: The error code for the last request, from 
--                   Enum.ClubErrorType. If the request fails but we already 
--                   have the result from a previous successful request, then 
--                   the error is ignored and the previous data is used.
--     callbacks: A list of callbacks that are waiting for data to be resolved.
--     time: The time this request was made OR satisfied (request time set
--            first, and then the satisfy time set after the event).
Me.requests = Me.requests or {}

Me.outgoing_tickets = Me.outgoing_tickets or {}
--[[
-------------------------------------------------------------------------------
function Me.TriggerCallback( callback, request_data )
	if not callback then return end
	local desc = ""
	if request_data.info then
		desc = request_data.info.description or ""
	end
	callback( desc, request_data.result_code, request_data.info )
end]]

-------------------------------------------------------------------------------
-- Trigger all callbacks for a request and then wipe the callback list.
--
function Me.TriggerCallbacks( request )
	if not request.callbacks then return end
	
	local desc = ""
	if request.info then
		desc = request.info.description or ""
	end
	
	for callback, _ in pairs( request.callbacks ) do
		callback( desc, request.result_code, request.info, request.ticket )
	end
	
	wipe( request.callbacks )
end

-------------------------------------------------------------------------------
-- Event when we receive club information from the server (or an error code).
--  This is fired once per call to C_Club.RequestTicket. AFAIK this always
--  triggers, even if the ticket code is invalid or expired; `club_info` will
--  be nil in those cases.
--
function Me.Events.CLUB_TICKET_RECEIVED( error_code, ticket, club_info )
	local request = Me.requests[ticket]
	if request and request.waiting then
		request.waiting = false
		request.time    = GetTime()
		if error_code == Enum.ClubErrorType.ErrorCommunitiesNone then
			request.info = club_info
		end
		request.result_code = error_code
		Me.TriggerCallbacks( request )
	end
end

-------------------------------------------------------------------------------
-- Simple queue system to split up ticket requests.
--
function Me.QueueRequest( ticket )
	table.insert( Me.outgoing_tickets, ticket )
	
	-- Only want one "thread" emptying the queue.
	if Me.queue_started then return end
	Me.ContinueQueue()
end

-------------------------------------------------------------------------------
-- Start or continue emptying the ticket queue. Runs every REQUEST_PERIOD
--  seconds when the queue is active with tickets waiting to be sent.
function Me.ContinueQueue()
	if not Me.queue_started then return end
	if #Me.outgoing_tickets == 0 then
		Me.queue_started = nil
		return
	end
	
	-- If for whatever reason RequestTicket throws an error, we'll still be
	--  in a good state by doing this stuff before it.
	C_Timer.After( REQUEST_PERIOD, Me.ContinueQueue )
	local ticket = Me.outgoing_tickets[1]
	table.remove( Me.outgoing_tickets, 1 )
	
	C_Club.RequestTicket( ticket )
end

-------------------------------------------------------------------------------
-- Returns false if the waiting flag for a request is not set, or if the 
--  request has timed out.
function Me.RequestInProgress( request )
	if request.waiting then
		return GetTime() < (request.time + REQUEST_TIMEOUT)
	end
	return false
end

-------------------------------------------------------------------------------
-- Request the server for club information, and call the callback when it's
--  received. If called within a short period since the last request, it will
--  just used the cached data.
-- Returns true if a request is being made from the server.
--
function Me.Request( ticket, callback )
	local rq = Me.requests[ticket]
	if not rq then
		rq = { ticket = ticket }
		Me.requests[ticket] = rq
	end
	
	if callback then
		rq.callbacks = rq.callbacks or {}
	
		-- We store callbacks as keys, so there aren't any duplicates. Some 
		--  side effects are that callbacks are called randomly, but that 
		--  shouldn't matter. Most of the time you're only going to have one 
		--  callback anyway.
		-- Desired behavior is that even if you call this function multiple 
		--  times with the same callback, it'll only trigger once. If you call
		--           it with different callbacks, then each will trigger once.
		rq.callbacks[callback] = true
	end
	
	-- Cancel if we're already waiting for the server to satisfy a request. The
	--  callback added will be triggered right when the server responds.
	if Me.RequestInProgress( rq ) then return true end
	
	if rq.time and rq.time < GetTime() + REQUEST_COOLDOWN then
		-- We already made a request very recently, so just execute the
		--  callback with what we have. We do this on the next frame to not run
		--  through this execution path. Some addons might expect the handler
		--                                     to not run inside of their call.
		if callback then
			C_Timer.After( 0, function()
				Me.TriggerCallbacks( rq )
			end)
		end
		return false
	end
	
	rq.waiting = true
	rq.time    = GetTime()
	
	-- This requests data from the server. As far as I can tell, there's no
	--  limit to how many requests you can make per second. As of writing I've
	--  tested sending about 1000 requests and they all came back at the same 
	--  time. That cannot be what the devs planned, because the club info can 
	--  be around the same size as a message, and those are limited to around 
	--                                          50 requests per 2 minutes!
	Me.QueueRequest( ticket )
	
	return true
end

-------------------------------------------------------------------------------
-- Gets existing data from a previous request. Does not make a server request.
--
function Me.Read( ticket )
	local rq = Me.requests[ticket]
	local desc       = ""
	local has_desc   = false
	local club_info  = nil
	local last_error = nil
	
	-- If the request hasn't been made yet, then we basically return all empty
	--  data, "", false, nil, nil. Basically pick and choose what is valid
	--  data and then overwrite the empty values.
	if rq then
		if rq.info then
			desc = rq.info.description or ""
			has_desc  = true
			club_info = rq.info
		end
		last_error = rq.result_code
	end
	
	-- Should make sure that these have at least a little semblance to what
	--  arguments the Request callbacks have. Order by usefulness, desc is most
	--  important/used, followed by other info that typically has less use.
	return desc, has_desc, club_info, last_error
end


-------------------------------------------------------------------------------
-- PUBLIC API
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Request( ticket, callback )
-- 
-- Makes a request to the server for community information. The `ticket` is the
--  invite code (e.g. "owr2pVGunyM"), which should ideally be a permanent link
--  to the community that you want to read the description of/request data
--  from.
-- If called within a short period since the last request, it will just used 
--  the cached data. If you want to just READ the data and not request it again
--  use the `Read` method. When using cached data, the callback is triggered on
--  the next frame, i.e. not in the current execution path.
-- Returns true if a request is being made from the server.
--
-- Callback signature is `(description, error_code, club_info, ticket)`
--   description  Description of the club/community that the ticket is for.
--                 This will always be a string, and if the attempt to get the
--                 club info was unsuccessful, this will be an empty 
--                 string ("").
--   error_code   Error code for request. 0 is no error, otherwise it is a code
--                 from Enum.ClubErrorType.
--   club_info    The raw club info from the request. Contains things like the
--                 description, number of players in the community, community
--                 name, etc. May be `nil` for errors. Will not be `nil` if a
--                 previous request was successful (it will have the last
--                 value cached).
--   ticket       The ticket string that was used for this request.
--   
Public.Request = Internal.Request

-------------------------------------------------------------------------------
-- description, has_description, club_info, last_error = Read( ticket )
--
-- Reads data from the cache (data is retrieved using `Request`). `ticket` is
--  an invite code (e.g. "owr2pVGunyM"). Returns empty data if you haven't
--  made a request yet.
--
-- Returns:
-- [1] Description - The community description. Will always be a string, and an
--      empty string on error.
-- [2] Has Description - True if the description is valid and from a request;
--      false if the description hasn't been requested yet, or if there was an 
--      error.
-- [3] Club Info - The full community info from the last successful request.
--      This is of the ClubInfo type (from Blizzard's documentation). Keep in 
--      mind that some of the fields in here may not be set, as the data the
--      server provides is a subset of the full ClubInfo that you can get when
--      inside the community.
-- [4] Last Error - The error code from the last request made. 0 is no error.
--      Matches Enum.ClubErrorType
-- 
Public.Read = Internal.Read
