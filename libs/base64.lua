
local _, Me = ...

--[[

-- Base64-encoding
-- Sourced from http://en.wikipedia.org/wiki/Base64

local __author__ = 'Daniel Lindsley'
local __version__ = 'scm-1'
local __license__ = 'BSD'

local index_table = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local function to_binary(integer)
    local remaining = tonumber(integer)
    local bin_bits = ''

    for i = 7, 0, -1 do
        local current_power = math.pow(2, i)

        if remaining >= current_power then
            bin_bits = bin_bits .. '1'
            remaining = remaining - current_power
        else
            bin_bits = bin_bits .. '0'
        end
    end

    return bin_bits
end

local function from_binary(bin_bits)
    return tonumber(bin_bits, 2)
end


local function to_base64(to_encode)
    local bit_pattern = ''
    local encoded = ''
    local trailing = ''

    for i = 1, string.len(to_encode) do
        bit_pattern = bit_pattern .. to_binary(string.byte(string.sub(to_encode, i, i)))
    end

    -- Check the number of bytes. If it's not evenly divisible by three,
    -- zero-pad the ending & append on the correct number of ``=``s.
    if math.fmod(string.len(bit_pattern), 3) == 2 then
        trailing = '=='
        bit_pattern = bit_pattern .. '0000000000000000'
    elseif math.fmod(string.len(bit_pattern), 3) == 1 then
        trailing = '='
        bit_pattern = bit_pattern .. '00000000'
    end

    for i = 1, string.len(bit_pattern), 6 do
        local byte = string.sub(bit_pattern, i, i+5)
        local offset = tonumber(from_binary(byte))
        encoded = encoded .. string.sub(index_table, offset+1, offset+1)
    end

    return string.sub(encoded, 1, -1 - string.len(trailing)) .. trailing
end


local function from_base64(to_decode)
    local padded = to_decode:gsub("%s", "")
    local unpadded = padded:gsub("=", "")
    local bit_pattern = ''
    local decoded = ''

    for i = 1, string.len(unpadded) do
        local char = string.sub(to_decode, i, i)
        local offset, _ = string.find(index_table, char)
        if offset == nil then
             error("Invalid character '" .. char .. "' found.")
        end

        bit_pattern = bit_pattern .. string.sub(to_binary(offset-1), 3)
    end

    for i = 1, string.len(bit_pattern), 8 do
        local byte = string.sub(bit_pattern, i, i+7)
        decoded = decoded .. string.char(from_binary(byte))
    end

    local padding_length = padded:len()-unpadded:len()

    if (padding_length == 1 or padding_length == 2) then
        decoded = decoded:sub(1,-2)
    end
    return decoded
end

Me.ToBase64 = to_base64
Me.FromBase64 = from_base64
]]

-- Sweet base64 implementation by Itarater.

local b64Pad = "="
local b64Tab = { [0] =
	"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P",
	"Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "a", "b", "c", "d", "e", "f",
	"g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v",
	"w", "x", "y", "z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "+", "/",
}
local b64Dec = {}
for i = 0, #b64Tab do
	b64Dec[b64Tab[i]:byte(1)] = i
end

local function b64(str)
	local out = {}
	for i = 1, #str, 3 do
		local b1, b2, b3 = str:byte(i, i + 2)
		local num = bit.bor(bit.lshift(b1, 16), bit.lshift(b2 or 0, 8), b3 or 0)
		for j = 1, 4 do
			out[#out + 1] = b64Tab[bit.rshift(num, 24 - (j * 6)) % 0x40]
		end
	end
	local remain = #str % 3
	if remain == 1 then
		out[#out] = b64Pad
		out[#out - 1] = b64Pad
	elseif remain == 2 then
		out[#out] = b64Pad
	end
	return table.concat(out)
end

local function unb64(str)
	local out = {}
	local pad = 0
	for i = #str, #str - 2, -1 do
		if str:byte(i) == 61 then
			pad = pad + 1
		end
	end
	for i = 1, #str, 4 do
		local b1, b2, b3, b4 = str:byte(i, i + 3)
		local num = bit.bor(bit.lshift(b64Dec[b1], 18), bit.lshift(b64Dec[b2], 12), bit.lshift(b64Dec[b3] or 0, 6), b64Dec[b4] or 0)
		for j = 1, 3 do
			out[#out + 1] = string.char(bit.rshift(num, 24 - (j * 8)) % 0x100)
		end
	end
	for i = 1, pad do
		out[#out] = nil
	end
	return table.concat(out)
end

Me.ToBase64 = b64
Me.FromBase64 = unb64
