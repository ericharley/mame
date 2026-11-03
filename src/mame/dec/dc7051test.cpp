// license:BSD-3-Clause
// copyright-holders:Harley Card
/***************************************************************************

    Firmware-free regression harness for the DEC DC7051 device

***************************************************************************/

#include "emu.h"

#include "video/dc7051.h"


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
	emu_timer *m_finish_timer = nullptr;
	u64 m_hsync_events = 0;
	u64 m_frame_events = 0;
	attotime m_first_hsync = attotime::never;
	attotime m_last_hsync = attotime::never;
	attotime m_first_frame = attotime::never;
	attotime m_last_frame = attotime::never;
	bool m_hsync_state = true;
	bool m_reset_check = false;

	virtual void machine_start() override ATTR_COLD;
	virtual void machine_reset() override ATTR_COLD;
	void require(bool condition, char const *message);
	void hsync_w(int state);
	void frame_w(int state);
	TIMER_CALLBACK_MEMBER(begin_tests);
	TIMER_CALLBACK_MEMBER(check_diag_low);
	TIMER_CALLBACK_MEMBER(check_diag_high);
	TIMER_CALLBACK_MEMBER(finish_tests);
};


void dc7051_test_state::machine_start()
{
	m_begin_timer = timer_alloc(FUNC(dc7051_test_state::begin_tests), this);
	m_diag_low_timer = timer_alloc(FUNC(dc7051_test_state::check_diag_low), this);
	m_diag_high_timer = timer_alloc(FUNC(dc7051_test_state::check_diag_high), this);
	m_finish_timer = timer_alloc(FUNC(dc7051_test_state::finish_tests), this);
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


void dc7051_test_state::frame_w(int state)
{
	require(state == 1, "frame callback is a high event");
	if (!m_frame_events)
		m_first_frame = machine().time();
	m_last_frame = machine().time();
	++m_frame_events;
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

	m_dc7051->frame_enable_w(1);
	require(m_dc7051->frame_enabled(), "compatibility frame scheduling enabled");
	m_diag_low_timer->adjust(attotime::from_usec(27));
	m_diag_high_timer->adjust(attotime::from_usec(16'698));
	attotime const frame_period = attotime::from_ticks(dc7051_device::VERTICAL_TOTAL,
		dc7051_device::HORIZONTAL_RATE);
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


TIMER_CALLBACK_MEMBER(dc7051_test_state::finish_tests)
{
	constexpr u64 FRAMES = 2000;
	constexpr u64 TOGGLES_PER_FRAME = dc7051_device::VERTICAL_TOTAL * 2;
	require(m_frame_events == FRAMES, "2,000 frame events without loss or duplication");
	require(m_hsync_events == FRAMES * TOGGLES_PER_FRAME,
		"horizontal and frame schedules retain the 1,052:1 relationship");
	require(m_first_hsync == attotime::from_hz(dc7051_device::HORIZONTAL_TOGGLE_RATE),
		"first horizontal transition phase");
	require(m_first_frame == attotime::from_ticks(dc7051_device::VERTICAL_TOTAL,
		dc7051_device::HORIZONTAL_RATE), "first frame phase");
	require((m_last_hsync - m_first_hsync) ==
		attotime::from_hz(dc7051_device::HORIZONTAL_TOGGLE_RATE) * (m_hsync_events - 1),
		"horizontal period has no accumulated drift");
	require((m_last_frame - m_first_frame) ==
		attotime::from_ticks(dc7051_device::VERTICAL_TOTAL, dc7051_device::HORIZONTAL_RATE) * (m_frame_events - 1),
		"frame period has no accumulated drift");

	m_dc7051->frame_enable_w(0);
	require(!m_dc7051->frame_enabled(), "frame scheduling disables cleanly");
	m_reset_check = true;
	m_dc7051->reset();
	require(m_dc7051->low_r(0) == 0 && m_dc7051->high_r(0x0f) == 0,
		"reset restores register values");
	require(m_dc7051->hsync_asserted() && !m_dc7051->frame_enabled(),
		"reset restores timing outputs and disables frames");

	osd_printf_info("DC7051 firmware-free timing regression passed: %llu horizontal transitions, %llu frames\n",
		(unsigned long long)m_hsync_events, (unsigned long long)m_frame_events);
	machine().schedule_exit();
}


void dc7051_test_state::dc7051test(machine_config &config)
{
	DC7051(config, m_dc7051, XTAL(dc7051_device::DOT_CLOCK));
	m_dc7051->hsync_handler().set(FUNC(dc7051_test_state::hsync_w));
	m_dc7051->frame_handler().set(FUNC(dc7051_test_state::frame_w));
}


static INPUT_PORTS_START(dc7051test)
INPUT_PORTS_END

ROM_START(dc7051test)
ROM_END

} // anonymous namespace


COMP(2026, dc7051test, 0, 0, dc7051test, dc7051test, dc7051_test_state, empty_init, "MAME", "DEC DC7051 device regression", MACHINE_NO_SOUND_HW)
