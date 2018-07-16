-- Copyright (c) 2007, Ace3 Development Team 
-- 
-- All rights reserved.
-- 
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions are met:
-- 
--    * Redistributions of source code must retain the above copyright notice,
--      this list of conditions and the following disclaimer.
--    * Redistributions in binary form must reproduce the above copyright
--      notice, this list of conditions and the following disclaimer in the
--      documentation and/or other materials provided with the distribution.
--    * Redistribution of a stand alone version is strictly prohibited without
--      prior written authorization from the Lead of the Ace3 Development Team.
--    * Neither the name of the Ace3 Development Team nor the names of its
--      contributors may be used to endorse or promote products derived from
--      this software without specific prior written permission.
-- 
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
-- "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
-- LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
-- A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER
-- OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
-- EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
-- PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
-- PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
-- LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
-- NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
-- SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

-------------------------------------------------------------------------------
-- (!) This is a customized version of the Ace3 Serializer, which changes the
--  way strings are escaped, so that they're more suitable for our text
--  protocol.
-------------------------------------------------------------------------------

local _, Me = ...
local MySerializer = {}

-- Lua APIs
local strbyte, strchar, gsub, gmatch, format 
          = string.byte, string.char, string.gsub, string.gmatch, string.format
local assert, error, pcall = assert, error, pcall
local type, tostring, tonumber = type, tostring, tonumber
local pairs, select, frexp = pairs, select, math.frexp
local tconcat = table.concat

-- quick copies of string representations of wonky numbers
local inf = math.huge

local serNaN  -- can't do this in 4.3, see ace3 ticket 268
local serInf, serInfMac = "1.#INF", "inf"
local serNegInf, serNegInfMac = "-1.#INF", "-inf"

-- Serialization functions

local function SerializeStringHelper(ch)	-- Used by SerializeValue for strings
	-- We use \126 ("~") as an escape character for all nonprints plus a few more
	local n = strbyte(ch)

	---------------------------------------------------------------------------
	-- (!) Don't escape space, remap control chars a little differently, 
	--  0-9,A-V, escape the pipe character, and escape backslash.
	---------------------------------------------------------------------------
	if n<=31 then 			-- nonprint  
		if n <= 9 then
			return "~"..strchar(n+48) -- starts at 0
		else
			return "~"..strchar(n+55) -- starts at A (65-10)
		end
	elseif n==94 then		-- value separator 
		return "~a"
	elseif n==92 then       -- \ backslash
		return "~b"
	elseif n==124 then		-- | pipe
		return "~c"
	elseif n==126 then		-- tilda / our own escape character
		return "~d"
	elseif n==127 then		-- nonprint (DEL)
		return "~e"
	else
		assert(false)	-- can't be reached if caller uses a sane regex
	end
end

local function SerializeValue(v, res, nres)
	-- We use "^" as a value separator, followed by one byte for type indicator
	local t=type(v)
	
	if t=="string" then		-- ^S = string (escaped to remove nonprints, "^"s, etc)
		res[nres+1] = "^S"
		res[nres+2] = gsub(v,"[%c\092\094\124\126\127]", SerializeStringHelper)
		nres=nres+2
	
	elseif t=="number" then	-- ^N = number (just tostring()ed) or ^F (float components)
		local str = tostring(v)
		if tonumber(str)==v  --[[not in 4.3 or str==serNaN]] then
			-- translates just fine, transmit as-is
			res[nres+1] = "^N"
			res[nres+2] = str
			nres=nres+2
		elseif v == inf or v == -inf then
			res[nres+1] = "^N"
			res[nres+2] = v == inf and serInf or serNegInf
			nres=nres+2
		else
			local m,e = frexp(v)
			res[nres+1] = "^F"
			res[nres+2] = format("%.0f",m*2^53)	-- force mantissa to become integer (it's originally 0.5--0.9999)
			res[nres+3] = "^f"
			res[nres+4] = tostring(e-53)	-- adjust exponent to counteract mantissa manipulation
			nres=nres+4
		end
	
	elseif t=="table" then	-- ^T...^t = table (list of key,value pairs)
		nres=nres+1
		res[nres] = "^T"
		for k,v in pairs(v) do
			nres = SerializeValue(k, res, nres)
			nres = SerializeValue(v, res, nres)
		end
		nres=nres+1
		res[nres] = "^t"
	
	elseif t=="boolean" then	-- ^B = true, ^b = false
		nres=nres+1
		if v then
			res[nres] = "^B"	-- true
		else
			res[nres] = "^b"	-- false
		end
	
	elseif t=="nil" then		-- ^Z = nil (zero, "N" was taken :P)
		nres=nres+1
		res[nres] = "^Z"
	
	else
		error(MAJOR..": Cannot serialize a value of type '"..t.."'")	-- can't produce error on right level, this is wildly recursive
	end
	
	return nres
end



local serializeTbl = { "^1" }	-- "^1" = Hi, I'm data serialized by AceSerializer protocol rev 1

--- Serialize the data passed into the function.
-- Takes a list of values (strings, numbers, booleans, nils, tables)
-- and returns it in serialized form (a string).\\
-- May throw errors on invalid data types.
-- @param ... List of values to serialize
-- @return The data in its serialized form (string)
function MySerializer:Serialize(...)
	local nres = 1
	
	for i=1,select("#", ...) do
		local v = select(i, ...)
		nres = SerializeValue(v, serializeTbl, nres)
	end
	
	serializeTbl[nres+1] = "^^"	-- "^^" = End of serialized data
	
	return tconcat(serializeTbl, "", 1, nres+1)
end

-- Deserialization functions
local function DeserializeStringHelper(escape)
	-- (!) Our custom escape codes which match above in SerializeStringHelper
	local n = escape:byte(2)
	if n >= 48 and n <= 57 then
		return strchar(n-48)
	elseif n >= 65 and n <= 86 then
		return strchar(n-65+10)
	elseif escape=="~a" then
		return "\094"
	elseif escape=="~b" then
		return "\092"
	elseif escape=="~c" then
		return "\124"
	elseif escape=="~d" then
		return "\126"
	elseif escape=="~e" then
		return "\127"
	end
	error("DeserializeStringHelper got called for '"..escape.."'?!?")  -- can't be reached unless regex is screwed up
end

local function DeserializeNumberHelper(number)
	--[[ not in 4.3 if number == serNaN then
		return 0/0
	else]]if number == serNegInf or number == serNegInfMac then
		return -inf
	elseif number == serInf or number == serInfMac then
		return inf
	else
		return tonumber(number)
	end
end

-- DeserializeValue: worker function for :Deserialize()
-- It works in two modes:
--   Main (top-level) mode: Deserialize a list of values and return them all
--   Recursive (table) mode: Deserialize only a single value (_may_ of course be another table with lots of subvalues in it)
--
-- The function _always_ works recursively due to having to build a list of values to return
--
-- Callers are expected to pcall(DeserializeValue) to trap errors

local function DeserializeValue(iter,single,ctl,data)

	if not single then
		ctl,data = iter()
	end

	if not ctl then 
		error("Supplied data misses AceSerializer terminator ('^^')")
	end	

	if ctl=="^^" then
		-- ignore extraneous data
		return
	end

	local res
	
	if ctl=="^S" then
		res = gsub(data, "~.", DeserializeStringHelper)
	elseif ctl=="^N" then
		res = DeserializeNumberHelper(data)
		if not res then
			error("Invalid serialized number: '"..tostring(data).."'")
		end
	elseif ctl=="^F" then     -- ^F<mantissa>^f<exponent>
		local ctl2,e = iter()
		if ctl2~="^f" then
			error("Invalid serialized floating-point number, expected '^f', not '"..tostring(ctl2).."'")
		end
		local m=tonumber(data)
		e=tonumber(e)
		if not (m and e) then
			error("Invalid serialized floating-point number, expected mantissa and exponent, got '"..tostring(m).."' and '"..tostring(e).."'")
		end
		res = m*(2^e)
	elseif ctl=="^B" then	-- yeah yeah ignore data portion
		res = true
	elseif ctl=="^b" then   -- yeah yeah ignore data portion
		res = false
	elseif ctl=="^Z" then	-- yeah yeah ignore data portion
		res = nil
	elseif ctl=="^T" then
		-- ignore ^T's data, future extensibility?
		res = {}
		local k,v
		while true do
			ctl,data = iter()
			if ctl=="^t" then break end	-- ignore ^t's data
			k = DeserializeValue(iter,true,ctl,data)
			if k==nil then 
				error("Invalid AceSerializer table format (no table end marker)")
			end
			ctl,data = iter()
			v = DeserializeValue(iter,true,ctl,data)
			if v==nil then
				error("Invalid AceSerializer table format (no table end marker)")
			end
			res[k]=v
		end
	else
		error("Invalid AceSerializer control code '"..ctl.."'")
	end
	
	if not single then
		return res,DeserializeValue(iter)
	else
		return res
	end
end

--- Deserializes the data into its original values.
-- Accepts serialized data, ignoring all control characters and whitespace.
-- @param str The serialized data (from :Serialize)
-- @return true followed by a list of values, OR false followed by an error message
function MySerializer:Deserialize(str)
	-- (!) Not sure what this is for, but space was removed from control characters to keep things
	--  readable.
	str = gsub(str, "[%c]", "")	-- ignore all control characters; nice for embedding in email and stuff

	local iter = gmatch(str, "(^.)([^^]*)")	-- Any ^x followed by string of non-^
	local ctl,data = iter()
	if not ctl or ctl~="^1" then
		-- we purposefully ignore the data portion of the start code, it can be used as an extension mechanism
		return false, "Supplied data is not AceSerializer data (rev 1)"
	end

	return pcall(DeserializeValue, iter)
end

-- (!) We also expose our escaping function for simple string transfers.
function MySerializer:EscapeString( text )
	return gsub(text,"[%c\092\094\124\126\127]", SerializeStringHelper)
end

function MySerializer:UnescapeString( text )
	return gsub(text, "~.", DeserializeStringHelper)
end

Me.Serializer = MySerializer