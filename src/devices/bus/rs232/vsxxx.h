// license:BSD-3-Clause
// copyright-holders:Eric Harley
#ifndef MAME_BUS_RS232_VSXXX_H
#define MAME_BUS_RS232_VSXXX_H

#pragma once

#include "rs232.h"

class vsxxx_mouse_device : public buffered_rs232_device<16>
{
public:
	vsxxx_mouse_device(machine_config const &mconfig, char const *tag, device_t *owner, uint32_t clock);

	DECLARE_INPUT_CHANGED_MEMBER(input_changed);

protected:
	virtual ioport_constructor device_input_ports() const override ATTR_COLD;
	virtual void device_start() override ATTR_COLD;
	virtual void received_byte(u8 byte) override;

private:
	TIMER_CALLBACK_MEMBER(power_up);
	TIMER_CALLBACK_MEMBER(report_tick);

	bool read_inputs();
	void send_report(u8 buttons);
	void send_self_test();
	void queue_buttons(u8 buttons);
	void clear_button_queue();

	required_ioport m_buttons;
	required_ioport m_x_axis;
	required_ioport m_y_axis;
	int16_t m_x_delta;
	int16_t m_y_delta;
	uint16_t m_x_val;
	uint16_t m_y_val;
	uint8_t m_btn_val;
	uint8_t m_btn_sent;
	bool m_stream_mode;
	emu_timer *m_report_timer;
	std::array<u8, 16> m_button_queue;
	u8 m_button_queue_head;
	u8 m_button_queue_count;
};

DECLARE_DEVICE_TYPE(VSXXX_MOUSE, vsxxx_mouse_device)

#endif // MAME_BUS_RS232_VSXXX_H
