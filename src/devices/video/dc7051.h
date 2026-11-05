// license:BSD-3-Clause
// copyright-holders:Harley Card
/***************************************************************************

    Digital Equipment Corporation DC7051 video timing generator

***************************************************************************/

#ifndef MAME_VIDEO_DC7051_H
#define MAME_VIDEO_DC7051_H

#pragma once


class dc7051_device : public device_t
{
public:
	using frame_event_delegate = device_delegate<void ()>;

	static constexpr u32 DOT_CLOCK = 32'317'400;
	static constexpr u32 HORIZONTAL_TOGGLE_RATE = 63'000;
	static constexpr u32 HORIZONTAL_TOTAL = 1026;
	static constexpr u32 VERTICAL_TOTAL = 526;
	static constexpr u32 FRAME_CLOCKS = HORIZONTAL_TOTAL * VERTICAL_TOTAL;
	static constexpr u32 VISIBLE_WIDTH = 800;
	static constexpr u32 VISIBLE_HEIGHT = 500;

	dc7051_device(machine_config const &mconfig, char const *tag, device_t *owner, u32 clock);

	auto hsync_handler() { return m_hsync_handler.bind(); }
	template <typename... T> void set_frame_event_callback(T &&... args)
	{
		m_frame_event_callback.set(std::forward<T>(args)...);
	}

	u8 low_r(offs_t offset) const { return m_low[offset & 0x0f] & 0x0f; }
	void low_w(offs_t offset, u8 data);
	u8 high_r(offs_t offset) const { return m_high[offset & 0x0f]; }
	void high_w(offs_t offset, u8 data);

	// Narrow vertical diagnostic output currently used by the external VT340
	// test multiplexer.  This preserves the established POST waveform pending
	// decoding of the physical DC7051 output and mux input.
	int diagnostic_vsync_r() const;
	u16 raster_line_r() const;

	bool hsync_asserted() const { return m_hsync_asserted; }
	u64 horizontal_transitions() const { return m_horizontal_transitions; }
	u64 frame_events() const { return m_frame_events; }
	u32 post_load_count() const { return m_post_load_count; }
	bool post_load_hsync_asserted() const { return m_post_load_hsync_asserted; }

protected:
	virtual void device_start() override ATTR_COLD;
	virtual void device_reset() override ATTR_COLD;
	virtual void device_post_load() override;

private:
	TIMER_CALLBACK_MEMBER(horizontal_tick);
	TIMER_CALLBACK_MEMBER(frame_tick);

	devcb_write_line m_hsync_handler;
	frame_event_delegate m_frame_event_callback;
	emu_timer *m_horizontal_timer = nullptr;
	emu_timer *m_frame_timer = nullptr;
	std::array<u8, 16> m_low{};
	std::array<u8, 16> m_high{};
	bool m_hsync_asserted = true;
	u64 m_horizontal_transitions = 0;
	u64 m_frame_events = 0;
	u32 m_post_load_count = 0;
	bool m_post_load_hsync_asserted = true;
	u32 m_log_events = 0;
};


DECLARE_DEVICE_TYPE(DC7051, dc7051_device)

#endif // MAME_VIDEO_DC7051_H
