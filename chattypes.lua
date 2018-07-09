-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- Our custom chat types /rp, /rpw, etc. We add them directly to the chat box
--  tables.
-------------------------------------------------------------------------------
local _, Me = ...
local L = Me.Locale

-------------------------------------------------------------------------------
-- Called after our chat settings change.
--
-- Chat Type hashes are what the chat system uses internally to see what sort 
--  of chat types exist. We can insert chat types into them, so that the chat
--  boxes will accommodate for our special/custom types ("/rp" etc.). We only
--  add entries that are enabled. If we aren't connected or if they're disabled
--  in the menu, we don't let the user type with them.
function Me.UpdateChatTypeHashes()
	if Me.db.global.show_rpw and Me.connected then
		hash_ChatTypeInfoList["/RPW"] = "RPW"
	else
		hash_ChatTypeInfoList["/RPW"] = nil
	end
	for i = 1, 9 do
		if Me.db.global["show_rp"..i] and Me.connected then
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
		if chat_type:match( "^RP." )
		   and not (Me.db.global["show_"..chat_type:lower()] and Me.connected) 
		                                                               then
			editbox:SetAttribute( "chatType", "SAY" )
			if editbox:IsShown() then
				ChatEdit_UpdateHeader(editbox)
			end
		end
	end
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

-- /rp1 is the same as /rp, and RP1 shows up as just "RP".
-- We also have /rpw for "RP Warning"
ChatTypeInfo["RPW"]           = { r = 1, g = 1, b = 1, sticky = 1 }
hash_ChatTypeInfoList["/RP"]  = "RP1"
hash_ChatTypeInfoList["/RPW"] = "RPW"
CHAT_RP1_SEND                 = "RP: "
CHAT_RP1_GET                  = "[RP] %s: "
CHAT_RPW_SEND                 = L.RP_WARNING .. ": "
CHAT_RPW_GET                  = "["..L.RP_WARNING.."] %s: "
