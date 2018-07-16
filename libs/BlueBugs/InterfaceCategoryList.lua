--[[
	© Justin Snelgrove

	Permission to use, copy, modify, and distribute this software for any
	purpose with or without fee is hereby granted, provided that the above
	copyright notice and this permission notice appear in all copies.

	THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
	WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
	MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
	SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
	WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION
	OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
	CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

	--

	InterfaceCategoryList_Update() taint

	The selection key is often tainted, if an addon options panel is selected.
	This taints the execution path of InterfaceCategoryList_Update(), and will
	often spread to other things (most commonly, raid profiles).

	Possible fix locations:
	Interface\FrameXML\InterfaceOptionsFrame.lua:83-135
]]

local ICLU_VERSION = 1

if (BLUEBUGS_ICLU_VERSION or 0) < ICLU_VERSION then

	InterfaceOptionsFrame:HookScript("OnHide", function(self)
		if ICLU_VERSION < BLUEBUGS_ICLU_VERSION then return end
		if not issecurevariable(InterfaceOptionsFrameCategories, "selection")
		then
			InterfaceOptionsFrameCategories.selection = nil
		end
	end)

	BLUEBUGS_ICLU_VERSION = ICLU_VERSION
end
