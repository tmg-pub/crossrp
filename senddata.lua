
local _, Me = ...
local Serializer = LibStub:GetLibrary("AceSerializer-3.0");

local MAX_PAYLOAD = 2000

-- PROTOCOL:
-- binary message
-- DAT:TAG:S:P/N:DATA
--   TAG = Custom Tag
--   S = 0: plain text, 1 = base64 text, 2 = base64 serialized struct
--   P = page#
--   N = number of pages
--   DATA = page
-- text message
-- TXT:TAG:P/N:TEXT

Me.data_queue = {
	-- [user][tag] = { page, count, data }
}


-------------------------------------------------------------------------------
function Me.SendData( tag, msg )
	local serialized = "1"
	if type(msg) == "table" then
		serialized = "2"
		msg = Serializer:Serialize( msg )
	end
	
	msg = Me.ToBase64(msg)
	local pages = math.ceil(#msg / MAX_PAYLOAD)
	for i = 1, pages do
		Me.SendPacket( "DAT", tag, serialized, i, pages, msg:sub( 1 + (i-1)*MAX_PAYLOAD, i*MAX_PAYLOAD ))
	end
end

-------------------------------------------------------------------------------
function Me.SendTextData( tag, msg )
	local pages = math.ceil( #msg / MAX_PAYLOAD )
	for i = 1, pages do
		Me.SendPacket( "DAT", tag, "0", i, pages, msg:sub( 1 + (i-1)*MAX_PAYLOAD, i*MAX_PAYLOAD ))
	end
end	

-------------------------------------------------------------------------------
function Me.ProcessPacket.DAT( user, msg )
	local tag, serialized, page, pagecount, data = msg:match( "([^:]+):(%d):(%d+)/(%d+):(.*)" )
	if not tag then return end
	
	Me.data_queue[user] = Me.data_queue[user] or {}
	local queue = Me.data_queue[user]
	
	page = tonumber(page)
	pagecount = tonumber(pagecount)
	if page == 1 then
		queue[tag] = {
			page = 0;
			count = pagecount;
			data = "";
		}
	end
	
	if not queue[tag] then return end -- corrupt message
	local qt = queue[tag]
	if page ~= qt.page + 1 then 
		-- corrupt message
		queue[tag] = nil
		return 
	end 
	
	qt.data = qt.data .. data
	qt.page = page
	if qt.page == qt.pagecount then
		-- finished message.
		local finished = qt.data
		queue[tag] = nil
		
		serialized = tonumber(serialized)
		if serialized >= 1 then
			finished = Me.FromBase64( finished )
		end
		
		if serialized >= 2 then
			local good
			finished = Serializer:Unserialize( finished )
			if not good then return end -- corrupt message
		end
		
		Me.ReceiveData( user, tag, serialized == 0, finished )
	end
end

-------------------------------------------------------------------------------
function Me.ReceiveData( user, tag, istext, data )
	for k, v in ipairs( Me.DataHandlers ) do
		v( user, tag, istext, data )
	end
end
