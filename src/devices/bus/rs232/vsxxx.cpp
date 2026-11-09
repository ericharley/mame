// license:BSD-3-Clause
// copyright-holders:Eric Harley
/***************************************************************************

    DEC VSXXX-AA serial mouse

    The VSXXX-AA is Digital Equipment Corporation's round three-button
    relative mouse, used with systems including the VT330/VT340 terminals
    and VAXstation/DECstation workstations.  It connects through a keyed
    seven-pin connector carrying RS-232 data, power and a device-present
    contact.

    Communication is asynchronous at 4,800 baud with one start bit, eight
    data bits, odd parity and one stop bit.  Prompt mode is selected at
    power-up.  The host may request a single position report, select
    incremental stream mode, return to prompt mode, or request self-test.
    A position report contains the three button states and signed relative
    X/Y movement in a three-byte packet.  Incremental mode samples motion at
    the documented 55 reports per second.  Power-up and the self-test command
    produce a four-byte identification and diagnostic report.

    This device models the documented external serial behavior.  Mouse
    motion and buttons are MAME inputs; the mechanical encoders and the
    mouse's internal control electronics are not separately emulated.  No
    source code from the Linux VSXXX driver is used here.

    Primary references:

    * VCB02 Video Subsystem Technical Manual, EK-104AA-TM-001,
      Appendix C, "Interactive Device Parameters".
      https://github.com/hackerb9/vt340test/blob/main/docs/kindred/
      EK-104AA-TM-001_VCB02_Video_Subsystem_Feb87.pdf

    * VSXXX-CA/CB Peripheral Repeater Technical Manual,
      EK-VSXPR-TM-001, Appendix A, "Peripheral Device Parameters".
      https://github.com/hackerb9/vt340test/blob/main/docs/kindred/
      EK-VSXPR-TM-001-mod.pdf

    Independent protocol cross-check and hardware test material:

    * Linux drivers/input/mouse/vsxxxaa.c (GPL-2.0-or-later).
      https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/
      tree/drivers/input/mouse/vsxxxaa.c

    * VT340 locator documentation and hardware-driven regression tests.
      https://github.com/hackerb9/vt340test/tree/main/locator

***************************************************************************/

#include "emu.h"
#include "vsxxx.h"

namespace {

INPUT_PORTS_START(vsxxx)
	PORT_START("BTN")
	PORT_BIT(0xfff8, IP_ACTIVE_HIGH, IPT_UNUSED)
	PORT_BIT(0x0004, IP_ACTIVE_HIGH, IPT_BUTTON1) PORT_NAME("Left Button") PORT_CODE(MOUSECODE_BUTTON1) PORT_CHANGED_MEMBER(DEVICE_SELF, FUNC(vsxxx_mouse_device::input_changed), 0)
	PORT_BIT(0x0002, IP_ACTIVE_HIGH, IPT_BUTTON3) PORT_NAME("Middle Button") PORT_CODE(MOUSECODE_BUTTON3) PORT_CHANGED_MEMBER(DEVICE_SELF, FUNC(vsxxx_mouse_device::input_changed), 0)
	PORT_BIT(0x0001, IP_ACTIVE_HIGH, IPT_BUTTON2) PORT_NAME("Right Button") PORT_CODE(MOUSECODE_BUTTON2) PORT_CHANGED_MEMBER(DEVICE_SELF, FUNC(vsxxx_mouse_device::input_changed), 0)

	PORT_START("X")
	PORT_BIT(0xf000, IP_ACTIVE_HIGH, IPT_UNUSED)
	PORT_BIT(0x0fff, 0x00, IPT_MOUSE_X) PORT_SENSITIVITY(100) PORT_KEYDELTA(0) PORT_CHANGED_MEMBER(DEVICE_SELF, FUNC(vsxxx_mouse_device::input_changed), 0)

	PORT_START("Y")
	PORT_BIT(0xf000, IP_ACTIVE_HIGH, IPT_UNUSED)
	PORT_BIT(0x0fff, 0x00, IPT_MOUSE_Y) PORT_SENSITIVITY(100) PORT_KEYDELTA(0) PORT_CHANGED_MEMBER(DEVICE_SELF, FUNC(vsxxx_mouse_device::input_changed), 0)
INPUT_PORTS_END

template <unsigned Bits, typename T>
std::make_signed_t<T> read_axis(ioport_port &port, T &value)
{
	static_assert((1U < Bits) && ((sizeof(T) * 8) > Bits), "invalid field bits");

	T const updated(T(std::make_unsigned_t<T>(port.read())) & make_bitmask<T>(Bits));
	std::make_signed_t<T> delta(std::make_signed_t<T>(updated) - std::make_signed_t<T>(value));
	if (std::make_signed_t<T>(std::make_unsigned_t<T>(1) << (Bits - 1)) <= delta)
		delta -= std::make_signed_t<T>(std::make_unsigned_t<T>(1) << Bits);
	else if (-std::make_signed_t<T>(std::make_unsigned_t<T>(1) << (Bits - 1)) >= delta)
		delta += std::make_signed_t<T>(std::make_unsigned_t<T>(1) << Bits);
	value = updated;
	return delta;
}

} // anonymous namespace

DEFINE_DEVICE_TYPE(VSXXX_MOUSE, vsxxx_mouse_device, "vsxxx_mouse", "DEC VSXXX-AA Mouse")

INPUT_CHANGED_MEMBER(vsxxx_mouse_device::input_changed)
{
	read_inputs();
}

vsxxx_mouse_device::vsxxx_mouse_device(machine_config const &mconfig, char const *tag, device_t *owner, uint32_t clock)
	: buffered_rs232_device<16>(mconfig, VSXXX_MOUSE, tag, owner, clock)
	, m_buttons(*this, "BTN")
	, m_x_axis(*this, "X")
	, m_y_axis(*this, "Y")
	, m_x_delta(0)
	, m_y_delta(0)
	, m_x_val(0U)
	, m_y_val(0U)
	, m_btn_val(0U)
	, m_btn_sent(0U)
	, m_stream_mode(false)
	, m_report_timer(nullptr)
	, m_button_queue{}
	, m_button_queue_head(0U)
	, m_button_queue_count(0U)
{
}

ioport_constructor vsxxx_mouse_device::device_input_ports() const
{
	return INPUT_PORTS_NAME(vsxxx);
}

void vsxxx_mouse_device::device_start()
{
	buffered_rs232_device<16>::device_start();

	save_item(NAME(m_x_delta));
	save_item(NAME(m_y_delta));
	save_item(NAME(m_x_val));
	save_item(NAME(m_y_val));
	save_item(NAME(m_btn_val));
	save_item(NAME(m_btn_sent));
	save_item(NAME(m_stream_mode));
	save_item(NAME(m_button_queue));
	save_item(NAME(m_button_queue_head));
	save_item(NAME(m_button_queue_count));

	set_data_frame(1, 8, PARITY_ODD, STOP_BITS_1);
	set_rate(4'800);
	receive_register_reset();
	transmit_register_reset();

	m_x_delta = m_y_delta = 0;
	m_x_val = m_y_val = 0U;
	m_btn_val = m_btn_sent = 0U;
	m_stream_mode = false;
	clear_button_queue();
	m_report_timer = timer_alloc(FUNC(vsxxx_mouse_device::report_tick), this);
	m_report_timer->adjust(attotime::from_hz(55), 0, attotime::from_hz(55));

	machine().scheduler().synchronize(timer_expired_delegate(FUNC(vsxxx_mouse_device::power_up), this));
}

void vsxxx_mouse_device::received_byte(u8 byte)
{
	switch (byte & 0x7f)
	{
	case 'R':
		read_inputs();
		m_x_delta = 0;
		m_y_delta = 0;
		clear_button_queue();
		m_btn_sent = m_btn_val;
		m_stream_mode = true;
		send_report(m_btn_val);
		break;

	case 'D':
		m_stream_mode = false;
		clear_button_queue();
		break;

	case 'P':
		m_stream_mode = false;
		clear_button_queue();
		read_inputs();
		send_report(m_btn_val);
		break;

	case 'T':
		m_stream_mode = false;
		clear_button_queue();
		clear_fifo();
		send_self_test();
		break;

	case 'S':
	default:
		break;
	}
}

TIMER_CALLBACK_MEMBER(vsxxx_mouse_device::power_up)
{
	read_inputs();
	m_x_delta = m_y_delta = 0;
	m_btn_sent = m_btn_val;
	send_self_test();
}

TIMER_CALLBACK_MEMBER(vsxxx_mouse_device::report_tick)
{
	bool const changed = read_inputs();
	if (!m_stream_mode || !changed || !fifo_empty() || !is_transmit_register_empty())
		return;

	if (m_button_queue_count)
	{
		u8 const buttons = m_button_queue[m_button_queue_head];
		m_button_queue_head = (m_button_queue_head + 1U) % m_button_queue.size();
		--m_button_queue_count;
		send_report(buttons);
	}
	else
		send_report(m_btn_val);
}

bool vsxxx_mouse_device::read_inputs()
{
	m_x_delta += read_axis<12>(*m_x_axis, m_x_val);
	m_y_delta -= read_axis<12>(*m_y_axis, m_y_val);
	u8 const buttons = m_buttons->read() & 0x07U;
	if (buttons != m_btn_val)
	{
		m_btn_val = buttons;
		if (m_stream_mode)
			queue_buttons(buttons);
	}
	return m_x_delta || m_y_delta || m_button_queue_count || (m_btn_val != m_btn_sent);
}

void vsxxx_mouse_device::send_report(u8 buttons)
{
	int16_t const x = std::clamp<int16_t>(m_x_delta, -127, 127);
	int16_t const y = std::clamp<int16_t>(m_y_delta, -127, 127);
	m_x_delta -= x;
	m_y_delta -= y;

	transmit_byte(0x80U | ((x > 0) ? 0x10U : 0U) | ((y > 0) ? 0x08U : 0U) | buttons);
	transmit_byte(std::abs(x));
	transmit_byte(std::abs(y));
	m_btn_sent = buttons;
}

void vsxxx_mouse_device::queue_buttons(u8 buttons)
{
	if (m_button_queue_count < m_button_queue.size())
	{
		u8 const tail = (m_button_queue_head + m_button_queue_count) % m_button_queue.size();
		m_button_queue[tail] = buttons;
		++m_button_queue_count;
	}
}

void vsxxx_mouse_device::clear_button_queue()
{
	m_button_queue.fill(0U);
	m_button_queue_head = 0U;
	m_button_queue_count = 0U;
}

void vsxxx_mouse_device::send_self_test()
{
	transmit_byte(0xa0U);
	transmit_byte(0x02U);
	transmit_byte(0x00U);
	transmit_byte(m_buttons->read() & 0x07U);
}
