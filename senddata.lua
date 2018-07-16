-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- Our protocol for sending large data over the relay channel.
-------------------------------------------------------------------------------
local _, Me         = ...
-------------------------------------------------------------------------------
-- API use:
-- Pick some unique tags that you will use to label your data types,
--  e.g. TRPD1, TRPD2 the TRP3 module uses.
--
-- Set `Me.DataHandlers[TAG]` to your handler. This is called when you receive
--  a whole message. Signature is `function( tag, user, istext, data )`.
--
-- Optionally, also set `Me.DataProgressHandlers[TAG]` to your data progress
--  handler. This is called when you receive each page of a message. Signature
--  is `function( tag, user, pages, pagecount )`.
--
-- Use `SendData( TAG, DATA )` for transferring a binary string or a table.
-- Use `SendTextData( TAG, TEXT )` for text transfers.
--
-------------------------------------------------------------------------------
-- The maximum amount of text that we'll send in a single packet. This can be
--  as high as 4000-ish with the chat system, but sending messages that big
--  can pound the client on the opposite side when they receive the message
--  and its visible somewhere. It /shouldn't/ be visible anywhere, but if it is
--  and they have a lower-end computer, it can potentially make them lock up
--  for seconds. We'll keep it within a managable level. Plus, we don't know
--  if server logs limits are per-line or per-byte, and this way will cut our
local MAX_PAYLOAD = 2000                     --  big-data footprint in half.
-------------------------------------------------------------------------------
-- PROTOCOL
-- Large Data Message Example:
--         cc1A Tammya-MoonGuard LEN:DATA:TRPD1:0:1F:1:3 PAYLOAD...
--                                |   |    |    | |  | |    |
--     BYTE LENGTH OF PAYLOAD-----'   |    |    | |  | |    |
--                     "DATA"---------'    |    | |  | |    |
--         TAG / MESSAGE TYPE--------------'    | |  | |    |
--                   ENCODING-------------------' |  | |    |
--             MESSAGE SERIAL---------------------'  | |    |
--                PAGE NUMBER------------------------' |    |
--                TOTAL PAGES--------------------------'    |
--                  PAGE DATA-------------------------------'
--
-- ENCODING: What kind of data is being transferred.
--             0 = Plain text.
--             1 = Base64 encoded binary.
--             2 = Base64 encoded serialized table.
-- MESSAGE SERIAL: Semi-unique (will wrap around) per message for queueing 
--                 purposes. Hexcode.
-- PAGE NUMBER: What page you're currently getting. One page is sent per
--               packet. Max page size is `MAX_PAYLOAD`.
-- TOTAL PAGES: The total number of pages in this transfer. You should receive
--               pages 1-TOTAL.
-- PAGE DATA: Data encoded according to SERIALIZED.
--
-------------------------------------------------------------------------------
-- Buffer for data transfers. Indexed by username and message serial.
--   [user][serial] = { time, pages }
Me.data_queue = {}
-------------------------------------------------------------------------------
-- Data handlers are called after we're done with a complete data transfer.
-- To insert a handler:
-- DataHandlers[TAG] = function( user, tag, istext, data )
-- TAG/tag: The tag passed to SendData.
-- user:    User information, in our common user table format.
-- istext:  True if this message wasn't encoded or serialized.
-- data:    The entire data payload, may be a table if it was encoded.
Me.DataHandlers         = Me.DataHandlers or {}
-------------------------------------------------------------------------------
-- Data progress handlers let you know that a transfer is in progress.
-- DataProgressHandlers[TAG] = function( user, tag, pages, pagecount )
-- TAG/tag: The tag passed to SendData.
-- user:    User information, in our common user table format.
-- pages:   How many pages of this transfer have been received so far.
-- pagecount: How many pages are expected in total.
Me.DataProgressHandlers = Me.DataProgressHandlers or {}
-------------------------------------------------------------------------------
-- The next serial number we'll use for a transfer. This is wrapped 0-4095.
Me.data_serial = 0

-------------------------------------------------------------------------------
-- Queue a data transfer.
-- tag: Tag for this data. What type of data it is.
-- msg: Data payload. May be plain text, binary, or a table.
-- pack: True to pack the data. This must be set if `msg` is binary or a table.
--
local function QueueData( tag, msg, txt )
	local encoding = "0"
	
	-- Encoding level:
	-- 0 = None/Plain Text
	-- 1 = Ace Encoded Text (for text)
	-- 2 = Ace Encoded Table (for text)
	-- 3 = Base64 Encoded Text (for binary)
	-- 4 = Ace+Base64 Encoded Table (for binary)
	
	if type(msg) == "table" then
		msg = Me.Serializer:Serialize( msg )
		if txt then
			encoding = "2"
		else
			encoding = "4"
			msg = Me.ToBase64( msg )
		end
	else
		if txt then
			encoding = "1"
			msg = Me.Serializer:EscapeString( msg )
		else
			encoding = "3"
			msg = Me.ToBase64( msg )
		end
	end
	
	local pages = {}
	
	-- Split up message. This is "off-by-one hell."
	local startpoint = 1
	while true do
		if #msg - (startpoint-1) > MAX_PAYLOAD then
			local splitpoint = startpoint + MAX_PAYLOAD
			
			-- We need to find a valid split point. If we aren't sending
			--  valid UTF-8, our message might be silently discarded.
			for i = 1,16 do
				if i == 16 then return end -- Invalid input.
				
				local ch = msg:byte( splitpoint )
				if ch >= 32 and ch <= 128 or ch >= 192 then
					-- Normal ASCII or valid UTF-8 start character.
					break
				end
				splitpoint = splitpoint - 1
			end
			
			-- We insert the data from `startpoint` to `splitpoint-1`, and
			--  `splitpoint` points to the character that starts off the next
			--  piece.
			table.insert( pages, msg:sub( startpoint, splitpoint-1 ))
			startpoint = splitpoint
		else
			table.insert( pages, msg:sub( startpoint ))
			break
		end
	end
	
	-- Send all packets, low priority. Each page has its own packet.
	for k, v in ipairs( pages ) do
		Me.SendPacketLowPrio( "DATA", v,  tag, encoding, 
		                             ("%X"):format(Me.data_serial), k, #pages )
	end
	Me.data_serial = (Me.data_serial + 1) % 4096
end

-------------------------------------------------------------------------------
-- Start a data transfer.
-- tag: What handler will receive this message.
-- msg: Binary data or a table.
--
function Me.SendData( tag, msg )
	QueueData( tag, msg, false )
end

-------------------------------------------------------------------------------
-- Start a text data transfer.
-- tag: What handler will receive this message.
-- msg: Plain text.
--
function Me.SendTextData( tag, msg )
	QueueData( tag, msg, true )
end

-------------------------------------------------------------------------------
-- Get or create a user's queue.
--
local function GetDataQueue( username )
	local queue = Me.data_queue[username]
	if not queue then
		queue = {}
		Me.data_queue[username] = queue
	end
	return queue
end

-------------------------------------------------------------------------------
-- Packet handler for our core protocol.
--
function Me.ProcessPacket.DATA( user, command, msg, args )
	if not user.connected then
		-- We don't have any use for unconnected data messages.
		return
	end
	
	local tag, encoding, serial, page, pagecount 
	                              = args[3], args[4], args[5], args[6], args[7]
	if not pagecount then return end
	local queue = GetDataQueue( user.name )
	
	-- Sanitize and check.
	page      = tonumber(page)
	pagecount = tonumber(pagecount)
	serial    = tonumber(serial, 16)
	if not page or not pagecount or not serial then return end
	
	local qs = queue[serial]
	if not qs or (GetTime() - qs.time > 30) then
		-- If this queue gets untouched for 30 seconds, then we reset it. We 
		--  also create it if it doesn't exist.
		qs = {
			pages = {}
		}
		queue[serial] = qs
	end
	
	qs.time = GetTime()
	qs.pages[page] = msg
	
	for i = 1, pagecount do
		if not qs.pages[i] then
			-- In rare cases, we might actually have more pages than we report,
			--  due to a data ordering problem. Not guaranteed to receive
			--                             messages in a proper order.
			Me.ReceiveDataProgress( user, tag, i-1, pagecount )
			return
		end
	end
	
	-- Concatenate. TODO: can this be replaced with a single table.concat?
	local final_message = ""
	for i = 1, pagecount do
		final_message = final_message .. qs.pages[i]
	end

	-- Delete this set from our buffer.
	queue[serial] = nil
	
	encoding = tonumber( encoding )
	if encoding == 1 then
		final_message = Me.Serializer:UnescapeString( final_message )
	elseif encoding == 2 then
		local good
		good, final_message = Me.Serializer:Deserialize( final_message )
		if not good then return end
	elseif encoding == 3 then
		final_message = Me.FromBase64( final_message )
	elseif encoding == 4 then
		local good
		final_message = Me.FromBase64( final_message )
		good, final_message = Me.Serializer:Deserialize( final_message )
		if not good then return end
	end
	
	-- Pass to handler.
	Me.ReceiveData( user, tag, encoding, final_message )
end

-------------------------------------------------------------------------------
-- Helper to pass to our handlers.
--
function Me.ReceiveData( user, tag, encoding, data )
	if Me.DataHandlers[tag] then
		Me.DataHandlers[tag]( user, tag, encoding, data )
	end
end

-------------------------------------------------------------------------------
-- Helper to pass to our progress handlers.
--
function Me.ReceiveDataProgress( user, tag, pages, pagecount )
	if Me.DataProgressHandlers[tag] then
		Me.DataProgressHandlers[tag]( user, tag, pages, pagecount )
	end
end
