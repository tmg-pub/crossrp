-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- Let's have a little bit of fun, hm? Here's something like a base64
--  implementation, for packing map coordinates.
-------------------------------------------------------------------------------
local _, Me = ...

-- Max number range is +-2^32 / 2 / 5
--
local PACKCOORD_DIGITS 
--          0          11                         38                       63
         = "0123456789+@ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
--          48-57     |64-90                      97-122
--                 43-'
-------------------------------------------------------------------------------
-- Returns a fixed point packed number.
--
function Me.PackCoord( number )
	-- We store the number as units of fifths, and then we add one more bit 
	--  which is the sign. In other words, odd numbers (packed) are negative
	--  when unpacked, and we discard this LSB.
	number = math.floor( number * 5 )
	if number < 0 then
		number = (-number * 2) + 1
	else
		number = number * 2
	end
	local result = ""
	while number > 0 do
		-- Iterate through 6-bit chunks, select a digit from our string up
		--  there, and then append it to the result.
		local a = bit.band( number, 63 ) + 1
		result  = PACKCOORD_DIGITS:sub(a,a) .. result
		number  = bit.rshift( number, 6 )
	end
	if result == "" then result = "0" end
	return result
end

------------------------------------------------------------------------
-- Reverts a fixed point packed number.
--
function Me.UnpackCoord( packed )
	if not packed then return nil end
	
	local result = 0
	for i = 0, #packed-1 do
		-- Go through the string backward, and then convert the digits
		--  back into 6-bit numbers, shifting them accordingly and adding
		--  them to the results.
		-- We can have some fun sometime benchmarking a few different ways
		--  how to do this:
		-- (1) Using string:find with our string above to convert it easily.
		--     (Likely slow)
		-- (2) This way, below.
		-- (3) Add some code above to generate a lookup map.
		--
		local digit = packed:byte( #packed - i )
		if digit >= 48 and digit <= 57 then
			digit = digit - 48
		elseif digit == 43 then
			digit = 10
		elseif digit >= 64 and digit <= 90 then
			digit = digit - 64 + 11
		elseif digit >= 97 and digit <= 122 then
			digit = digit - 97 + 38
		else
			-- Bad input.
			return nil
		end
		result = result + bit.lshift( digit, i*6 )
	end
	
	-- The unpacked number is in units of fifths (fixed point), with an
	--  additional sign-bit appended.
	if bit.band( result, 1 ) == 1 then
		result = -bit.rshift( result, 1 )
	else
		result = bit.rshift( result, 1 )
	end
	return result / 5
end
