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
	save_item(NAME(m_status));
	save_item(NAME(m_operational));
	save_item(NAME(m_scroll_pending));
	save_item(NAME(m_pbt_read_active));
	save_item(NAME(m_pbt_read_index));
	save_item(NAME(m_pbt_read_count));
	save_item(NAME(m_video_operational));
	save_item(NAME(m_irq_state));
}


void dc323_device::device_reset()
{
	m_registers.fill(0);
	m_viper_registers.fill(0);
	m_status = 0;
	m_operational = false;
	m_scroll_pending = false;
	m_pbt_read_active = false;
	m_pbt_read_index = 0;
	m_pbt_read_count = 0;
	m_video_operational = false;
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
	DC323_LOGMASKED(LOG_REGISTERS, "%s %s: W %02X=%04X status=%04X enable=%04X\n",
		machine().time().to_string(), tag(), reg, data, m_status, m_registers[REG_INTERRUPT_ENABLE]);
	m_registers[reg] = data;

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


void dc323_device::operational_w(int state)
{
	bool const operational = bool(state);
	if (m_operational == operational)
		return;
	m_operational = operational;
	DC323_LOGMASKED(LOG_REGISTERS, "%s %s: operational=%u\n", machine().time().to_string(), tag(), m_operational);
	update_interrupt("operational input");
}


void dc323_device::vsync_w(int state)
{
	if (!state)
		return;

	u16 const old_status = m_status;
	bool const was_pending = m_scroll_pending;
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

	if (BIT(source_origin_y, 12))
	{
		u16 const rom_x = source_x & 0x00ff;
		u16 const rom_y = source_y & 0x03ff;
		data = m_chargen_rom[(rom_y << 5) | (rom_x >> 3)];
	}
	else if ((source_x < BITMAP_WIDTH) && (source_y < BITMAP_HEIGHT))
	{
		for (unsigned bit = 0; bit < 8 && (source_x + bit) < BITMAP_WIDTH; bit++)
			data |= (m_bitmap_planes[bitmap_plane_address(0, source_x + bit, source_y)] & 1) << bit;
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
	}

	if ((command & 0xffe0) == 0x0180)
		m_viper_registers[command & 0x1f] = m_registers[REG_ID_DATA];

	if ((operation == 3) && BIT(command, 11) && !BIT(command, 10))
	{
		u32 const width = m_registers[REG_WIDTH] & 0x1fff;
		u32 const height = m_registers[REG_HEIGHT] & 0x1fff;
		m_pbt_read_index = 0;
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
	bool const rasterop = ((command >> 8) & 3) == 2;
	bool const destination_enabled = BIT(command, 10);
	bool const source1_enabled = BIT(command, 11);
	bool const source2_enabled = BIT(command, 12);
	u16 const x_control = m_registers[REG_X_CONTROL];
	bool const normal_mode = ((x_control & 0x001f) == 0) && BIT(x_control, 7);
	bool const indexed = BIT(x_control, 5) || BIT(x_control, 6);
	bool const zero_indexes = !(m_registers[REG_NEW_X_INDEX] |
		m_registers[REG_NEW_Y_INDEX] | m_registers[REG_OLD_X_INDEX] |
		m_registers[REG_OLD_Y_INDEX]);
	if (!rasterop || !destination_enabled || source2_enabled ||
		!normal_mode || (indexed && !zero_indexes))
		return;

	u16 const source_x = m_registers[REG_SOURCE_X] & 0x3fff;
	u16 const source_y = m_registers[REG_SOURCE_Y] & 0x1fff;
	bool const source_is_e49 = source1_enabled && BIT(source_y, 12);
	u16 const destination_x = m_registers[REG_DESTINATION_X] & 0x3fff;
	u16 const destination_y = m_registers[REG_DESTINATION_Y] & 0x3fff;
	u16 const width = std::min<u16>(m_registers[REG_WIDTH] & 0x1fff, BITMAP_WIDTH);
	u16 const height = std::min<u16>(m_registers[REG_HEIGHT] & 0x1fff, BITMAP_HEIGHT);
	u8 const logic = u8(m_viper_registers[VIPER_REG_LOGIC_BASE + ((command >> 4) & 3)]);
	DC323_LOGMASKED(LOG_RASTEROPS, "%s %s: raster command=%04X src=%u,%u dst=%u,%u size=%ux%u logic=%02X s1=%u s2=%u\n",
		machine().time().to_string(), tag(), command, source_x, source_y,
		destination_x, destination_y, width, height, logic, source1_enabled, source2_enabled);
	if (source_is_e49 && (destination_x < 800) && (destination_y < 500) &&
		(width == 10) && (height == 20))
		m_video_operational = true;

	for (u16 y = 0; y < height && (destination_y + y) < BITMAP_HEIGHT; y++)
	{
		for (u16 x = 0; x < width && (destination_x + x) < BITMAP_WIDTH; x++)
		{
			u16 const source_pixel_x = source_x + x;
			u16 const source_pixel_y = source_y + y;
			u16 const rom_x = source_pixel_x & 0x00ff;
			u16 const rom_y = source_pixel_y & 0x03ff;
			u8 const rom_source = source_is_e49 ? m_chargen_rom[(rom_y << 5) | (rom_x >> 3)] : 0;
			unsigned const word_bit = (destination_x + x) & 15;
			bool mask1 = BIT(m_viper_registers[VIPER_REG_MASK_1], word_bit);
			bool mask2 = BIT(m_viper_registers[VIPER_REG_MASK_2], word_bit);
			if (BIT(logic, 4))
				mask1 = !mask1;
			if (BIT(logic, 5))
				mask2 = !mask2;
			if (!mask1 || !mask2)
				continue;

			for (unsigned plane = 0; plane < BITMAP_PLANES; plane++)
			{
				u32 const destination = bitmap_plane_address(plane, destination_x + x, destination_y + y);
				bool source_bit;
				if (!source1_enabled)
					source_bit = BIT(m_viper_registers[VIPER_REG_SOURCE], word_bit);
				else if (source_is_e49)
					source_bit = BIT(rom_source, rom_x & 7);
				else if ((source_pixel_x < BITMAP_WIDTH) && (source_pixel_y < BITMAP_HEIGHT))
					source_bit = m_bitmap_planes[bitmap_plane_address(plane, source_pixel_x, source_pixel_y)];
				else
					source_bit = false;
				if (!BIT(logic, 6))
					source_bit = !source_bit;
				bool const destination_bit = m_bitmap_planes[destination];
				unsigned const logic_input = (destination_bit << 1) | source_bit;
				m_bitmap_planes[destination] = BIT(logic, logic_input);
			}
		}
	}
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
	u16 const fill = m_viper_registers[VIPER_REG_FILL];
	bool const erase = BIT(scroll, 13);
	u16 const distance = (y_min < y_max) ? std::min<u16>(scroll & 0x0fff, y_max - y_min) : 0;
	DC323_LOGMASKED(LOG_SCROLL, "%s %s: execute command=%04X down=%u distance=%u erase=%u x=%u..%u y=%u..%u offset=%u pending=0 status=%04X enable=%04X\n",
		machine().time().to_string(), tag(), scroll, BIT(scroll, 12), distance, erase,
		x_min, x_max, y_min, y_max, y_offset, m_status, m_registers[REG_INTERRUPT_ENABLE]);
	if ((x_min >= x_max) || (y_min >= y_max))
		return;

	unsigned const bus_width_select = (m_viper_registers[VIPER_REG_BUS_WIDTH] >> 2) & 3;
	u16 const scroll_word_width = (bus_width_select == 0) ? 4 : (bus_width_select == 3) ? 16 : 8;
	u16 const left_word = x_min & ~(scroll_word_width - 1);
	u16 const right_word = x_max & ~(scroll_word_width - 1);
	u16 const operation_x_min = erase ? x_min : left_word;
	u16 const operation_x_max = erase ? x_max : std::min<u16>(right_word + scroll_word_width, BITMAP_WIDTH);
	u16 const left_mask = m_viper_registers[VIPER_REG_SCROLL_LEFT];
	u16 const right_mask = m_viper_registers[VIPER_REG_SCROLL_RIGHT];
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

	auto const copy_row = [this, operation_x_min, operation_x_max, y_offset, &scrolls_x](u16 destination_y, u16 source_y)
	{
		u16 const destination_bitmap_y = (destination_y + y_offset) & (BITMAP_HEIGHT - 1);
		u16 const source_bitmap_y = (source_y + y_offset) & (BITMAP_HEIGHT - 1);
		for (u16 x = operation_x_min; x < operation_x_max; x++)
		{
			if (!scrolls_x(x))
				continue;
			for (unsigned plane = 0; plane < BITMAP_PLANES; plane++)
				m_bitmap_planes[bitmap_plane_address(plane, x, destination_bitmap_y)] =
					m_bitmap_planes[bitmap_plane_address(plane, x, source_bitmap_y)];
		}
	};

	auto const fill_row = [this, operation_x_min, operation_x_max, y_offset, fill, &scrolls_x](u16 device_y)
	{
		u16 const bitmap_y = (device_y + y_offset) & (BITMAP_HEIGHT - 1);
		for (u16 x = operation_x_min; x < operation_x_max; x++)
		{
			if (!scrolls_x(x))
				continue;
			for (unsigned plane = 0; plane < BITMAP_PLANES; plane++)
				m_bitmap_planes[bitmap_plane_address(plane, x, bitmap_y)] = BIT(fill, x & 15);
		}
	};

	if (erase)
	{
		for (u16 device_y = y_min; device_y < y_max; device_y++)
			fill_row(device_y);
		return;
	}
	if (!distance)
		return;

	if (BIT(scroll, 12))
	{
		for (u16 device_y = y_max - distance; device_y-- > y_min; )
			copy_row(device_y + distance, device_y);
		for (u16 device_y = y_min; device_y < y_min + distance; device_y++)
			fill_row(device_y);
	}
	else
	{
		for (u16 device_y = y_min; device_y < y_max - distance; device_y++)
			copy_row(device_y, device_y + distance);
		for (u16 device_y = y_max - distance; device_y < y_max; device_y++)
			fill_row(device_y);
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
