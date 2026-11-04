-- Diagnostic-only DC323/Viper command and framebuffer-region trace.
-- This script observes native firmware activity and never changes emulated state.

local cpu2 = manager.machine.devices[":cpu2"]
local xdata = cpu2.spaces["xdata"]
local screen = manager.machine.screens[":screen"]
local artifact_dir = os.getenv("VT340_TEST_ARTIFACT_DIR")
local planes = manager.machine.memory.shares[":bitmap_planes"]

assert(planes, "VT340 bitmap_planes memory share is unavailable")

local regs = {}
local viper = { {}, {}, {}, {} }
local viper_select = 0
local commands = 0
local palette_writes = 0
local region_trace_start = 115.0
local pending_raster = nil

local regions = {
	{ name = "WAIT",      x0 =   0, y0 =   0, x1 =  39, y1 =  19 },
	{ name = "STATUS",    x0 =   0, y0 = 480, x1 = 799, y1 = 499 },
	{ name = "POST_OK",   x0 = 300, y0 = 200, x1 = 499, y1 = 259 },
	{ name = "COPYRIGHT", x0 = 180, y0 = 380, x1 = 619, y1 = 439 }
}

local function framebuffer_hash(region)
	-- FNV-1a over the four one-byte-per-pixel bitmap planes.  The exact ROI
	-- bounds are deliberately part of the trace record so later refinements
	-- cannot silently change the meaning of an existing hash.
	local hash = 0x811c9dc5
	for plane = 0, 3 do
		local plane_base = plane * 1024 * 2048
		for y = region.y0, region.y1 do
			local row = plane_base + y * 1024
			for x = region.x0, region.x1, 8 do
				local word = planes:read_u64(row + x)
				hash = ((hash ~ word ~ (word >> 32)) * 0x01000193) & 0xffffffff
			end
		end
	end
	return hash
end

local function intersects(x, y, width, height, region)
	return width ~= 0 and height ~= 0 and x <= region.x1 and y <= region.y1 and
		(x + width - 1) >= region.x0 and (y + height - 1) >= region.y0
end

local function capture_rectangle(x, y, width, height)
	local x0 = math.min(x, 1024)
	local y0 = math.min(y, 2048)
	local x1 = math.min(x + width, 1024)
	local y1 = math.min(y + height, 2048)
	local pixels = {}
	local n = 0
	for py = y0, y1 - 1 do
		for px = x0, x1 - 1 do
			local address = py * 1024 + px
			local color = 0
			for plane = 0, 3 do
				color = color | ((planes:read_u8(plane * 1024 * 2048 + address) & 1) << plane)
			end
			n = n + 1
			pixels[n] = color
		end
	end
	return { x0 = x0, y0 = y0, x1 = x1, y1 = y1, pixels = pixels }
end

local function finish_pending_raster()
	if not pending_raster then return end
	local after = capture_rectangle(
		pending_raster.before.x0, pending_raster.before.y0,
		pending_raster.before.x1 - pending_raster.before.x0,
		pending_raster.before.y1 - pending_raster.before.y0)
	local changed_pixels = 0
	local changed_bits = 0
	for i, before in ipairs(pending_raster.before.pixels) do
		local difference = before ~ after.pixels[i]
		if difference ~= 0 then
			changed_pixels = changed_pixels + 1
			for plane = 0, 3 do
				changed_bits = changed_bits + ((difference >> plane) & 1)
			end
		end
	end
	print(string.format(
		'VT340_GFX_JSON {"event":"raster_result","parent":%d,"clipped_bounds":[%d,%d,%d,%d],"eligible_pixels":%d,"changed_pixels":%d,"changed_plane_bits":%d}',
		pending_raster.id, after.x0, after.y0, after.x1 - 1, after.y1 - 1,
		#after.pixels, changed_pixels, changed_bits))
	pending_raster = nil
end

local function emit_regions(event, destination_x, destination_y, width, height)
	for _, region in ipairs(regions) do
		local hit = intersects(destination_x, destination_y, width, height, region)
		local hash = hit and string.format('"%08X"', framebuffer_hash(region)) or "null"
		print(string.format(
			'VT340_GFX_JSON {"event":"region","parent":%d,"name":"%s","bounds":[%d,%d,%d,%d],"intersects":%s,"hash":%s}',
			event, region.name, region.x0, region.y0, region.x1, region.y1,
			hit and "true" or "false", hash))
	end
end

graphics_command_trace = xdata:install_write_tap(
	0xf000, 0xffff, "graphics_command_trace",
	function(offset, data, mask)
		finish_pending_raster()
		local now = manager.machine.time:as_double()
		local pc = cpu2.state["PC"].value

		if (offset & 0xffe0) == 0xf080 or (offset & 0xffe0) == 0xf0a0 then
			palette_writes = palette_writes + 1
			print(string.format(
				'VT340_GFX_JSON {"event":"palette","time":%.9f,"pc":"%04X","bank":"%s","index":%d,"value":"%02X"}',
				now, pc, ((offset & 0xffe0) == 0xf080) and "RG" or "GB", offset & 0x0f, data))
			return
		end

		if offset >= 0xf060 and offset <= 0xf07f then
			local select = (((data >> 5) & 1) << 0) |
				(((data >> 4) & 1) << 1) |
				(((data >> 3) & 1) << 2) |
				(((data >> 2) & 1) << 3)
			viper_select = select
			print(string.format(
				'VT340_GFX_JSON {"event":"viper_select","time":%.9f,"pc":"%04X","address":"%04X","data":"%02X","select":"%X"}',
				now, pc, offset, data, select))
			return
		end

		if (offset & 0xf0c0) ~= 0xf000 then return end
		local reg = offset & 0x3f
		local value = (cpu2.state["P1"].value << 8) | data
		regs[reg] = value
		if reg >= 0x0e and reg <= 0x1a then
			print(string.format(
				'VT340_GFX_JSON {"event":"scroll_register","time":%.9f,"pc":"%04X","register":"%02X","value":"%04X","scroll_bounds":["%04X","%04X","%04X","%04X"],"y_offset":"%04X","y_scroll":"%04X","erase":%s,"indexes":["%04X","%04X","%04X","%04X","%04X","%04X"]}',
				now, pc, reg, value,
				regs[0x0e] or 0, regs[0x0f] or 0, regs[0x10] or 0, regs[0x11] or 0,
				regs[0x13] or 0, regs[0x14] or 0,
				((regs[0x14] or 0) & 0x2000) ~= 0 and "true" or "false",
				regs[0x15] or 0, regs[0x16] or 0, regs[0x17] or 0,
				regs[0x18] or 0, regs[0x19] or 0, regs[0x1a] or 0))
		end
		if reg ~= 0x08 then return end

		if (value & 0xffe0) == 0x0180 then
			local viper_reg = value & 0x1f
			for plane = 0, 3 do
				if ((viper_select >> plane) & 1) ~= 0 then
					viper[plane + 1][viper_reg] = regs[0x07] or 0
				end
			end
		end

		commands = commands + 1
		local operation = (value >> 8) & 3
		local destination_enabled = ((value >> 10) & 1) ~= 0
		local source1_enabled = ((value >> 11) & 1) ~= 0
		local source2_enabled = ((value >> 12) & 1) ~= 0
		local mode = regs[0x09] or 0
		local source_x = (regs[0x22] or 0) & 0x3fff
		local source_y = (regs[0x23] or 0) & 0x1fff
		local destination_x = (regs[0x24] or 0) & 0x3fff
		local destination_y = (regs[0x25] or 0) & 0x3fff
		local width = (regs[0x26] or 0) & 0x1fff
		local height = (regs[0x29] or 0) & 0x1fff
		local function_selector = (value >> 4) & 3
		local logic = viper[1][4 + function_selector] or 0
		local normal_mode = (mode & 0x1f) == 0 and (mode & 0x80) ~= 0
		local indexed = (mode & 0x60) ~= 0
		local zero_indexes = ((regs[0x17] or 0) | (regs[0x18] or 0) |
			(regs[0x19] or 0) | (regs[0x1a] or 0)) == 0
		local supported = operation == 2 and destination_enabled and
			not source2_enabled and normal_mode and (not indexed or zero_indexes)
		local reason = "executed"
		if operation ~= 2 then reason = "non_rasterop"
		elseif not destination_enabled then reason = "destination_disabled"
		elseif source2_enabled then reason = "source2_unimplemented"
		elseif not normal_mode then reason = "non_normal_mode_unimplemented"
		elseif indexed and not zero_indexes then reason = "nonzero_index_unimplemented"
		end

		print(string.format(
			'VT340_GFX_JSON {"event":"command","id":%d,"time":%.9f,"pc":"%04X","raw":"%04X","operation":%d,"destination":%s,"source1":%s,"source2":%s,"mode":"%04X","source":[%d,%d],"destination_origin":[%d,%d],"extent":[%d,%d],"bitmap_stride":1024,"e49_stride":32,"xcon":"%04X","function_selector":%d,"viper_select":"%X","logic":"%02X","logic_planes":["%02X","%02X","%02X","%02X"],"resolution_mode":"%04X","bus_width":"%04X","scroll_constant":"%04X","plane_address":"%04X","mask1":"%04X","mask2":"%04X","source_constant":"%04X","fill":"%04X","background":"%04X","foreground":"%04X","background_planes":["%04X","%04X","%04X","%04X"],"foreground_planes":["%04X","%04X","%04X","%04X"],"csr_select":%d,"csr":["%04X","%04X","%04X","%04X","%04X","%04X","%04X"],"y_offset":"%04X","y_scroll":"%04X","indexes":["%04X","%04X","%04X","%04X","%04X","%04X"],"supported":%s,"reason":"%s"}',
			commands, now, pc, value, operation,
			destination_enabled and "true" or "false",
			source1_enabled and "true" or "false",
			source2_enabled and "true" or "false",
			mode, source_x, source_y, destination_x, destination_y, width, height,
			regs[0x35] or 0, function_selector, viper_select, logic,
			viper[1][4 + function_selector] or 0, viper[2][4 + function_selector] or 0,
			viper[3][4 + function_selector] or 0, viper[4][4 + function_selector] or 0,
			viper[1][0] or 0, viper[1][1] or 0, viper[1][2] or 0, viper[1][3] or 0,
			viper[1][8] or 0, viper[1][9] or 0, viper[1][0x0a] or 0, viper[1][0x0b] or 0,
			viper[1][0x0e] or 0, viper[1][0x0f] or 0,
			viper[1][0x0e] or 0, viper[2][0x0e] or 0, viper[3][0x0e] or 0, viper[4][0x0e] or 0,
			viper[1][0x0f] or 0, viper[2][0x0f] or 0, viper[3][0x0f] or 0, viper[4][0x0f] or 0,
			(value >> 2) & 1,
			viper[1][0x10] or 0, viper[1][0x11] or 0, viper[1][0x12] or 0,
			viper[1][0x13] or 0, viper[1][0x14] or 0, viper[1][0x15] or 0, viper[1][0x16] or 0,
			regs[0x13] or 0, regs[0x14] or 0,
			regs[0x15] or 0, regs[0x16] or 0, regs[0x17] or 0,
			regs[0x18] or 0, regs[0x19] or 0, regs[0x1a] or 0,
			supported and "true" or "false", reason))
		if now >= region_trace_start and operation == 2 then
			emit_regions(commands, destination_x, destination_y, width, height)
			if supported then
				pending_raster = {
					id = commands,
					before = capture_rectangle(destination_x, destination_y, width, height)
				}
			end
		end
	end)

local capture_times = { 115, 124, 130, 140, 160, 180, 240, 300 }
local next_capture = 1
emu.register_frame_done(function()
	local now = manager.machine.time:as_double()
	while next_capture <= #capture_times and now >= capture_times[next_capture] do
		local capture = capture_times[next_capture]
		local path = artifact_dir and artifact_dir ~= "" and
			string.format("%s/graphics-%03d.png", artifact_dir, capture) or
			string.format("/tmp/vt340-graphics-%03d.png", capture)
		screen:snapshot(path)
		print(string.format(
			'VT340_GFX_JSON {"event":"snapshot","time":%.9f,"target_time":%d,"path":"%s"}',
			now, capture, path))
		for _, region in ipairs(regions) do
			print(string.format(
				'VT340_GFX_JSON {"event":"snapshot_region","target_time":%d,"name":"%s","bounds":[%d,%d,%d,%d],"bitmap_hash":"%08X"}',
				capture, region.name, region.x0, region.y0, region.x1, region.y1,
				framebuffer_hash(region)))
		end
		next_capture = next_capture + 1
	end
end)

graphics_command_trace_stop = emu.add_machine_stop_notifier(function()
	finish_pending_raster()
	print(string.format(
		'VT340_GFX_JSON {"event":"summary","time":%.9f,"commands":%d,"palette_writes":%d}',
		manager.machine.time:as_double(), commands, palette_writes))
end)
