-- Observe native VT340 text attributes without modifying graphics state.
-- A host process supplies the SGR fixture through Comm 1 after the script
-- leaves POST. Raw Viper-plane indices distinguish intensity attributes even
-- when two palette entries happen to contain the same RGB value.

io.stdout:setvbuf("no")

local cpu2 = manager.machine.devices[":cpu2"]
local xdata = cpu2.spaces["xdata"]
local planes = manager.machine.memory.shares[":bitmap_planes"]
local keyboard = manager.machine.natkeyboard
local screen = manager.machine.screens[":screen"]
local snapshot = os.getenv("VT340_TEXT_ATTR_SNAPSHOT") or "/tmp/vt340-text-attributes.png"
local palette_rg = {}
local palette_gb = {}
local left_post = false
local next_capture = 1
local captures = { 140.0, 140.25, 140.5, 140.75, 141.0, 141.25, 141.5, 141.75 }

assert(planes, "VT340 bitmap_planes memory share is unavailable")
keyboard.in_use = true

text_attribute_palette_tap = xdata:install_write_tap(
	0xf080, 0xf0bf, "vt340_text_attribute_palette",
	function(offset, data, mask)
		if (offset & 0xffe0) == 0xf080 then
			palette_rg[offset & 0x0f] = data
		elseif (offset & 0xffe0) == 0xf0a0 then
			palette_gb[offset & 0x0f] = data
		end
	end)

local function output_map_address(planes_value)
	return ((planes_value & 0x01) << 3) |
		((planes_value & 0x02) << 1) |
		((planes_value & 0x04) >> 1) |
		((planes_value & 0x08) >> 3)
end

local function band_state(y0)
	local counts = {}
	local mapped = {}
	local hash = 0x811c9dc5
	for color = 0, 15 do
		counts[color] = 0
		mapped[color] = 0
	end
	for y = y0, y0 + 19 do
		for x = 0, 399 do
			local address = y * 1024 + x
			local color = 0
			for plane = 0, 3 do
				color = color | ((planes:read_u8(plane * 1024 * 2048 + address) & 1) << plane)
			end
			counts[color] = counts[color] + 1
			mapped[output_map_address(color)] = mapped[output_map_address(color)] + 1
			hash = ((hash ~ color) * 0x01000193) & 0xffffffff
		end
	end
	local count_text = {}
	local mapped_text = {}
	for color = 0, 15 do
		count_text[color + 1] = tostring(counts[color])
		mapped_text[color + 1] = tostring(mapped[color])
	end
	return string.format('{"hash":"%08X","raw":[%s],"mapped":[%s]}',
		hash, table.concat(count_text, ","), table.concat(mapped_text, ","))
end

local function palette_state()
	local entries = {}
	for index = 0, 15 do
		entries[index + 1] = string.format('"%02X%02X"',
			palette_rg[index] or 0, palette_gb[index] or 0)
	end
	return table.concat(entries, ",")
end

emu.register_frame_done(function()
	local now = manager.machine.time:as_double()
	if not left_post and now >= 130 then
		keyboard:post_coded("{TAB}")
		left_post = true
		print(string.format('VT340_TEXT_ATTR_JSON {"event":"external_ready","time":%.9f}', now))
	end

	while next_capture <= #captures and now >= captures[next_capture] do
		local target = captures[next_capture]
		if next_capture == 1 then
			screen:snapshot(snapshot)
		end
		print(string.format(
			'VT340_TEXT_ATTR_JSON {"event":"capture","time":%.9f,"target":%.2f,"normal":%s,"bold":%s,"underline":%s,"reverse":%s,"blink":%s,"reset":%s,"palette":[%s],"snapshot":"%s"}',
			now, target, band_state(0), band_state(20), band_state(40),
			band_state(60), band_state(80), band_state(100), palette_state(), snapshot))
		next_capture = next_capture + 1
	end
end)
