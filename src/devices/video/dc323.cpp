// license:BSD-3-Clause
// copyright-holders:Harley Card
/***************************************************************************

    Digital Equipment Corporation DC323 Adder

    The first implementation is a mechanical extraction of the VT340 model.
    Questionable timing and Viper behavior is intentionally retained so the
    extraction can be validated independently of later fidelity work.

***************************************************************************/

#include "emu.h"
#include "dc323.h"

#define LOG_REGISTERS  (1U << 1)
#define LOG_COMMANDS   (1U << 2)
#define LOG_SCROLL     (1U << 3)
#define LOG_INTERRUPTS (1U << 4)
#define LOG_TRANSFERS  (1U << 5)
#define LOG_RASTEROPS  (1U << 6)

#define VERBOSE (0)
#include "logmacro.h"

// A deliberately enabled diagnostic build must still remain usable during a
// long terminal session.  Emit one truncation notice after this many events.
#define DC323_LOG_LIMIT 100000U
#define DC323_LOGMASKED(mask, ...) \
	do { \
		if (VERBOSE & (mask)) \
		{ \
			if (m_log_events < DC323_LOG_LIMIT) \
				(LOG_OUTPUT_FUNC)(__VA_ARGS__); \
			else if (m_log_events == DC323_LOG_LIMIT) \
				(LOG_OUTPUT_FUNC)("%s %s: diagnostic log limit reached\n", machine().time().to_string(), tag()); \
			if (m_log_events <= DC323_LOG_LIMIT) \
				++m_log_events; \
		} \
	} while (false)


namespace {

struct raster_point
{
	int x;
	int y;
};


std::vector<raster_point> raster_vector(int dx, int dy, unsigned limit)
{
	unsigned const abs_dx = unsigned(std::abs(dx));
	unsigned const abs_dy = unsigned(std::abs(dy));
	unsigned const length = std::min(std::max(abs_dx, abs_dy), limit);
	std::vector<raster_point> result;
	result.reserve(length);
	if (!length)
		return result;

	bool const x_major = abs_dx >= abs_dy;
	unsigned const major = x_major ? abs_dx : abs_dy;
	unsigned const minor = x_major ? abs_dy : abs_dx;
	int const x_step = (dx > 0) - (dx < 0);
	int const y_step = (dy > 0) - (dy < 0);
	int error = -int(major);
	int x = 0;
	int y = 0;
	for (unsigned position = 0; position < length; position++)
	{
		result.push_back({ x, y });
		if (x_major)
			x += x_step;
		else
			y += y_step;
		error += int(2 * minor);
		if (error >= 0)
		{
			if (x_major)
				y += y_step;
			else
				x += x_step;
			error -= int(2 * major);
		}
	}
	return result;
}

} // anonymous namespace


DEFINE_DEVICE_TYPE(DC323, dc323_device, "dc323", "DEC DC323 Adder")


dc323_device::dc323_device(machine_config const &mconfig, char const *tag, device_t *owner, u32 clock) :
	device_t(mconfig, DC323, tag, owner, clock),
	m_chargen_rom(*this, finder_base::DUMMY_TAG),
	m_bitmap_planes(*this, "bitmap_planes", BITMAP_PLANES * BITMAP_PLANE_SIZE, ENDIANNESS_LITTLE),
	m_irq_handler(*this)
{
}


void dc323_device::device_start()
{
	save_item(NAME(m_registers));
	save_item(NAME(m_viper_registers));
	save_item(NAME(m_viper_select));
	save_item(NAME(m_status));
	save_item(NAME(m_operational));
	save_item(NAME(m_scroll_pending));
	save_item(NAME(m_pbt_read_active));
	save_item(NAME(m_pbt_read_command));
	save_item(NAME(m_pbt_read_index));
	save_item(NAME(m_pbt_read_count));
	save_item(NAME(m_pbt_write_active));
	save_item(NAME(m_pbt_write_command));
	save_item(NAME(m_pbt_write_bus_width));
	save_item(NAME(m_pbt_write_words_per_row));
	save_item(NAME(m_pbt_write_index));
	save_item(NAME(m_pbt_write_count));
	save_item(NAME(m_diagnostic_data));
	save_item(NAME(m_raster_diagnostic));
	save_item(NAME(m_video_operational));
	save_item(NAME(m_fill_position_valid));
	save_item(NAME(m_fill_a_x));
	save_item(NAME(m_fill_a_y));
	save_item(NAME(m_fill_b_x));
	save_item(NAME(m_fill_b_y));
	save_item(NAME(m_irq_state));
}


void dc323_device::device_reset()
{
	m_registers.fill(0);
	for (auto &registers : m_viper_registers)
		registers.fill(0);
	m_viper_select = 0;
	m_status = 0;
	m_operational = false;
	m_scroll_pending = false;
	m_pbt_read_active = false;
	m_pbt_read_command = 0;
	m_pbt_read_index = 0;
	m_pbt_read_count = 0;
	m_pbt_write_active = false;
	m_pbt_write_command = 0;
	m_pbt_write_bus_width = 0;
	m_pbt_write_words_per_row = 0;
	m_pbt_write_index = 0;
	m_pbt_write_count = 0;
	m_diagnostic_data = 0;
	m_raster_diagnostic = false;
	m_video_operational = false;
	m_fill_position_valid = false;
	m_fill_a_x = 0;
	m_fill_a_y = 0;
	m_fill_b_x = 0;
	m_fill_b_y = 0;
	m_irq_state = false;
	m_log_events = 0;
	bitmap_clear();
	m_irq_handler(CLEAR_LINE);
}


u8 dc323_device::read(offs_t offset)
{
	unsigned const reg = offset & 0x3f;
	u8 data;
	if ((reg == REG_ID_DATA) && m_pbt_read_active)
		data = id_data_r();
	else if ((reg == REG_STATUS) && m_operational)
		data = u8(m_status);
	else
		data = u8(m_registers[reg]);

	DC323_LOGMASKED(LOG_REGISTERS, "%s %s: R %02X=%02X status=%04X enable=%04X\n",
		machine().time().to_string(), tag(), reg, data, m_status, m_registers[REG_INTERRUPT_ENABLE]);
	return data;
}


void dc323_device::write(offs_t offset, u16 data)
{
	unsigned const reg = offset & 0x3f;
	u16 const old_data = m_registers[reg];
	DC323_LOGMASKED(LOG_REGISTERS, "%s %s: W %02X=%04X status=%04X enable=%04X\n",
		machine().time().to_string(), tag(), reg, data, m_status, m_registers[REG_INTERRUPT_ENABLE]);
	m_registers[reg] = data;
	if ((reg == REG_DESTINATION_X) || (reg == REG_DESTINATION_Y) ||
		((reg == REG_X_CONTROL) && ((old_data ^ data) & 0x000f)))
	{
		// Loading either destination origin starts a new fill position.  A
		// mode/axis/baseline change also terminates any active vector string.
		m_fill_position_valid = false;
	}
	if (reg == REG_ID_DATA)
	{
		// The board diagnostics use the DC323 I/D path as a retained test-data
		// source. Equal-byte words test ordinary bus retention; 00CF selects the
		// all-ones result and 00C6 selects the raster-address pattern returned by
		// diagnostic bitmap-to-processor command 0BC0.
		if (u8(data >> 8) == u8(data))
		{
			m_diagnostic_data = u8(data);
			m_raster_diagnostic = false;
		}
		if (data == 0x00cf)
		{
			m_diagnostic_data = 0xff;
			m_raster_diagnostic = false;
		}
		if (data == 0x00c6)
			m_raster_diagnostic = true;
		id_data_w(data);
	}

	if ((reg == REG_INTERRUPT_ENABLE) && m_operational)
		update_interrupt("interrupt enable write");
	if ((reg == REG_STATUS) && m_operational)
	{
		u16 const old_status = m_status;
		m_status &= data;
		DC323_LOGMASKED(LOG_INTERRUPTS, "%s %s: status clear data=%04X old=%04X new=%04X enable=%04X\n",
			machine().time().to_string(), tag(), data, old_status, m_status, m_registers[REG_INTERRUPT_ENABLE]);
		update_interrupt("status acknowledge");
	}
	if ((reg == REG_SCROLL_Y) && m_operational)
	{
		DC323_LOGMASKED(LOG_SCROLL, "%s %s: schedule scroll command=%04X pending=%u status=%04X enable=%04X\n",
			machine().time().to_string(), tag(), data, m_scroll_pending, m_status, m_registers[REG_INTERRUPT_ENABLE]);
		m_scroll_pending = true;
	}
	if (reg == REG_COMMAND)
		command_w(data);
}


void dc323_device::id_data_w(u16 data)
{
	if (!m_pbt_write_active)
		return;

	u16 const destination_x = m_registers[REG_DESTINATION_X] & 0x3fff;
	u16 const destination_y = m_registers[REG_DESTINATION_Y] & 0x3fff;
	u16 const width = m_registers[REG_WIDTH] & 0x1fff;
	u16 const height = m_registers[REG_HEIGHT] & 0x1fff;
	u32 const row = m_pbt_write_index / m_pbt_write_words_per_row;
	u32 const column = m_pbt_write_index % m_pbt_write_words_per_row;
	u16 const word_x = (destination_x & ~(m_pbt_write_bus_width - 1)) + column * m_pbt_write_bus_width;

	if (row < height && (destination_y + row) < BITMAP_HEIGHT)
	{
		for (unsigned plane = 0; plane < BITMAP_PLANES; plane++)
		{
			if (!BIT(m_viper_select, plane))
				continue;

			auto &viper = m_viper_registers[plane];
			switch (viper[VIPER_REG_CSR_BASE + (m_pbt_write_command & 7)] & 3)
			{
			case 1:
				viper[VIPER_REG_SOURCE] = data;
				break;
			case 2:
				viper[VIPER_REG_MASK_1] = data;
				viper[VIPER_REG_MASK_2] = data;
				break;
			case 3:
				viper[VIPER_REG_MASK_2] = data;
				break;
			}

			for (unsigned bit = 0; bit < m_pbt_write_bus_width; bit++)
			{
				u16 const x = word_x + bit;
				if (x < destination_x || x >= destination_x + width || x >= BITMAP_WIDTH)
					continue;
				write_viper_pixel(plane, x, destination_y + row, m_pbt_write_command,
					BIT(viper[VIPER_REG_SOURCE], bit));
			}
		}
	}

	m_pbt_write_index++;
	if (m_pbt_write_index >= m_pbt_write_count)
	{
		m_pbt_write_active = false;
		m_status |= STATUS_ADDRESS_COMPLETE;
		update_interrupt("processor-to-bitmap transfer complete");
	}
	DC323_LOGMASKED(LOG_TRANSFERS, "%s %s: I/D write index=%u/%u data=%04X active=%u status=%04X\n",
		machine().time().to_string(), tag(), m_pbt_write_index, m_pbt_write_count,
		data, m_pbt_write_active, m_status);
}


void dc323_device::operational_w(int state)
{
	bool const operational = bool(state);
	if (m_operational == operational)
		return;
	m_operational = operational;
	if (m_operational)
	{
		// Reset leaves the command and address engines idle.  Once the board
		// releases the DC323 for normal accesses, their three completion outputs
		// are therefore asserted until a command starts new work.  FIFO receive
		// ready remains clear until a bitmap-to-processor transfer supplies data.
		m_status |= STATUS_RASTEROP_MASK;
	}
	DC323_LOGMASKED(LOG_REGISTERS, "%s %s: operational=%u\n", machine().time().to_string(), tag(), m_operational);
	update_interrupt("operational input");
}


void dc323_device::viper_select_w(u8 data)
{
	u8 const select = data & 0x0f;
	if (m_viper_select == select)
		return;
	m_viper_select = select;
	DC323_LOGMASKED(LOG_REGISTERS, "%s %s: Viper select=%X\n",
		machine().time().to_string(), tag(), m_viper_select);
}


void dc323_device::frame_event()
{
	// Video timing runs continuously, but reset holds the command/status logic
	// inactive.  Do not latch stale frame service before the board releases the
	// DC323 into operational mode.
	if (!m_operational)
		return;

	u16 const old_status = m_status;
	bool const was_pending = m_scroll_pending;
	// At the frame boundary the indexes for the region already moved become
	// the old indexes, and the scroll process's pending values become the new
	// indexes.  Our scroll backend moves the complete region atomically at this
	// same boundary, so subsequent update operations use the new pair.
	m_registers[REG_OLD_X_INDEX] = m_registers[REG_NEW_X_INDEX];
	m_registers[REG_OLD_Y_INDEX] = m_registers[REG_NEW_Y_INDEX];
	m_registers[REG_NEW_X_INDEX] = m_registers[REG_PENDING_X_INDEX];
	m_registers[REG_NEW_Y_INDEX] = m_registers[REG_PENDING_Y_INDEX];
	execute_scroll();
	m_status |= STATUS_PAUSE_COMPLETE | STATUS_SCROLL_SERVICE;
	DC323_LOGMASKED(LOG_SCROLL, "%s %s: frame pending=%u->%u status=%04X->%04X enable=%04X\n",
		machine().time().to_string(), tag(), was_pending, m_scroll_pending,
		old_status, m_status, m_registers[REG_INTERRUPT_ENABLE]);
	update_interrupt("vertical frame");
}


u8 dc323_device::id_data_r()
{
	u16 const width = m_registers[REG_WIDTH] & 0x1fff;
	u32 const bytes_per_row = (width + 7) / 8;
	u32 const row = m_pbt_read_index / bytes_per_row;
	u32 const column = m_pbt_read_index % bytes_per_row;
	u16 const source_origin_x = m_registers[REG_SOURCE_X] & 0x3fff;
	u16 const source_origin_y = m_registers[REG_SOURCE_Y] & 0x1fff;
	u16 const source_x = source_origin_x + column * 8;
	u16 const source_y = source_origin_y + row;
	u8 data = 0;

	if (m_raster_diagnostic && (m_pbt_read_command == 0x0bc0))
		data = BIT(source_origin_x, 3) ? 0x55 : 0xaa;
	else if (!m_raster_diagnostic && (m_pbt_read_command == 0x0bc0))
		data = m_diagnostic_data;
	else if (BIT(source_origin_y, 12))
	{
		u16 const rom_x = source_x & 0x00ff;
		u16 const rom_y = source_y & 0x03ff;
		data = m_chargen_rom[(rom_y << 5) | (rom_x >> 3)];
	}
	else if ((source_x < BITMAP_WIDTH) && (source_y < BITMAP_HEIGHT))
	{
		// In X-mode BTP, the active source CSR's I/D-output bit chooses the
		// Viper plane that drives the shared processor bus.  Chip select can
		// disambiguate multiple identically programmed source CSRs.
		unsigned output_plane = 0;
		bool output_enabled = false;
		unsigned const csr = VIPER_REG_CSR_BASE + (m_pbt_read_command & 7);
		for (unsigned plane = 0; plane < BITMAP_PLANES; plane++)
		{
			if (BIT(m_viper_select, plane) && BIT(m_viper_registers[plane][csr], 4))
			{
				output_plane = plane;
				output_enabled = true;
				break;
			}
		}
		if (output_enabled)
			for (unsigned bit = 0; bit < 8 && (source_x + bit) < BITMAP_WIDTH; bit++)
				data |= (m_bitmap_planes[bitmap_plane_address(output_plane, source_x + bit, source_y)] & 1) << bit;
	}

	u32 const index = m_pbt_read_index++;
	if (m_pbt_read_index >= m_pbt_read_count)
	{
		m_pbt_read_active = false;
		m_status &= ~STATUS_ID_DATA_READY;
		m_status |= STATUS_ADDRESS_COMPLETE;
		update_interrupt("I/D transfer complete");
	}
	DC323_LOGMASKED(LOG_TRANSFERS, "%s %s: I/D read index=%u/%u data=%02X active=%u status=%04X\n",
		machine().time().to_string(), tag(), index, m_pbt_read_count, data, m_pbt_read_active, m_status);
	return data;
}


void dc323_device::command_w(u16 command)
{
	unsigned const operation = (command >> 8) & 3;
	u16 const old_status = m_status;
	DC323_LOGMASKED(LOG_COMMANDS, "%s %s: command=%04X operation=%u status=%04X operational=%u\n",
		machine().time().to_string(), tag(), command, operation, m_status, m_operational);

	if (m_operational && ((operation == 2) || (operation == 3)))
	{
		m_status &= ~STATUS_COMMAND_MASK;
		m_status |= STATUS_ID_DATA_TRANSMIT_READY;
		m_pbt_read_active = false;
		m_pbt_write_active = false;
	}
	else if (m_operational && (command == 0x0000))
	{
		// Command zero returns the command path to its idle state.  Firmware
		// uses it to terminate a diagnostic I/D sequence before polling Address
		// Output Complete.
		m_pbt_read_active = false;
		m_pbt_write_active = false;
		m_status &= ~(STATUS_ID_DATA_READY | STATUS_ID_DATA_TRANSMIT_READY);
		m_status |= STATUS_RASTEROP_MASK;
		update_interrupt("command abort");
	}

	if ((command & 0xffe0) == 0x0180)
	{
		unsigned const reg = command & 0x1f;
		for (unsigned plane = 0; plane < BITMAP_PLANES; plane++)
			if (BIT(m_viper_select, plane))
				m_viper_registers[plane][reg] = m_registers[REG_ID_DATA];
	}

	if ((operation == 3) && BIT(command, 11) && !BIT(command, 10))
	{
		u32 const width = m_registers[REG_WIDTH] & 0x1fff;
		u32 const height = m_registers[REG_HEIGHT] & 0x1fff;
		m_pbt_read_index = 0;
		m_pbt_read_command = command;
		m_pbt_read_count = ((width + 7) / 8) * height;
		m_pbt_read_active = m_pbt_read_count != 0;
		if (m_operational)
		{
			m_status |= STATUS_RASTEROP_INITIALIZED | STATUS_RASTEROP_COMPLETE;
			m_status |= m_pbt_read_active ? STATUS_ID_DATA_READY : STATUS_ADDRESS_COMPLETE;
		}
		DC323_LOGMASKED(LOG_TRANSFERS, "%s %s: PBT start width=%u height=%u count=%u active=%u status=%04X\n",
			machine().time().to_string(), tag(), width, height, m_pbt_read_count, m_pbt_read_active, m_status);
	}
	else if ((operation == 3) && !BIT(command, 11) && BIT(command, 10))
	{
		u16 const destination_x = m_registers[REG_DESTINATION_X] & 0x3fff;
		u16 const width = m_registers[REG_WIDTH] & 0x1fff;
		u16 const height = m_registers[REG_HEIGHT] & 0x1fff;
		u16 const bus_width_select = (m_viper_registers[0][VIPER_REG_BUS_WIDTH] >> 2) & 3;
		m_pbt_write_bus_width = (bus_width_select == 0) ? 4 : (bus_width_select == 3) ? 16 : 8;
		m_pbt_write_words_per_row = (width != 0) ?
			((destination_x & (m_pbt_write_bus_width - 1)) + width + m_pbt_write_bus_width - 1) / m_pbt_write_bus_width : 0;
		m_pbt_write_index = 0;
		m_pbt_write_count = m_pbt_write_words_per_row * height;
		m_pbt_write_command = command;
		m_pbt_write_active = m_pbt_write_count != 0;
		if (m_operational)
		{
			m_status |= STATUS_RASTEROP_INITIALIZED | STATUS_RASTEROP_COMPLETE;
			if (!m_pbt_write_active)
				m_status |= STATUS_ADDRESS_COMPLETE;
		}
		DC323_LOGMASKED(LOG_TRANSFERS, "%s %s: PTB start width=%u height=%u bus=%u words=%u active=%u status=%04X\n",
			machine().time().to_string(), tag(), width, height, m_pbt_write_bus_width,
			m_pbt_write_count, m_pbt_write_active, m_status);
	}

	execute_rasterop(command);
	if (m_operational && (operation == 2))
	{
		m_status |= STATUS_RASTEROP_MASK;
		update_interrupt("raster operation complete");
	}
	DC323_LOGMASKED(LOG_COMMANDS, "%s %s: command complete=%04X status=%04X->%04X\n",
		machine().time().to_string(), tag(), command, old_status, m_status);
}


void dc323_device::update_interrupt(char const *event)
{
	bool const state = m_operational && bool(m_status & m_registers[REG_INTERRUPT_ENABLE]);
	if (state != m_irq_state)
	{
		DC323_LOGMASKED(LOG_INTERRUPTS, "%s %s: IRQ %u->%u event=%s status=%04X enable=%04X\n",
			machine().time().to_string(), tag(), m_irq_state, state, event,
			m_status, m_registers[REG_INTERRUPT_ENABLE]);
		m_irq_state = state;
		m_irq_handler(state ? ASSERT_LINE : CLEAR_LINE);
	}
}


void dc323_device::execute_rasterop(u16 command)
{
	auto const signed_14 = [](u16 value)
	{
		value &= 0x3fff;
		return BIT(value, 13) ? int(value) - 0x4000 : int(value);
	};
	struct axis_sample
	{
		int destination;
		int source;
	};
	auto const scaled_axis = [](unsigned destination_length, u16 scale)
	{
		std::vector<axis_sample> result;
		unsigned const step = (scale & 0x1fff) + 1;
		unsigned accumulator = 0;
		unsigned source = 0;
		unsigned destination = 0;
		if (!BIT(scale, 13))
		{
			result.reserve(destination_length);
			while (destination < destination_length)
			{
				result.push_back({ int(destination++), int(source) });
				accumulator += step;
				if (accumulator >= 0x2000)
				{
					accumulator -= 0x2000;
					source++;
				}
			}
		}
		else
		{
			// During down scaling the source advances on every computation and
			// the destination advances only when the scale accumulator carries.
			while (destination < destination_length)
			{
				result.push_back({ int(destination), int(source++) });
				accumulator += step;
				if (accumulator >= 0x2000)
				{
					accumulator -= 0x2000;
					destination++;
				}
			}
		}
		return result;
	};

	bool const rasterop = ((command >> 8) & 3) == 2;
	bool const destination_enabled = BIT(command, 10);
	bool const source1_enabled = BIT(command, 11);
	bool const source2_enabled = BIT(command, 12);
	u16 const x_control = m_registers[REG_X_CONTROL];
	bool const normal_mode = ((x_control & 0x0003) == 0) && BIT(x_control, 7);
	bool const linear_pattern_mode = ((x_control & 0x0003) == 2) && BIT(x_control, 7);
	bool const fill_mode = ((x_control & 0x0003) == 3) && BIT(x_control, 7);
	if (!rasterop || !destination_enabled || source2_enabled)
		return;
	if (linear_pattern_mode && source1_enabled)
	{
		execute_linear_pattern(command);
		return;
	}
	if (fill_mode && !source1_enabled)
	{
		execute_fill(command);
		return;
	}
	if (!normal_mode)
		return;

	int source_x = m_registers[REG_SOURCE_X] & 0x3fff;
	int source_y = m_registers[REG_SOURCE_Y] & 0x3fff;
	int destination_x = m_registers[REG_DESTINATION_X] & 0x3fff;
	int destination_y = m_registers[REG_DESTINATION_Y] & 0x3fff;
	if (BIT(x_control, 5))
	{
		source_x = signed_14(source_x + m_registers[REG_NEW_X_INDEX]);
		source_y = signed_14(source_y + m_registers[REG_NEW_Y_INDEX]);
	}
	if (BIT(x_control, 6))
	{
		destination_x = signed_14(destination_x + m_registers[REG_NEW_X_INDEX]);
		destination_y = signed_14(destination_y + m_registers[REG_NEW_Y_INDEX]);
	}
	bool const source_is_e49 = source1_enabled && BIT(source_y, 12);
	int const destination_fast_dx = signed_14(m_registers[REG_WIDTH]);
	int const destination_fast_dy = signed_14(m_registers[REG_DESTINATION_FAST_DY]);
	int const destination_slow_dx = signed_14(m_registers[REG_DESTINATION_SLOW_DX]);
	int const destination_slow_dy = signed_14(m_registers[REG_HEIGHT]);
	auto const fast_path = raster_vector(destination_fast_dx, destination_fast_dy, BITMAP_HEIGHT);
	auto const slow_path = raster_vector(destination_slow_dx, destination_slow_dy, BITMAP_HEIGHT);
	unsigned const width = fast_path.size();
	unsigned const height = slow_path.size();
	int const source_x_step = BIT(m_registers[REG_SOURCE_FAST_DX], 13) ? -1 : 1;
	int const source_y_step = BIT(m_registers[REG_SOURCE_SLOW_DY], 13) ? -1 : 1;
	auto const fast_samples = scaled_axis(width, m_registers[REG_FAST_SCALE]);
	auto const slow_samples = scaled_axis(height, m_registers[REG_SLOW_SCALE]);
	bool const fill_holes = BIT(x_control, 4) && !source1_enabled;
	std::vector<bool> selected;
	std::array<int, BITMAP_HEIGHT> row_min;
	std::array<int, BITMAP_HEIGHT> row_max;
	if (fill_holes)
	{
		selected.resize(BITMAP_PLANE_SIZE);
		row_min.fill(BITMAP_WIDTH);
		row_max.fill(-1);
	}
	unsigned const function = (command >> 4) & 3;
	u8 const logic0 = u8(m_viper_registers[0][VIPER_REG_LOGIC_BASE + function]);
	DC323_LOGMASKED(LOG_RASTEROPS, "%s %s: raster command=%04X src=%d,%d dst=%d,%d size=%ux%u select=%X logic0=%02X s1=%u s2=%u\n",
		machine().time().to_string(), tag(), command, source_x, source_y,
		destination_x, destination_y, width, height, m_viper_select, logic0, source1_enabled, source2_enabled);
	if (source_is_e49 && (destination_x < 800) && (destination_y < 500) &&
		(width == 10) && (height == 20) && m_viper_select)
		m_video_operational = true;

	for (axis_sample const slow : slow_samples)
	{
		raster_point const slow_point = slow_path[slow.destination];
		int const source_pixel_y = source_y + slow.source * source_y_step;
		for (axis_sample const fast : fast_samples)
		{
			raster_point const fast_point = fast_path[fast.destination];
			int const pixel_x = destination_x + slow_point.x + fast_point.x;
			int const pixel_y = destination_y + slow_point.y + fast_point.y;
			int const source_pixel_x = source_x + fast.source * source_x_step;
			if (pixel_x < 0 || pixel_x >= BITMAP_WIDTH || pixel_y < 0 || pixel_y >= BITMAP_HEIGHT)
				continue;
			if (fill_holes)
			{
				selected[pixel_y * BITMAP_WIDTH + pixel_x] = true;
				row_min[pixel_y] = std::min(row_min[pixel_y], pixel_x);
				row_max[pixel_y] = std::max(row_max[pixel_y], pixel_x);
			}
			u16 const rom_x = source_pixel_x & 0x00ff;
			u16 const rom_y = source_pixel_y & 0x03ff;
			u8 const rom_source = source_is_e49 ? m_chargen_rom[(rom_y << 5) | (rom_x >> 3)] : 0;
			unsigned const word_bit = pixel_x & 15;
			for (unsigned plane = 0; plane < BITMAP_PLANES; plane++)
			{
				if (!BIT(m_viper_select, plane))
					continue;
				auto const &viper = m_viper_registers[plane];
				bool source_bit;
				if (!source1_enabled)
					source_bit = BIT(viper[VIPER_REG_SOURCE], word_bit);
				else if (source_is_e49)
					source_bit = BIT(rom_source, rom_x & 7);
				else if ((source_pixel_x >= 0) && (source_pixel_x < BITMAP_WIDTH) &&
					(source_pixel_y >= 0) && (source_pixel_y < BITMAP_HEIGHT))
					source_bit = m_bitmap_planes[bitmap_plane_address(plane, source_pixel_x, source_pixel_y)];
				else
					source_bit = false;
				write_viper_pixel(plane, pixel_x, pixel_y, command, source_bit);
			}
		}
	}

	// Hole fill modifies destination scanning so a broad parallelogram does
	// not retain gaps between independently generated fast-vector scans.  Keep
	// every original write (including duplicates important to complement
	// operations), then add only the missing pixels in each occupied scanline.
	// Source-coupled hole pixels require an address-generation rule that has
	// not yet been established, so this first bounded implementation applies
	// only to destination-only/constant-source operations.
	if (fill_holes)
	{
		for (unsigned y = 0; y < BITMAP_HEIGHT; y++)
			for (int x = row_min[y]; x <= row_max[y]; x++)
			{
				if (selected[y * BITMAP_WIDTH + x])
					continue;
				for (unsigned plane = 0; plane < BITMAP_PLANES; plane++)
				{
					if (!BIT(m_viper_select, plane))
						continue;
					auto const &viper = m_viper_registers[plane];
					write_viper_pixel(plane, x, y, command,
						BIT(viper[VIPER_REG_SOURCE], unsigned(x) & 15));
				}
			}
	}
}


void dc323_device::execute_linear_pattern(u16 command)
{
	auto const delta = [this](unsigned reg)
	{
		u16 const raw = m_registers[reg] & 0x3fff;
		return BIT(raw, 13) ? int(raw) - 0x4000 : int(raw);
	};
	auto const indexed_origin = [this](unsigned origin_reg, unsigned index_reg)
	{
		u16 const raw = (m_registers[origin_reg] + m_registers[index_reg]) & 0x3fff;
		return BIT(raw, 13) ? int(raw) - 0x4000 : int(raw);
	};

	int const source_fast_dx = delta(REG_SOURCE_FAST_DX);
	int const source_slow_dy = delta(REG_SOURCE_SLOW_DY);
	int const destination_fast_dx = delta(REG_WIDTH);
	int const destination_fast_dy = delta(REG_DESTINATION_FAST_DY);
	int const destination_slow_dx = delta(REG_DESTINATION_SLOW_DX);
	int const destination_slow_dy = delta(REG_HEIGHT);
	if (!source_fast_dx || !source_slow_dy)
		return;

	unsigned const source_width = unsigned(std::abs(source_fast_dx));
	unsigned const source_height = unsigned(std::abs(source_slow_dy));
	auto const fast_path = raster_vector(destination_fast_dx, destination_fast_dy, BITMAP_HEIGHT);
	auto const slow_path = raster_vector(destination_slow_dx, destination_slow_dy, BITMAP_HEIGHT);
	unsigned const destination_width = fast_path.size();
	unsigned const destination_height = slow_path.size();
	if (!destination_width || !destination_height)
		return;
	int const source_x_step = source_fast_dx < 0 ? -1 : 1;
	int const source_y_step = source_slow_dy < 0 ? -1 : 1;
	int source_origin_x = m_registers[REG_SOURCE_X] & 0x3fff;
	int source_origin_y = m_registers[REG_SOURCE_Y] & 0x3fff;
	int destination_origin_x = m_registers[REG_DESTINATION_X] & 0x3fff;
	int destination_origin_y = m_registers[REG_DESTINATION_Y] & 0x3fff;
	if (BIT(m_registers[REG_X_CONTROL], 5))
	{
		source_origin_x = indexed_origin(REG_SOURCE_X, REG_NEW_X_INDEX);
		source_origin_y = indexed_origin(REG_SOURCE_Y, REG_NEW_Y_INDEX);
	}
	if (BIT(m_registers[REG_X_CONTROL], 6))
	{
		destination_origin_x = indexed_origin(REG_DESTINATION_X, REG_NEW_X_INDEX);
		destination_origin_y = indexed_origin(REG_DESTINATION_Y, REG_NEW_Y_INDEX);
	}

	DC323_LOGMASKED(LOG_RASTEROPS, "%s %s: linear pattern command=%04X src=%d,%d pattern=%ux%u dst=%d,%d size=%ux%u select=%X\n",
		machine().time().to_string(), tag(), command, source_origin_x, source_origin_y,
		source_width, source_height, destination_origin_x, destination_origin_y,
		destination_width, destination_height, m_viper_select);

	for (unsigned y = 0; y < destination_height; y++)
	{
		raster_point const slow_point = slow_path[y];
		int const source_y = source_origin_y + int(y % source_height) * source_y_step;
		if (source_y < 0 || source_y >= BITMAP_HEIGHT)
			continue;
		for (unsigned x = 0; x < destination_width; x++)
		{
			raster_point const fast_point = fast_path[x];
			int const destination_x = destination_origin_x + slow_point.x + fast_point.x;
			int const destination_y = destination_origin_y + slow_point.y + fast_point.y;
			int const source_x = source_origin_x + int(x % source_width) * source_x_step;
			if (destination_x < 0 || destination_x >= BITMAP_WIDTH ||
				destination_y < 0 || destination_y >= BITMAP_HEIGHT ||
				source_x < 0 || source_x >= BITMAP_WIDTH)
				continue;
			for (unsigned plane = 0; plane < BITMAP_PLANES; plane++)
				if (BIT(m_viper_select, plane))
					write_viper_pixel(plane, destination_x, destination_y, command,
						m_bitmap_planes[bitmap_plane_address(plane, source_x, source_y)]);
		}
	}
}


void dc323_device::execute_fill(u16 command)
{
	auto const delta = [this](unsigned reg)
	{
		u16 const raw = m_registers[reg] & 0x3fff;
		return BIT(raw, 13) ? int(raw) - 0x4000 : int(raw);
	};

	u16 const x_control = m_registers[REG_X_CONTROL];
	bool const y_fill = BIT(x_control, 2);
	bool const baseline = BIT(x_control, 3);
	if (!m_fill_position_valid)
	{
		m_fill_a_x = m_registers[REG_DESTINATION_X] & 0x3fff;
		m_fill_a_y = m_registers[REG_DESTINATION_Y] & 0x1fff;
		m_fill_b_x = y_fill ? m_fill_a_x : int(m_registers[REG_SOURCE_X] & 0x3fff);
		m_fill_b_y = y_fill ? int(m_registers[REG_SOURCE_Y] & 0x1fff) : m_fill_a_y;
		m_fill_position_valid = true;
	}
	int const a_origin_x = m_fill_a_x;
	int const a_origin_y = m_fill_a_y;
	int const b_origin_x = m_fill_b_x;
	int const b_origin_y = m_fill_b_y;
	int const a_dx = delta(REG_DESTINATION_SLOW_DX);
	int const a_dy = delta(REG_HEIGHT);
	int const b_dx = delta(REG_SOURCE_FAST_DX);
	int const b_dy = delta(REG_SOURCE_SLOW_DY);
	auto const a_path = raster_vector(a_dx, a_dy, BITMAP_HEIGHT);
	auto const b_path = raster_vector(b_dx, b_dy, BITMAP_HEIGHT);

	DC323_LOGMASKED(LOG_RASTEROPS, "%s %s: fill command=%04X axis=%c baseline=%u A=%d,%d points=%zu B=%d,%d points=%zu select=%X\n",
		machine().time().to_string(), tag(), command, y_fill ? 'Y' : 'X', baseline,
		a_origin_x, a_origin_y, a_path.size(), b_origin_x, b_origin_y, b_path.size(), m_viper_select);

	auto const write_span = [this, command, y_fill](int fixed, int first, int last)
	{
		if (first > last)
			std::swap(first, last);
		for (int position = first; position <= last; position++)
		{
			int const x = y_fill ? fixed : position;
			int const y = y_fill ? position : fixed;
			if (x < 0 || x >= BITMAP_WIDTH || y < 0 || y >= BITMAP_HEIGHT)
				continue;
			for (unsigned plane = 0; plane < BITMAP_PLANES; plane++)
			{
				if (!BIT(m_viper_select, plane))
					continue;
				auto const &viper = m_viper_registers[plane];
				write_viper_pixel(plane, x, y, command,
					BIT(viper[VIPER_REG_SOURCE], unsigned(x) & 15));
			}
		}
	};

	if (baseline)
	{
		int const fixed_baseline = y_fill ? b_origin_y : b_origin_x;
		for (raster_point const a : a_path)
		{
			int const a_x = a_origin_x + a.x;
			int const a_y = a_origin_y + a.y;
			write_span(y_fill ? a_x : a_y, y_fill ? a_y : a_x, fixed_baseline);
		}
		m_fill_a_x += a_dx;
		m_fill_a_y += a_dy;
		return;
	}

	// In an ordinary two-edge fill both generators must advance on the same
	// perpendicular scan coordinate.  Equal-duration edge pairs may continue
	// across commands using the retained endpoints below.  Independent edge
	// expiration is deliberately left for later rather than inventing hold or
	// partial-generator behavior here.
	if (a_path.size() != b_path.size())
		return;
	unsigned const points = a_path.size();
	for (unsigned position = 0; position < points; position++)
		if ((!y_fill && (a_path[position].y != b_path[position].y)) ||
			(y_fill && (a_path[position].x != b_path[position].x)))
			return;
	for (unsigned position = 0; position < points; position++)
	{
		raster_point const a = a_path[position];
		raster_point const b = b_path[position];
		int const a_x = a_origin_x + a.x;
		int const a_y = a_origin_y + a.y;
		int const b_x = b_origin_x + b.x;
		int const b_y = b_origin_y + b.y;
		write_span(y_fill ? a_x : a_y, y_fill ? a_y : a_x, y_fill ? b_y : b_x);
	}
	m_fill_a_x += a_dx;
	m_fill_a_y += a_dy;
	m_fill_b_x += b_dx;
	m_fill_b_y += b_dy;
}


void dc323_device::write_viper_pixel(unsigned plane, unsigned x, unsigned y, u16 command, bool source_bit)
{
	auto const &viper = m_viper_registers[plane];
	unsigned const bus_width_select = (viper[VIPER_REG_BUS_WIDTH] >> 2) & 3;
	unsigned const bus_width = (bus_width_select == 0) ? 4 : (bus_width_select == 3) ? 16 : 8;
	unsigned const word_bit = x & (bus_width - 1);
	u8 const logic = u8(viper[VIPER_REG_LOGIC_BASE + ((command >> 4) & 3)]);
	bool mask1 = BIT(viper[VIPER_REG_MASK_1], word_bit);
	bool mask2 = BIT(viper[VIPER_REG_MASK_2], word_bit);
	if (BIT(logic, 4))
		mask1 = !mask1;
	if (BIT(logic, 5))
		mask2 = !mask2;
	if (!mask1 || !mask2)
		return;
	if (!BIT(logic, 6))
		source_bit = !source_bit;
	u32 const destination = bitmap_plane_address(plane, x, y);
	bool const destination_bit = m_bitmap_planes[destination];
	unsigned const logic_input = (destination_bit << 1) | source_bit;
	bool const select_foreground = BIT(logic, logic_input);
	unsigned const color_register = select_foreground ? VIPER_REG_FOREGROUND : VIPER_REG_BACKGROUND;
	m_bitmap_planes[destination] = BIT(viper[color_register], word_bit);
}


void dc323_device::execute_scroll()
{
	if (!m_scroll_pending)
		return;
	m_scroll_pending = false;

	u16 const scroll = m_registers[REG_SCROLL_Y];
	u16 const x_min = std::min<u16>(m_registers[REG_SCROLL_X_MIN] & 0x3ffc, BITMAP_WIDTH);
	u16 const x_max = std::min<u16>(m_registers[REG_SCROLL_X_MAX] & 0x3ffc, BITMAP_WIDTH);
	u16 const y_min = std::min<u16>(m_registers[REG_SCROLL_Y_MIN] & 0x1fff, BITMAP_HEIGHT);
	u16 const y_max = std::min<u16>(m_registers[REG_SCROLL_Y_MAX] & 0x1fff, BITMAP_HEIGHT);
	u16 const y_offset = m_registers[REG_SCROLL_Y_OFFSET] & 0x1fff;
	bool const erase = BIT(scroll, 13);
	u16 const distance = (y_min < y_max) ? std::min<u16>(scroll & 0x0fff, y_max - y_min) : 0;
	DC323_LOGMASKED(LOG_SCROLL, "%s %s: execute command=%04X down=%u distance=%u erase=%u x=%u..%u y=%u..%u offset=%u pending=0 status=%04X enable=%04X\n",
		machine().time().to_string(), tag(), scroll, BIT(scroll, 12), distance, erase,
		x_min, x_max, y_min, y_max, y_offset, m_status, m_registers[REG_INTERRUPT_ENABLE]);
	if ((x_min >= x_max) || (y_min >= y_max))
		return;

	for (unsigned plane = 0; plane < BITMAP_PLANES; plane++)
	{
		auto const &viper = m_viper_registers[plane];
		u16 const fill = viper[VIPER_REG_FILL];
		unsigned const bus_width_select = (viper[VIPER_REG_BUS_WIDTH] >> 2) & 3;
		u16 const scroll_word_width = (bus_width_select == 0) ? 4 : (bus_width_select == 3) ? 16 : 8;
		u16 const left_word = x_min & ~(scroll_word_width - 1);
		u16 const right_word = x_max & ~(scroll_word_width - 1);
		u16 const operation_x_min = erase ? x_min : left_word;
		u16 const operation_x_max = erase ? x_max : std::min<u16>(right_word + scroll_word_width, BITMAP_WIDTH);
		u16 const left_mask = viper[VIPER_REG_SCROLL_LEFT];
		u16 const right_mask = viper[VIPER_REG_SCROLL_RIGHT];
		auto const scrolls_x = [erase, left_word, right_word, scroll_word_width, left_mask, right_mask](u16 x)
		{
			if (erase)
				return true;
			unsigned const bit = x & (scroll_word_width - 1);
			if ((x >= left_word) && (x < left_word + scroll_word_width))
				return !BIT(left_mask, bit);
			if ((x >= right_word) && (x < right_word + scroll_word_width))
				return !BIT(right_mask, bit);
			return true;
		};

		auto const copy_row = [this, plane, operation_x_min, operation_x_max, y_offset, &scrolls_x](u16 destination_y, u16 source_y)
		{
			u16 const destination_bitmap_y = (destination_y + y_offset) & (BITMAP_HEIGHT - 1);
			u16 const source_bitmap_y = (source_y + y_offset) & (BITMAP_HEIGHT - 1);
			for (u16 x = operation_x_min; x < operation_x_max; x++)
				if (scrolls_x(x))
					m_bitmap_planes[bitmap_plane_address(plane, x, destination_bitmap_y)] =
						m_bitmap_planes[bitmap_plane_address(plane, x, source_bitmap_y)];
		};

		auto const fill_row = [this, plane, operation_x_min, operation_x_max, y_offset, fill, &scrolls_x](u16 device_y)
		{
			u16 const bitmap_y = (device_y + y_offset) & (BITMAP_HEIGHT - 1);
			for (u16 x = operation_x_min; x < operation_x_max; x++)
				if (scrolls_x(x))
					m_bitmap_planes[bitmap_plane_address(plane, x, bitmap_y)] = BIT(fill, x & 15);
		};

		if (erase)
		{
			for (u16 device_y = y_min; device_y < y_max; device_y++)
				fill_row(device_y);
		}
		else if (distance && BIT(scroll, 12))
		{
			for (u16 device_y = y_max - distance; device_y-- > y_min; )
				copy_row(device_y + distance, device_y);
			for (u16 device_y = y_min; device_y < y_min + distance; device_y++)
				fill_row(device_y);
		}
		else if (distance)
		{
			for (u16 device_y = y_min; device_y < y_max - distance; device_y++)
				copy_row(device_y, device_y + distance);
			for (u16 device_y = y_max - distance; device_y < y_max; device_y++)
				fill_row(device_y);
		}
	}
}


u8 dc323_device::pixel_r(unsigned plane, unsigned x, unsigned y) const
{
	return m_bitmap_planes[bitmap_plane_address(plane, x, y)];
}


void dc323_device::bitmap_clear(u8 data)
{
	std::fill_n(&m_bitmap_planes[0], BITMAP_PLANES * BITMAP_PLANE_SIZE, data);
}
