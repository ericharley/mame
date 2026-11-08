// license:BSD-3-Clause
// copyright-holders:Eric Harley
/***************************************************************************

    Firmware-free regression harness for the DEC DC7051 device

***************************************************************************/

#include "emu.h"

#include "video/dc7051.h"

#include "emuopts.h"


namespace {

class dc7051_test_state : public driver_device
{
public:
	dc7051_test_state(machine_config const &mconfig, device_type type, char const *tag) :
		driver_device(mconfig, type, tag),
		m_dc7051(*this, "dc7051")
	{
	}

	void dc7051test(machine_config &config);

private:
	required_device<dc7051_device> m_dc7051;
	emu_timer *m_begin_timer = nullptr;
	emu_timer *m_diag_low_timer = nullptr;
	emu_timer *m_diag_high_timer = nullptr;
	emu_timer *m_autosave_exit_timer = nullptr;
	emu_timer *m_finish_timer = nullptr;
	emu_timer *m_reset_verify_timer = nullptr;
	u64 m_hsync_events = 0;
	u64 m_frame_events = 0;
	u64 m_scanline_events = 0;
	u64 m_pause_line_events = 0;
	u16 m_last_scanline = 0xffff;
	attotime m_first_hsync = attotime::never;
	attotime m_last_hsync = attotime::never;
	attotime m_first_frame = attotime::never;
	attotime m_last_frame = attotime::never;
	bool m_hsync_state = true;
	u32 m_seen_post_load_count = 0;
	bool m_reset_check = false;
	attotime m_reset_time = attotime::never;
	attotime m_reset_first_frame = attotime::never;

	virtual void machine_start() override ATTR_COLD;
	virtual void machine_reset() override ATTR_COLD;
	void require(bool condition, char const *message);
	void hsync_w(int state);
	void frame_event();
	void scanline_event(u16 line);
	TIMER_CALLBACK_MEMBER(begin_tests);
	TIMER_CALLBACK_MEMBER(check_diag_low);
	TIMER_CALLBACK_MEMBER(check_diag_high);
	TIMER_CALLBACK_MEMBER(exit_for_autosave);
	TIMER_CALLBACK_MEMBER(finish_tests);
	TIMER_CALLBACK_MEMBER(check_nonzero_reset);
};


void dc7051_test_state::machine_start()
{
	m_begin_timer = timer_alloc(FUNC(dc7051_test_state::begin_tests), this);
	m_diag_low_timer = timer_alloc(FUNC(dc7051_test_state::check_diag_low), this);
	m_diag_high_timer = timer_alloc(FUNC(dc7051_test_state::check_diag_high), this);
	m_autosave_exit_timer = timer_alloc(FUNC(dc7051_test_state::exit_for_autosave), this);
	m_finish_timer = timer_alloc(FUNC(dc7051_test_state::finish_tests), this);
	m_reset_verify_timer = timer_alloc(FUNC(dc7051_test_state::check_nonzero_reset), this);

	save_item(NAME(m_hsync_events));
	save_item(NAME(m_frame_events));
	save_item(NAME(m_scanline_events));
	save_item(NAME(m_pause_line_events));
	save_item(NAME(m_last_scanline));
	save_item(NAME(m_first_hsync));
	save_item(NAME(m_last_hsync));
	save_item(NAME(m_first_frame));
	save_item(NAME(m_last_frame));
	save_item(NAME(m_hsync_state));
	save_item(NAME(m_reset_check));
}


void dc7051_test_state::machine_reset()
{
	m_begin_timer->adjust(attotime::zero);
}


void dc7051_test_state::require(bool condition, char const *message)
{
	if (!condition)
		fatalerror("DC7051 device regression failed: %s\n", message);
}


void dc7051_test_state::hsync_w(int state)
{
	bool const asserted = bool(state);
	// device_post_load deliberately re-drives the saved external level.  That
	// callback restores pin state; it is not a new timing-generator edge.
	if (m_dc7051->post_load_count() != m_seen_post_load_count)
	{
		m_seen_post_load_count = m_dc7051->post_load_count();
		m_hsync_state = asserted;
		return;
	}
	if (m_reset_check)
	{
		m_hsync_state = asserted;
		return;
	}
	if (!m_hsync_events && machine().time().is_zero() && asserted)
	{
		m_hsync_state = true;
		return;
	}
	if (m_hsync_events)
		require(asserted != m_hsync_state, "horizontal output alternates polarity");
	m_hsync_state = asserted;
	if (!m_hsync_events)
		m_first_hsync = machine().time();
	m_last_hsync = machine().time();
	++m_hsync_events;
}


void dc7051_test_state::frame_event()
{
	if (m_reset_check)
	{
		if (m_reset_first_frame.is_never())
			m_reset_first_frame = machine().time();
		return;
	}
	if (!m_frame_events)
		m_first_frame = machine().time();
	m_last_frame = machine().time();
	++m_frame_events;
}


void dc7051_test_state::scanline_event(u16 line)
{
	if (m_reset_check)
		return;
	if (!m_scanline_events)
		require(line == 0, "scanline raster starts at device coordinate zero");
	else
		require(line == ((m_last_scanline + 1) % dc7051_device::VERTICAL_TOTAL),
			"scanline raster advances without skips or duplicates");
	m_last_scanline = line;
	++m_scanline_events;
	if (line == 500)
		++m_pause_line_events;
}


TIMER_CALLBACK_MEMBER(dc7051_test_state::begin_tests)
{
	for (unsigned reg = 0; reg < 16; reg++)
	{
		require(m_dc7051->low_r(reg) == 0, "low register reset value");
		require(m_dc7051->high_r(reg) == 0, "high register reset value");
	}
	m_dc7051->low_w(0x10, 0xa5);
	require(m_dc7051->low_r(0) == 0x05, "low register nibble and alias");
	m_dc7051->high_w(0x1f, 0xa5);
	require(m_dc7051->high_r(0x0f) == 0xa5, "high register byte and alias");
	require(m_dc7051->diagnostic_vsync_r() == 1, "diagnostic pulse starts high");

	m_diag_low_timer->adjust(attotime::from_usec(27));
	m_diag_high_timer->adjust(attotime::from_usec(16'698));
	attotime const frame_period = attotime::from_ticks(dc7051_device::FRAME_CLOCKS,
		dc7051_device::DOT_CLOCK);
	if (machine().options().autosave())
		m_autosave_exit_timer->adjust(frame_period * 100 + attotime::from_usec(1));
	m_finish_timer->adjust(frame_period * 2000 + attotime::from_nsec(1));
}


TIMER_CALLBACK_MEMBER(dc7051_test_state::check_diag_low)
{
	require(m_dc7051->diagnostic_vsync_r() == 0, "diagnostic pulse is 27 microseconds wide");
}


TIMER_CALLBACK_MEMBER(dc7051_test_state::check_diag_high)
{
	require(m_dc7051->diagnostic_vsync_r() == 1, "diagnostic pulse repeats after 16698 microseconds");
}


TIMER_CALLBACK_MEMBER(dc7051_test_state::exit_for_autosave)
{
	// Save at a known low horizontal level so the second process proves that
	// device_post_load re-drives the restored output rather than retaining the
	// reset-high level.
	require(!m_dc7051->hsync_asserted(), "autosave checkpoint has low horizontal output");
	machine().schedule_exit();
}


TIMER_CALLBACK_MEMBER(dc7051_test_state::finish_tests)
{
	constexpr u64 FRAMES = 2000;
	constexpr u64 HORIZONTAL_EVENTS = FRAMES * dc7051_device::FRAME_CLOCKS *
		dc7051_device::HORIZONTAL_TOGGLE_RATE / dc7051_device::DOT_CLOCK;
	require(m_frame_events == FRAMES, "2,000 frame events without loss or duplication");
	require(m_scanline_events == FRAMES * dc7051_device::VERTICAL_TOTAL + 1,
		"exactly one scanline event per raster line plus the initial origin");
	require(m_pause_line_events == FRAMES,
		"device coordinate 500 occurs exactly once per completed frame");
	require(m_hsync_events == HORIZONTAL_EVENTS,
		"horizontal compatibility output remains stable across screen-clock frames");
	require(m_first_hsync == attotime::from_hz(dc7051_device::HORIZONTAL_TOGGLE_RATE),
		"first horizontal transition phase");
	require(m_first_frame == attotime::from_ticks(dc7051_device::FRAME_CLOCKS,
		dc7051_device::DOT_CLOCK), "first frame phase follows the screen raster");
	require((m_last_hsync - m_first_hsync) ==
		attotime::from_hz(dc7051_device::HORIZONTAL_TOGGLE_RATE) * (m_hsync_events - 1),
		"horizontal period has no accumulated drift");
	require((m_last_frame - m_first_frame) ==
		attotime::from_ticks(dc7051_device::FRAME_CLOCKS, dc7051_device::DOT_CLOCK) * (m_frame_events - 1),
		"frame period has no accumulated drift");
	if (machine().options().autosave())
	{
		require(m_dc7051->post_load_count() == 1,
			"autosave continuation executes one device post-load restoration");
		require(!m_dc7051->post_load_hsync_asserted(),
			"post-load restores the saved low horizontal output");
		require(m_dc7051->low_r(0) == 0x05 && m_dc7051->high_r(0x0f) == 0xa5,
			"post-load retains register values");
	}

	m_reset_check = true;
	m_reset_time = machine().time();
	m_reset_first_frame = attotime::never;
	m_dc7051->reset();
	require(m_dc7051->low_r(0) == 0 && m_dc7051->high_r(0x0f) == 0,
		"reset restores register values");
	require(m_dc7051->hsync_asserted() && m_hsync_state,
		"nonzero-time reset restores horizontal output");
	require(m_dc7051->horizontal_transitions() == 0 && m_dc7051->frame_events() == 0,
		"nonzero-time reset clears timing counters");
	m_reset_verify_timer->adjust(attotime::from_ticks(dc7051_device::FRAME_CLOCKS,
		dc7051_device::DOT_CLOCK) + attotime::from_nsec(1));
}


TIMER_CALLBACK_MEMBER(dc7051_test_state::check_nonzero_reset)
{
	attotime const frame_period = attotime::from_ticks(dc7051_device::FRAME_CLOCKS,
		dc7051_device::DOT_CLOCK);
	constexpr u64 HORIZONTAL_EVENTS = u64(dc7051_device::FRAME_CLOCKS) *
		dc7051_device::HORIZONTAL_TOGGLE_RATE / dc7051_device::DOT_CLOCK;
	require(m_dc7051->frame_events() == 1 && m_reset_first_frame == m_reset_time + frame_period,
		"nonzero-time reset establishes a fresh first-frame phase");
	require(m_dc7051->horizontal_transitions() == HORIZONTAL_EVENTS,
		"nonzero-time reset establishes a fresh horizontal phase");

	osd_printf_info("DC7051 firmware-free timing/save-state regression passed: %llu horizontal transitions, %llu frames\n",
		(unsigned long long)m_hsync_events, (unsigned long long)m_frame_events);
	machine().schedule_exit();
}


void dc7051_test_state::dc7051test(machine_config &config)
{
	DC7051(config, m_dc7051, XTAL(dc7051_device::DOT_CLOCK));
	m_dc7051->hsync_handler().set(FUNC(dc7051_test_state::hsync_w));
	m_dc7051->set_frame_event_callback(FUNC(dc7051_test_state::frame_event));
	m_dc7051->set_scanline_event_callback(FUNC(dc7051_test_state::scanline_event));
}


static INPUT_PORTS_START(dc7051test)
INPUT_PORTS_END

ROM_START(dc7051test)
ROM_END

} // anonymous namespace


COMP(2026, dc7051test, 0, 0, dc7051test, dc7051test, dc7051_test_state, empty_init, "MAME", "DEC DC7051 device regression", MACHINE_NO_SOUND_HW | MACHINE_SUPPORTS_SAVE)
