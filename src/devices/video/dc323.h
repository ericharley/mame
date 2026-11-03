// license:BSD-3-Clause
// copyright-holders:Harley Card
/***************************************************************************

    Digital Equipment Corporation DC323 Adder

    This device currently preserves the operational model first developed in
    the VT340 driver.  It includes the retained Viper register values and the
    bitmap operations needed by that model; the Viper chips remain candidates
    for a later, separate extraction.

***************************************************************************/

#ifndef MAME_VIDEO_DC323_H
#define MAME_VIDEO_DC323_H

#pragma once


class dc323_device : public device_t
{
public:
	enum register_number : unsigned
	{
		REG_INTERRUPT_ENABLE = 0x02,
		REG_STATUS = 0x03,
		REG_ID_DATA = 0x07,
		REG_COMMAND = 0x08,
		REG_X_CONTROL = 0x09,
		REG_SCROLL_X_MIN = 0x0e,
		REG_SCROLL_X_MAX = 0x0f,
		REG_SCROLL_Y_MIN = 0x10,
		REG_SCROLL_Y_MAX = 0x11,
		REG_SCROLL_Y_OFFSET = 0x13,
		REG_SCROLL_Y = 0x14,
		REG_NEW_X_INDEX = 0x17,
		REG_NEW_Y_INDEX = 0x18,
		REG_OLD_X_INDEX = 0x19,
		REG_OLD_Y_INDEX = 0x1a,
		REG_SOURCE_X = 0x22,
		REG_SOURCE_Y = 0x23,
		REG_DESTINATION_X = 0x24,
		REG_DESTINATION_Y = 0x25,
		REG_WIDTH = 0x26,
		REG_HEIGHT = 0x29
	};

	enum status_bit : u16
	{
		STATUS_PAUSE_COMPLETE = 0x0001,
		STATUS_SCROLL_SERVICE = 0x0002,
		STATUS_RASTEROP_INITIALIZED = 0x0004,
		STATUS_RASTEROP_COMPLETE = 0x0008,
		STATUS_ADDRESS_COMPLETE = 0x0010,
		STATUS_ID_DATA_READY = 0x0020,
		STATUS_ID_DATA_TRANSMIT_READY = 0x0040,
		STATUS_RASTEROP_MASK = STATUS_RASTEROP_INITIALIZED | STATUS_RASTEROP_COMPLETE | STATUS_ADDRESS_COMPLETE,
		STATUS_COMMAND_MASK = STATUS_RASTEROP_MASK | STATUS_ID_DATA_READY
	};

	static constexpr unsigned BITMAP_WIDTH = 1024;
	static constexpr unsigned BITMAP_HEIGHT = 2048;
	static constexpr unsigned BITMAP_PLANES = 4;
	static constexpr unsigned BITMAP_PLANE_SIZE = BITMAP_WIDTH * BITMAP_HEIGHT;

	dc323_device(machine_config const &mconfig, char const *tag, device_t *owner, u32 clock);

	auto irq_handler() { return m_irq_handler.bind(); }
	void set_chargen_tag(char const *tag) { m_chargen_rom.set_tag(tag); }
	void set_bitmap_tag(char const *tag) { m_bitmap_planes.set_tag(tag); }

	u8 read(offs_t offset);
	void write(offs_t offset, u16 data);
	void operational_w(int state);
	void vsync_w(int state);

	// Board compatibility and video-backend accessors.  These expose state,
	// but never CPU identity or firmware addresses, so policy remains outside.
	u16 register_r(offs_t offset) const { return m_registers[offset & 0x3f]; }
	u16 status_r() const { return m_status; }
	u16 interrupt_enable_r() const { return m_registers[REG_INTERRUPT_ENABLE]; }
	bool video_operational() const { return m_video_operational; }
	bool scroll_pending() const { return m_scroll_pending; }
	u8 pixel_r(unsigned plane, unsigned x, unsigned y) const;
	void bitmap_clear(u8 data = 0);

protected:
	virtual void device_start() override ATTR_COLD;
	virtual void device_reset() override ATTR_COLD;

private:
	enum : unsigned
	{
		VIPER_REG_BUS_WIDTH = 0x01,
		VIPER_REG_LOGIC_BASE = 0x04,
		VIPER_REG_MASK_1 = 0x08,
		VIPER_REG_MASK_2 = 0x09,
		VIPER_REG_SOURCE = 0x0a,
		VIPER_REG_FILL = 0x0b,
		VIPER_REG_SCROLL_LEFT = 0x0c,
		VIPER_REG_SCROLL_RIGHT = 0x0d
	};

	static constexpr u32 bitmap_plane_address(unsigned plane, unsigned x, unsigned y)
	{
		return plane * BITMAP_PLANE_SIZE + y * BITMAP_WIDTH + x;
	}

	u8 id_data_r();
	void command_w(u16 command);
	void execute_rasterop(u16 command);
	void execute_scroll();
	void update_interrupt(char const *event);

	required_region_ptr<u8> m_chargen_rom;
	memory_share_creator<u8> m_bitmap_planes;
	devcb_write_line m_irq_handler;

	std::array<u16, 0x40> m_registers{};
	std::array<u16, 0x20> m_viper_registers{};
	u16 m_status = 0;
	bool m_operational = false;
	bool m_scroll_pending = false;
	bool m_pbt_read_active = false;
	u32 m_pbt_read_index = 0;
	u32 m_pbt_read_count = 0;
	bool m_video_operational = false;
	bool m_irq_state = false;
	u32 m_log_events = 0;
};


DECLARE_DEVICE_TYPE(DC323, dc323_device)

#endif // MAME_VIDEO_DC323_H
