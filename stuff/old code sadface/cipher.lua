-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- Message ciphering.
-------------------------------------------------------------------------------
-- Stay away, cryptologists. This is NOT super secure encryption.
--
local _, Me = ...

local CHAR_TO_INDEX = {}
local INDEX_TO_CHAR = {}

local ESCAPE_CHAR = {
	[92]  = 49; -- \ = 1
	[124] = 50; -- | = 2
	[127] = 51; -- DEL = 3
}

local REVERSE_ESCAPE_CHAR = {
	[49] = 92;  -- 1 = \
	[50] = 124; -- 2 = |
	[51] = 127; -- 3 = DEL
}

local ESCAPE = 127

for ch = 32, 127 do
	if ESCAPE_CHAR[ch] and ch ~= ESCAPE then
		-- Skip adding escaped characters to the character set.
	else
		table.insert( INDEX_TO_CHAR, ch )
		CHAR_TO_INDEX[ch] = #INDEX_TO_CHAR
	end
end

-------------------------------------------------------------------------------
-- Shared globally with the encipher/decipher filters
local m_cipher_position
local m_cipher_bytes
local m_utf_byte
local m_utf_word
local m_escaped

local m_cipher_cache = {}

local function GetCipher( key, length )
	local name = "key" .. "~.~" .. length
	if m_cipher_cache[name] then
		return m_cipher_cache[name]
	end
	
	local source = key
	local cipher = ""
	while #cipher < length do
		source = sha256( source )
		cipher = cipher .. source
	end
	
	m_cipher_cache[name] = cipher
	return cipher
end

-------------------------------------------------------------------------------
-- disallowed utf8 characters:
-- 534D, 5350
-- d800-dfff 

-- 0101001101 001101 534D
-- 0101001101 010000 5350
-- 1101100000 000000 D800
-- 1101111111 111111 DFFF
-- 1111111111 111110 FFFE
-- 1111111111 111111 FFFF
-------------------------------------------------------------------------------

local function EncipherCharacter( character )
	local cb = character:byte()
	if cb < 128 then
		if ESCAPE_CHAR[cb] and not m_escaped then
			m_escaped = true
			return EncipherCharacter( string.char(ESCAPE) ) .. EncipherCharacter( string.char(ESCAPE_CHAR[cb]) )
		end
		m_escaped = false
		cb = CHAR_TO_INDEX[ cb ]
		if not cb then return character end -- Not supported, return raw.
		cb = (cb + m_cipher_bytes:byte(m_cipher_position) - 1) % #INDEX_TO_CHAR
		m_cipher_position = m_cipher_position % #m_cipher_bytes + 1
		return string.char( INDEX_TO_CHAR[ 1 + cb ] )
	end
	
	if cb >= 192 then
		-- utf-8 leading byte
		if cb >= 240 then
			m_utf_byte = 3
			m_utf_word = (cb % 8) * (2^18)
		elseif cb >= 224 then
			m_utf_byte = 2
			m_utf_word = (cb % 16) * (2^12)
		else
			m_utf_byte = 1
			m_utf_word = (cb % 32) * (2^6)
		end
		return character
	end
	
	-- utf-8 trailing byte
	m_utf_byte = m_utf_byte - 1
	if m_utf_byte == 0 then
		-- we only encode the last byte to save ourself a massive headache
		if m_utf_word == 0x5340 or (m_utf_word >= 0xD800 and m_utf_word < 0xE000) or m_utf_word == 0xFFC0 then
			-- Don't cipher anything where you could end up with an invalid UTF-8 character or anything
			--  forbidden in WoW.
			return character
		end
		
		cb = (cb + m_cipher_bytes:byte(m_cipher_position)) % 64
		m_cipher_position = m_cipher_position % #m_cipher_bytes + 1
		return string.char( 128 + cb )
	else
		m_utf_word = m_utf_word + (cb%64) * (2^(6*m_utf_byte))
	end
	return character
end

function Me.Cipher( message, key, keylen, keystart )
	m_cipher_bytes = GetCipher( key, keylen )
	m_cipher_position = ((keystart or 1) - 1) % #m_cipher_bytes + 1
	m_utf_byte = 0
	m_utf_word = 0
	m_escaped = false
	return message:gsub( ".", EncipherCharacter )
end

local function DecipherCharacter( character )
	local cb = CHAR_TO_INDEX[ character:byte() ]
	local cb = character:byte()
	if cb < 128 then
		cb = CHAR_TO_INDEX[ cb ]
		if not cb then return character end
		cb = (cb - m_cipher_bytes:byte(m_cipher_position) - 1) % #INDEX_TO_CHAR
		m_cipher_position = m_cipher_position % #m_cipher_bytes + 1
		cb = INDEX_TO_CHAR[1+cb]
		if cb == ESCAPE and not m_escaped then
			m_escaped = true
			return ""
		elseif m_escaped then
			m_escaped = false
			return string.char( REVERSE_ESCAPE_CHAR[cb] )
		end
		return string.char( cb )
	end
	
	if cb >= 192 then
		-- utf-8 leading byte
		if cb >= 240 then
			m_utf_byte = 3
			m_utf_word = (cb % 8) * (2^18)
		elseif cb >= 224 then
			m_utf_byte = 2
			m_utf_word = (cb % 16) * (2^12)
		else
			m_utf_byte = 1
			m_utf_word = (cb % 32) * (2^6)
		end
		return character
	end
	
	m_utf_byte = m_utf_byte - 1
	if m_utf_byte == 0 then
		-- we only encode the last byte to save ourself a massive headache
		if m_utf_word == 0x5340 or (m_utf_word >= 0xD800 and m_utf_word < 0xE000) or m_utf_word == 0xFFC0 then
			-- Don't cipher anything where you could end up with an invalid UTF-8 character or anything
			--  forbidden in WoW.
			return character
		end
		cb = (cb - m_cipher_bytes:byte(m_cipher_position)) % 64
		m_cipher_position = m_cipher_position % #m_cipher_bytes + 1
		return string.char( 128 + cb )
	else
		m_utf_word = m_utf_word + (cb%64) * (2^(6*m_utf_byte))
	end
	
	return character
end

function Me.Decipher( message, key, keylen, keystart )
	m_cipher_bytes    = GetCipher( key, keylen )
	m_cipher_position = ((keystart or 1) - 1) % #m_cipher_bytes + 1
	m_utf_byte        = 0
	m_utf_word        = 0
	m_escaped         = false
	return message:gsub( ".", DecipherCharacter )
end


function Me.Ciphertemp( message, key )
	message = Me.Cipher( message, key, 4096, 1 )
	local offset = message:byte(2) - 32 + (message:byte(1) - 32) * 96
	message = message:sub( 1, 2 ) 
	         .. Me.Cipher( message:sub(3), key .. "~~~overlay~~~asdfjao ewa03aojiwaf;k", 4096, offset )
	return message
end

function Me.Deciphertemp( message, key )

	local offset = message:byte(2) - 32 + (message:byte(1) - 32) * 96
	message = message:sub( 1, 2 ) 
	         .. Me.Decipher( message:sub(3), key .. "~~~overlay~~~asdfjao ewa03aojiwaf;k", 4096, offset )
	message = Me.Decipher( message, key, 4096, 1 )
	return message
	
end
