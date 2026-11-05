// license:BSD-3-Clause
// copyright-holders:Harley Card
/***************************************************************************

    Digital Equipment Corporation DC7051 video timing generator

    The initial device preserves the VT340 driver's fixed timing waveforms.
    Register decoding and a counter-derived programmable raster remain later
    hardware-fidelity work.

***************************************************************************/

#include "emu.h"
#include "dc7051.h"

#define LOG_REGISTERS (1U << 1)
#define LOG_TIMING    (1U << 2)
#define LOG_SYNC      (1U << 3)
#define LOG_TESTMUX   (1U << 4)
#define LOG_RESET     (1U << 5)

#define VERBOSE (0)
#include "logmacro.h"

#define DC7051_LOG_LIMIT 100000U
#define DC7051_LOGMASKED(mask, ...) \
	do { \
		if (VERBOSE & (mask)) \
		{ \
			if (m_log_events < DC7051_LOG_LIMIT) \
				(LOG_OUTPUT_FUNC)(__VA_ARGS__); \
			else if (m_log_events == DC7051_LOG_LIMIT) \
				(LOG_OUTPUT_FUNC)("%s %s: diagnostic log limit reached\n", machine().time().to_string(), tag()); \
			if (m_log_events <= DC7051_LOG_LIMIT) \
				++m_log_events; \
		} \
	} while (false)


DEFINE_DEVICE_TYPE(DC7051, dc7051_device, "dc7051", "DEC DC7051 Video Timing Generator")


dc7051_device::dc7051_device(machine_config const &mconfig, char const *tag, device_t *owner, u32 clock) :
	device_t(mconfig, DC7051, tag, owner, clock),
	m_hsync_handler(*this),
	m_frame_event_callback(*this),
	m_scanline_event_callback(*this)
{
}


void dc7051_device::device_start()
{
	m_horizontal_timer = timer_alloc(FUNC(dc7051_device::horizontal_tick), this);
	m_scanline_timer = timer_alloc(FUNC(dc7051_device::scanline_tick), this);
	m_frame_timer = timer_alloc(FUNC(dc7051_device::frame_tick), this);
	m_frame_event_callback.resolve_safe();
	m_scanline_event_callback.resolve_safe();

	save_item(NAME(m_low));
	save_item(NAME(m_high));
	save_item(NAME(m_hsync_asserted));
	save_item(NAME(m_horizontal_transitions));
	save_item(NAME(m_frame_events));
}


void dc7051_device::device_reset()
{
	m_low.fill(0);
	m_high.fill(0);
	m_hsync_asserted = true;
	m_horizontal_transitions = 0;
	m_frame_events = 0;
	m_log_events = 0;
	m_hsync_handler(ASSERT_LINE);
	m_horizontal_timer->adjust(attotime::from_hz(HORIZONTAL_TOGGLE_RATE), 0,
		attotime::from_hz(HORIZONTAL_TOGGLE_RATE));
	m_scanline_timer->adjust(attotime::zero, 0,
		attotime::from_ticks(HORIZONTAL_TOTAL, clock()));
	// Use the same Y1 dot-clock epoch and raster totals as the visible screen.
	// CPU2 T0 remains on its independently verified compatibility waveform
	// until the physical horizontal output is identified.
	attotime const frame_period = attotime::from_ticks(FRAME_CLOCKS, clock());
	m_frame_timer->adjust(frame_period, 0, frame_period);
	DC7051_LOGMASKED(LOG_RESET, "%s %s: reset clock=%u horizontal_toggle=%u frame_period=%s\n",
		machine().time().to_string(), tag(), clock(), HORIZONTAL_TOGGLE_RATE,
		frame_period.to_string());
}


void dc7051_device::device_post_load()
{
	// Timers and counters are restored by the scheduler/save system.  Re-drive
	// the one persistent external level; a frame is an event and must not be
	// replayed merely because state was loaded.
	++m_post_load_count;
	m_post_load_hsync_asserted = m_hsync_asserted;
	m_hsync_handler(m_hsync_asserted ? ASSERT_LINE : CLEAR_LINE);
}


void dc7051_device::low_w(offs_t offset, u8 data)
{
	unsigned const reg = offset & 0x0f;
	u8 const old = m_low[reg];
	m_low[reg] = data & 0x0f;
	DC7051_LOGMASKED(LOG_REGISTERS, "%s %s: low W %X=%X old=%X\n",
		machine().time().to_string(), tag(), reg, m_low[reg], old);
}


void dc7051_device::high_w(offs_t offset, u8 data)
{
	unsigned const reg = offset & 0x0f;
	u8 const old = m_high[reg];
	m_high[reg] = data;
	DC7051_LOGMASKED(LOG_REGISTERS, "%s %s: high W %X=%02X old=%02X\n",
		machine().time().to_string(), tag(), reg, data, old);
}


int dc7051_device::diagnostic_vsync_r() const
{
	// Preserve the original 27 us high interval in a 16.698 ms period.  These
	// constants are measured compatibility behavior, not decoded register
	// fields or a claimed physical VSYNC width.
	u64 const phase = machine().time().as_ticks(1'000'000) % 16'698;
	return phase < 27;
}


u16 dc7051_device::raster_line_r() const
{
	if (!m_frame_timer)
		return 0;
	u64 const remaining = std::min<u64>(m_frame_timer->remaining().as_ticks(clock()), FRAME_CLOCKS);
	u64 const phase = (FRAME_CLOCKS - remaining) % FRAME_CLOCKS;
	return u16(phase / HORIZONTAL_TOTAL);
}


TIMER_CALLBACK_MEMBER(dc7051_device::horizontal_tick)
{
	bool const old = m_hsync_asserted;
	m_hsync_asserted = !m_hsync_asserted;
	++m_horizontal_transitions;
	m_hsync_handler(m_hsync_asserted ? ASSERT_LINE : CLEAR_LINE);
	DC7051_LOGMASKED(LOG_SYNC, "%s %s: signal=hsync old=%u new=%u transition=%llu\n",
		machine().time().to_string(), tag(), old, m_hsync_asserted,
		(unsigned long long)m_horizontal_transitions);
}


TIMER_CALLBACK_MEMBER(dc7051_device::scanline_tick)
{
	// Scroll and pause comparisons use the video generator's dot-clock raster,
	// not the provisional 63 kHz compatibility waveform on the external
	// horizontal output.  Keeping this event on the exact 1026-dot cadence also
	// prevents phase drift at the frame boundary.
	m_scanline_event_callback(raster_line_r());
}


TIMER_CALLBACK_MEMBER(dc7051_device::frame_tick)
{
	++m_frame_events;
	DC7051_LOGMASKED(LOG_SYNC, "%s %s: signal=frame old=0 new=1 event=%llu register_context=compatibility\n",
		machine().time().to_string(), tag(), (unsigned long long)m_frame_events);
	m_frame_event_callback();
}
