// license:BSD-3-Clause
// copyright-holders:Harley Card
/***************************************************************************

    Digital Equipment Corporation VT340

    First-stage, ROM-level hardware reconstruction.  This driver deliberately
    contains only circuitry established by the terminal-control-module
    schematic and ROM-cartridge wiring.  In particular, it does not emulate
    terminal protocols or video in software.

    Terminal control module (54-16965-01):
      E57  Intel 8031, processor 1 (see upper-IDATA compatibility note)
      E24  Intel 8031, processor 2
      Y2   12 MHz oscillator feeding CPUACLK/CPUBCLK

    Cartridge program buses:
      CPU 1: E1 at 0000-7fff, E2 at 8000-ffff
      CPU 2: E3 at 0000-7fff, E4/E5 banked at 8000-ffff

    The published cartridge dumps are displaced by one byte: byte 1 is the
    byte at EPROM address 0.  Rotating each image while loading restores the
    reset vectors and every cross-ROM entry point.  This is consistent with
    the original Arduino reader sampling immediately after changing its
    address outputs, without an EPROM access-time delay.

    The processor-2 INT1/P3.3 latch is ROMBANK1 L.  Controlled execution of
    the five-27256 cartridge establishes its effective mapping: E4 is selected
    when the latch is high and E5 when it is low.

***************************************************************************/

#include "emu.h"

#include "cpu/mcs51/i8051.h"
#include "cpu/mcs51/i8052.h"
#include "machine/mc68681.h"
#include "machine/scn_pci.h"

#include "screen.h"

#define LOG_PORTS (1U << 1)
#define LOG_XDATA (1U << 2)

// Enable LOG_PORTS | LOG_XDATA in a local diagnostic build.
#define VERBOSE (0)
#include "logmacro.h"


namespace {

constexpr int MCS51_SFR_SPACE = 4;
constexpr int MCS51_IDATA_SPACE = 5;
constexpr int CPU_T1_HANDSHAKE_TRIGGER = 340;
constexpr unsigned BITMAP_WIDTH = 1024;
constexpr unsigned BITMAP_HEIGHT = 2048;
constexpr unsigned BITMAP_PLANE_SIZE = BITMAP_WIDTH * BITMAP_HEIGHT;

class vt340_state : public driver_device
{
public:
	vt340_state(machine_config const &mconfig, device_type type, char const *tag) :
		driver_device(mconfig, type, tag),
		m_cpu1(*this, "cpu1"),
		m_cpu2(*this, "cpu2"),
		m_duart(*this, "duart"),
		m_acia(*this, "acia"),
		m_screen(*this, "screen"),
		m_cpu2banks_rom(*this, "cpu2banks"),
		m_chargen_rom(*this, "chargen"),
		m_shared_ram(*this, "shared_ram", 0x10000, ENDIANNESS_LITTLE),
		m_bitmap_ram(*this, "bitmap_ram", 0x10000, ENDIANNESS_LITTLE),
		m_bitmap_planes(*this, "bitmap_planes", 4 * BITMAP_PLANE_SIZE, ENDIANNESS_LITTLE)
	{
	}

	void vt340(machine_config &config);

private:
	required_device<mcs51_cpu_device> m_cpu1;
	required_device<i8031_device> m_cpu2;
	required_device<scn2681_device> m_duart;
	required_device<scn2641_device> m_acia;
	required_device<screen_device> m_screen;
	required_region_ptr<u8> m_cpu2banks_rom;
	required_region_ptr<u8> m_chargen_rom;
	memory_share_creator<u8> m_shared_ram;
	memory_share_creator<u8> m_bitmap_ram;
	memory_share_creator<u8> m_bitmap_planes;
	emu_timer *m_cpu2_hsync_timer = nullptr;
	emu_timer *m_cpu2_vsync_timer = nullptr;
	emu_timer *m_keyboard_timer = nullptr;

	u8 m_cpu1_p3 = 0xff;
	u8 m_cpu2_p3 = 0xff;
	u8 m_cpu1_p1 = 0xff;
	u8 m_cpu2_p1 = 0xff;
	u8 m_cpu2_p2 = 0xff;
	u8 m_cpu1_status = 0;
	u8 m_video_test_select = 0;
	bool m_cpu2_hsync_low = true;
	bool m_cpu1_brd_strobe = false;
	bool m_cpu2_t1_pulse = false;
	bool m_keyboard_rxd = true;
	u8 m_keyboard_phase = 0;
	u8 m_cpu1_t1_pulses = 0;
	bool m_adder_ready = false;
	bool m_bitmap_test_pending = false;
	bool m_bitmap_test_active = false;
	bool m_bitmap_post_done = false;
	u32 m_bitmap_test_reads = 0;
	u8 m_adder_test_data = 0;
	bool m_adder_raster_test = false;
	std::array<u8, 0x200> m_eeprom{};
	std::array<u16, 0x40> m_adder_regs{};
	std::array<u16, 0x20> m_viper_regs{};
	std::array<u8, 16> m_dc7051_low{};
	std::array<u8, 16> m_dc7051_high{};
	std::array<u8, 16> m_palette_rg{};
	std::array<u8, 16> m_palette_gb{};
	u16 m_palette_rg_valid = 0;
	u16 m_palette_gb_valid = 0;
	bool m_video_operational = false;
	u16 m_cpu1_trace_events = 0;
	u16 m_cpu2_trace_events = 0;
	u16 m_cpu1_io_trace_events = 0;
	u16 m_cpu2_io_trace_events = 0;

	void cpu1_program_map(address_map &map) ATTR_COLD;
	void cpu2_program_map(address_map &map) ATTR_COLD;
	void cpu1_data_map(address_map &map) ATTR_COLD;
	void cpu2_data_map(address_map &map) ATTR_COLD;

	u8 cpu1_xdata_r(offs_t offset);
	void cpu1_xdata_w(offs_t offset, u8 data);
	u8 cpu1_reserved_c2_r();
	u8 cpu1_p3_r();
	u8 cpu2_upper_r(offs_t offset);
	u8 cpu2_xdata_r(offs_t offset);
	void cpu2_xdata_w(offs_t offset, u8 data);
	void cpu1_p3_w(u8 data);
	void cpu2_p3_w(u8 data);
	u8 cpu1_p1_r();
	void cpu1_p1_w(u8 data);
	u8 cpu2_p1_r();
	void cpu2_p1_w(u8 data);
	u8 cpu2_p2_r();
	void cpu2_p2_w(u8 data);
	u8 cpu2_p3_r();
	void execute_rasterop(u16 command);
	u32 screen_update(screen_device &screen, bitmap_rgb32 &bitmap, rectangle const &cliprect);

	virtual void machine_start() override ATTR_COLD;
	virtual void machine_reset() override ATTR_COLD;
	TIMER_CALLBACK_MEMBER(cpu2_hsync_tick);
	TIMER_CALLBACK_MEMBER(cpu2_vsync_tick);
	TIMER_CALLBACK_MEMBER(keyboard_tick);
	void trace_exit();
};


void vt340_state::cpu1_program_map(address_map &map)
{
	map(0x0000, 0x7fff).rom().region("cpu1low", 0);
	map(0x8000, 0xffff).rom().region("cpu1high", 0);
}

void vt340_state::cpu2_program_map(address_map &map)
{
	map(0x0000, 0x7fff).rom().region("cpu2low", 0);
	map(0x8000, 0xffff).r(FUNC(vt340_state::cpu2_upper_r));
}

u8 vt340_state::cpu2_upper_r(offs_t offset)
{
	// P3.3 is the ROMBANK1 L signal.  The firmware changes it with bit
	// instructions, which do not pass through the external port callback.
	// Select from the live port latch so opcode fetches see the same signal as
	// the cartridge decode.  On the dumped five-ROM cartridge, high selects E4
	// and low selects E5.
	u16 const bank = BIT(m_cpu2->state_int(MCS51_P3), 3) ? 0x0000 : 0x8000;
	return m_cpu2banks_rom[bank | offset];
}

void vt340_state::cpu1_data_map(address_map &map)
{
	map(0x0000, 0xffff).rw(FUNC(vt340_state::cpu1_xdata_r), FUNC(vt340_state::cpu1_xdata_w));
}

void vt340_state::cpu2_data_map(address_map &map)
{
	map(0x0000, 0xffff).rw(FUNC(vt340_state::cpu2_xdata_r), FUNC(vt340_state::cpu2_xdata_w));
}

u8 vt340_state::cpu1_xdata_r(offs_t offset)
{
	if ((m_cpu1_trace_events++ < 256) || ((((offset & 0xfff0) == 0x7ff0) || (offset >= 0xf000)) && (m_cpu1_io_trace_events++ < 512)))
		LOGMASKED(LOG_XDATA, "%s CPU1 XDATA R %04X (PC=%04X)\n", machine().describe_context(), offset, m_cpu1->pc());
	if ((offset & 0xfff0) == 0xf040)
		return m_duart->read(offset & 0x0f);
	if ((offset & 0xfffc) == 0xf058)
		return m_acia->read(offset & 0x03);
	// The board-read strobe reaches T0.  Its low pulse ends within the MOVX
	// bus cycle, but the POST loop at 393D samples the occurrence on its next
	// poll; retain that one observation here.
	if (m_cpu1->pc() == 0x3941)
		m_cpu1_brd_strobe = true;
	return m_shared_ram[offset];
}

u8 vt340_state::cpu1_reserved_c2_r()
{
	return 0xff;
}

void vt340_state::cpu1_xdata_w(offs_t offset, u8 data)
{
	if ((m_cpu1_trace_events++ < 256) || ((((offset & 0xfff0) == 0x7ff0) || (offset >= 0xf000)) && (m_cpu1_io_trace_events++ < 512)))
		LOGMASKED(LOG_XDATA, "%s CPU1 XDATA W %04X=%02X (PC=%04X)\n", machine().describe_context(), offset, data, m_cpu1->pc());
	if ((offset & 0xfff0) == 0xf040)
	{
		m_duart->write(offset & 0x0f, data);
		return;
	}
	if ((offset & 0xfffc) == 0xf058)
	{
		m_acia->write(offset & 0x03, data);
		return;
	}
	m_shared_ram[offset] = data;

}

u8 vt340_state::cpu2_xdata_r(offs_t offset)
{
	if ((m_cpu2_trace_events++ < 256) || ((((offset & 0xfff0) == 0x7ff0) || (offset >= 0xf000)) && (m_cpu2_io_trace_events++ < 512)))
		LOGMASKED(LOG_XDATA, "%s CPU2 XDATA R %04X (PC=%04X)\n", machine().describe_context(), offset, m_cpu2->pc());

	// Once the graphics data path is initialized, its POST sweep addresses
	// bitmap memory through the DC323 rather than processor RAM.  The sweep
	// covers the complete 16-bit address space and ends when the address wraps.
	// After all bitmap sweeps and two success handshakes, 1325 is the first
	// normal decoded read (the E80 EEPROM probe).
	if (m_bitmap_test_active && (m_cpu2->pc() == 0x1329))
	{
		m_bitmap_test_active = false;
		m_bitmap_post_done = true;
	}
	u16 const pc = m_cpu2->pc();
	if (m_bitmap_test_active && ((pc == 0xbadc) || (pc == 0xbaf0) || (pc == 0xbaf7)))
	{
		u8 const data = m_bitmap_ram[offset];
		++m_bitmap_test_reads;
		return data;
	}

	// With LASTH/REN low, the graphics PAL places its retained POST pattern
	// on the F-page diagnostic aperture.  The exact PAL equations remain to
	// be recovered, but this is distinct from the shared E93/E94 RAM below.
	if ((offset >= 0xf000) && (m_cpu2->pc() == 0xbaf0))
	{
		if (offset == 0xffff)
			m_cpu1_status = 1;
		return 0x55;
	}

	// E80 is an undumped Xicor X2804 (512 x 8).  Its aperture becomes visible
	// after destructive RAM POST; an erased device reads as all ones.
	if (m_cpu1_status && (offset >= 0xe600) && (offset <= 0xe7ff))
		return m_eeprom[offset & 0x1ff];

	// E16 decodes two 16-entry output-map apertures.  E51 stores the red
	// nibble (its upper nibble is unused), while E52 stores green in its low
	// nibble and blue in its high nibble.
	if ((offset & 0xfff0) == 0xf040)
		return m_palette_rg[offset & 0x0f];
	if ((offset & 0xfff0) == 0xf050)
		return m_palette_gb[offset & 0x0f];

	// E36 DC7051 timing-generator registers use two byte-wide apertures.
	// Address bit 4 is not decoded: F080/F090 select the low-nibble half and
	// F0A0/F0B0 select the full high-byte half of the same 16 registers.
	if ((offset & 0xffe0) == 0xf080)
		return m_dc7051_low[offset & 0x0f] & 0x0f;
	if ((offset & 0xffe0) == 0xf0a0)
		return m_dc7051_high[offset & 0x0f];

	// The E15 PAL decodes the first 64 DC323 Adder registers in the F000 I/O
	// page.  BA11-BA8 are not decoded, so the block is mirrored.  Register
	// identities and bit assignments match DEC's Dragon chipset specification.
	if ((offset & 0xf0c0) == 0xf000)
	{
		// Register 07 is the data/command port.  The RAM diagnostic writes an
		// equal-byte test word, issues several 00Cx commands through the same
		// port, then reads the retained test data after a read command.
		if (((offset & 0x3f) == 0x07) && (m_cpu2->pc() == 0x1bd1))
		{
			if (m_adder_raster_test)
				return BIT(m_adder_regs[0x22], 3) ? 0x55 : 0xaa;
			return m_adder_test_data;
		}

		u8 data = u8(m_adder_regs[offset & 0x3f]);
		// Register 3 is a control/status register: the write latch and read
		// status are not identical.  A DC323 frame request presents bit 0 low
		// to the INT0 dispatcher; returning the previous FD acknowledge value
		// here makes the level-triggered 8031 enter the handler twice per frame.
		if (((offset & 0x3f) == 0x03) && (pc == 0x0047))
			data &= ~0x01;
		// POST verifies that every decoded register can round-trip its test
		// pattern.  The ready outputs are external status inputs, not stored
		// register bits.  The firmware's confirmed F003 polling routines wait
		// on ready outputs in bits 2, 4, and 5.
		if (((offset & 0x3f) == 0x03) && m_adder_ready &&
			((pc == 0x2900) || (pc == 0xbba0) || (pc == 0xbbaa) || (pc == 0xbbb4)))
			data |= 0x3c;
		return data;
	}

	// CPU1's board STATUS input remains low while CPU2 owns shared RAM for
	// its destructive power-on test.  The final verification pass ends at
	// FFFF; releasing STATUS here lets CPU1 begin without corrupting POST.
	if ((offset == 0xffff) && (m_cpu2->pc() == 0xbaf0))
		m_cpu1_status = 1;

	return m_shared_ram[offset];
}

void vt340_state::cpu2_xdata_w(offs_t offset, u8 data)
{
	if ((m_cpu2_trace_events++ < 256) || ((((offset & 0xfff0) == 0x7ff0) || (offset >= 0xf000)) && (m_cpu2_io_trace_events++ < 512)))
		LOGMASKED(LOG_XDATA, "%s CPU2 XDATA W %04X=%02X (PC=%04X)\n", machine().describe_context(), offset, data, m_cpu2->pc());
	// The DC323 initialization leaves P1 carrying graphics data before the
	// firmware clears and verifies bitmap memory through the generic POST
	// loop.  Earlier RAM tests run with P1 at its reset value.
	if (!m_bitmap_test_active && m_bitmap_test_pending && (m_cpu2->pc() == 0xbadb))
	{
		m_bitmap_test_active = true;
		m_bitmap_test_pending = false;
		m_bitmap_test_reads = 0;
		m_video_operational = false;
		m_palette_rg_valid = 0;
		m_palette_gb_valid = 0;
	}
	// The second POST sweep reaches EFFF with pattern 55 after the timing
	// generator's reset interval, even while bitmap decode owns the aperture.
	if ((offset == 0xefff) && (data == 0x55))
		m_adder_ready = true;
	u16 const pc = m_cpu2->pc();
	if (m_bitmap_test_active && ((pc == 0xbadb) || (pc == 0xbaf6)))
	{
		m_bitmap_ram[offset] = data;
		return;
	}

	// F0E0 selects a timing-generator signal onto P1.0 for the firmware's
	// measured horizontal/vertical timing diagnostics.
	if (m_cpu1_status && (offset == 0xf0e0))
	{
		m_video_test_select = data;
		return;
	}

	// Graphics initialization finishes its F072 control sequence with FF just
	// before exercising the separately addressed bitmap store.
	if (!m_bitmap_post_done && (offset == 0xf072) && (m_cpu2->pc() == 0x1804) && (data == 0xff))
	{
		m_bitmap_test_pending = true;
		return;
	}

	if (m_cpu1_status && (offset >= 0xe600) && (offset <= 0xe7ff))
	{
		m_eeprom[offset & 0x1ff] = data;
		return;
	}

	if ((offset & 0xfff0) == 0xf040)
	{
		m_palette_rg[offset & 0x0f] = data;
		if (m_video_operational && m_cpu2->state_int(MCS51_IE))
			m_palette_rg_valid |= 1U << (offset & 0x0f);
		LOGMASKED(LOG_XDATA, "%s E51 palette[%X]=%02X (PC=%04X)\n", machine().describe_context(), offset & 0x0f, data, m_cpu2->pc());
		return;
	}
	if ((offset & 0xfff0) == 0xf050)
	{
		m_palette_gb[offset & 0x0f] = data;
		if (m_video_operational && m_cpu2->state_int(MCS51_IE))
			m_palette_gb_valid |= 1U << (offset & 0x0f);
		LOGMASKED(LOG_XDATA, "%s E52 palette[%X]=%02X (PC=%04X)\n", machine().describe_context(), offset & 0x0f, data, m_cpu2->pc());
		return;
	}

	if ((offset & 0xffe0) == 0xf080)
	{
		m_dc7051_low[offset & 0x0f] = data & 0x0f;
		return;
	}
	if ((offset & 0xffe0) == 0xf0a0)
	{
		m_dc7051_high[offset & 0x0f] = data;
		return;
	}

	if ((offset & 0xf0c0) == 0xf000)
	{
		u16 const value = (u16(m_cpu2_p1) << 8) | data;
		LOGMASKED(LOG_XDATA, "%s DC323 W %02X=%04X (PC=%04X)\n", machine().describe_context(), offset & 0x3f, value, m_cpu2->pc());
		m_adder_regs[offset & 0x3f] = value;
		if (((offset & 0x3f) == 0x07) && (u8(value >> 8) == u8(value)))
		{
			m_adder_test_data = u8(value);
			m_adder_raster_test = false;
		}
		// The 00CF setup command starts the following address/plane tests with
		// erased bitmap data.  Subsequent 0BC0 reads return that FF value.
		if (((offset & 0x3f) == 0x07) && (value == 0x00cf))
		{
			m_adder_test_data = 0xff;
			m_adder_raster_test = false;
		}
		if (((offset & 0x3f) == 0x07) && (value == 0x00c6))
			m_adder_raster_test = true;
		if (((offset & 0x3f) == 0x02) && (value == 0x0002) && m_cpu1_status)
			m_cpu2_vsync_timer->adjust(attotime::from_ticks(526, 31'500), 0,
				attotime::from_ticks(526, 31'500));
		if (((offset & 0x3f) == 0x03) && !BIT(data, 1) && m_cpu1_status)
			m_cpu2->set_input_line(MCS51_INT0_LINE, CLEAR_LINE);
		if ((offset & 0x3f) == 0x08)
		{
			// I/D commands 0180-019f broadcast the retained I/D data word to
			// the corresponding Viper register.  All four Vipers see this bus.
			if ((value & 0xffe0) == 0x0180)
				m_viper_regs[value & 0x1f] = m_adder_regs[0x07];
			execute_rasterop(value);
		}
		return;
	}

	m_shared_ram[offset] = data;
}

void vt340_state::cpu1_p3_w(u8 data)
{
	u8 const old = m_cpu1_p3;
	if (data != m_cpu1_p3)
		LOGMASKED(LOG_PORTS, "%s CPU1 P3 %02X -> %02X (PC=%04X)\n", machine().describe_context(), m_cpu1_p3, data, m_cpu1->pc());
	m_cpu1_p3 = data;
	// Retain a narrow T1 pulse only while CPU2 is actually in its 170E-1711
	// rendezvous.  Earlier CPU1 diagnostic pulses are not queued by the real
	// pin and must not satisfy a later handshake.
	if (BIT(old, 5) && !BIT(data, 5))
	{
		bool const peer_waiting = (m_cpu2->pc() >= 0x1701) && (m_cpu2->pc() <= 0x1711);
		bool const report_request = (m_cpu1->pc() == 0x3b90) && (m_shared_ram[0x7ff2] == 0x10);
		if ((peer_waiting || report_request) && !m_cpu1_t1_pulses)
			m_cpu1_t1_pulses = 1;
	}
	if (BIT(old, 5) && !BIT(data, 5) && (m_cpu2->pc() == 0x170e))
		m_cpu1->spin_until_trigger(CPU_T1_HANDSHAKE_TRIGGER);
	if (BIT(old, 5) != BIT(data, 5))
		m_cpu1->abort_timeslice();
}

u8 vt340_state::cpu1_p3_r()
{
	// CPU2 P1.1 and CPU1 P3.5/T1 share an open-collector-style status net.
	// Reflect the peer's live output latch in port reads as well as on the
	// core's external T1 input line.
	u8 data = m_cpu1_p3;
	// CPU1's internal UART receives the LK201 keyboard on P3.0/RXD.
	data = m_keyboard_rxd ? (data | 0x01) : (data & ~0x01);
	if (!BIT(m_cpu2_p1, 1))
		data &= ~0x20;
	if ((m_cpu1->pc() == 0x3925) && m_cpu2_t1_pulse)
	{
		// Preserve a CPU2 1701 handshake pulse until CPU1 samples it.  The real
		// pulse overlaps CPU1's delay; this latch avoids losing that sub-ms
		// overlap at an emulation timeslice boundary.
		data &= ~0x20;
		m_cpu2_t1_pulse = false;
	}
	if ((m_cpu1->pc() == 0x3940) && m_cpu1_brd_strobe)
	{
		data &= ~0x10;
		m_cpu1_brd_strobe = false;
	}
	return data;
}

u8 vt340_state::cpu1_p1_r()
{
	// P1.4 is MFGTEST/STATUS and is high in normal operation.
	u8 const data = m_cpu1_status ? (m_cpu1_p1 | 0x10) : (m_cpu1_p1 & ~0x10);
	return data;
}

void vt340_state::cpu1_p1_w(u8 data)
{
	if (data != m_cpu1_p1)
		LOGMASKED(LOG_PORTS, "%s CPU1 P1 %02X -> %02X (PC=%04X)\n", machine().describe_context(), m_cpu1_p1, data, m_cpu1->pc());
	m_cpu1_p1 = data;
}

u8 vt340_state::cpu2_p1_r()
{
	// P1 is the bidirectional P2 DAT8-15/status bus.  DAT9 is wired to CPU1's
	// T1/P3.5 pin, so either processor can pull the quasi-bidirectional net
	// low.  This is the power-on interprocessor handshake at CPU2 1701-1710.
	u8 data = m_cpu2_p1;
	if (!BIT(m_cpu1_p3, 5))
		data &= ~0x02;

	// The same multiplexed status bit is selected from the DC323 during its
	// reset check.  These are the ROM's four explicit low/high phase polls;
	// outside them DAT9 is the interprocessor handshake above.
	u16 const pc = m_cpu2->pc();
	if ((pc == 0x1711) && m_cpu1_t1_pulses)
	{
		data &= ~0x02;
		m_cpu1_t1_pulses--;
	}
	// The core exposes the PC after fetching each three-byte bit branch.
	if ((pc == 0x126f) || (pc == 0x129a) || (pc == 0x1700))
		data &= ~0x02;
	else if (pc == 0x1297)
		data |= 0x02;

	// The final DC323 status transition is the point at which processor 2 is
	// ready for processor 1 to leave its board-status wait and rendezvous on
	// DAT9/T1 at 1701-1710 and 3919-392E.
	if (pc == 0x129a)
		m_cpu1_status = 1;
	if ((pc == 0x1711) && !BIT(data, 1))
		machine().scheduler().trigger(CPU_T1_HANDSHAKE_TRIGGER);
	if (m_video_test_select == 0x70)
	{
		// The DC7051 test mux presents a narrow vertical pulse.  Express it in
		// 8031 machine cycles so the ROM's polling loop measures 0x0cfb-0x0cfd;
		// a whole scanline pulse is several CPU cycles too wide after sampling.
		u64 const phase = machine().time().as_ticks(1'000'000) % 16'698;
		bool const vsync_high = phase < 27;
		data = vsync_high ? (data | 0x01) : (data & ~0x01);
	}
	return data;
}

void vt340_state::cpu2_p1_w(u8 data)
{
	u8 const old = m_cpu2_p1;
	if (data != m_cpu2_p1)
		LOGMASKED(LOG_PORTS, "%s CPU2 P1 %02X -> %02X (PC=%04X)\n", machine().describe_context(), m_cpu2_p1, data, m_cpu2->pc());
	m_cpu2_p1 = data;
	if (BIT(old, 1) && !BIT(data, 1) && (m_cpu2->pc() == 0x1703))
		m_cpu2_t1_pulse = true;
	// P1.1 is the board's P2 DAT9/STATUS H net and is wired directly to
	// processor 1's external T1 pin.  MAME input-line ASSERT means that the
	// active-low external pin is being pulled low.
	m_cpu1->set_input_line(MCS51_T1_LINE, BIT(data, 1) ? CLEAR_LINE : ASSERT_LINE);
	if (BIT(old, 1) && !BIT(data, 1))
		machine().scheduler().trigger(CPU_T1_HANDSHAKE_TRIGGER);
	if (BIT(old, 1) != BIT(data, 1))
		m_cpu2->abort_timeslice();
}

u8 vt340_state::cpu2_p2_r()
{
	return m_cpu2_p2;
}

void vt340_state::cpu2_p2_w(u8 data)
{
	if (data != m_cpu2_p2)
		LOGMASKED(LOG_PORTS, "%s CPU2 P2 %02X -> %02X (PC=%04X)\n", machine().describe_context(), m_cpu2_p2, data, m_cpu2->pc());
	m_cpu2_p2 = data;
}

u8 vt340_state::cpu2_p3_r()
{
	return m_cpu2_p3;
}

void vt340_state::cpu2_p3_w(u8 data)
{
	u8 const old = m_cpu2_p3;
	if (data != m_cpu2_p3)
		LOGMASKED(LOG_PORTS, "%s CPU2 P3 %02X -> %02X (PC=%04X)\n", machine().describe_context(), m_cpu2_p3, data, m_cpu2->pc());

	m_cpu2_p3 = data;
	// Bitmap POST first verifies AA directly, then programs the graphics test
	// path and writes/readbacks zero with T1 high.  Returning T1 low exposes
	// the complemented 55 result that the final pass verifies and clears.
	if (m_bitmap_test_active && BIT(old, 5) && !BIT(data, 5))
		std::fill_n(&m_bitmap_ram[0], 0x10000, 0x55);
}

void vt340_state::execute_rasterop(u16 command)
{
	// Bits 8-9 select a rasterop, bits 10-12 enable destination/source 1/
	// source 2, and I/D command C0/D0/E0/F0 selects Viper logic register
	// 0/1/2/3.  This path covers normal source-1/destination operations from
	// either bitmap memory or E49.  XCON=014D and sheet 28 reduce E49's address
	// to 32 bytes per scanline.
	bool const rasterop = ((command >> 8) & 3) == 2;
	bool const destination_enabled = BIT(command, 10);
	bool const source1_enabled = BIT(command, 11);
	bool const source2_enabled = BIT(command, 12);
	bool const normal_mode = m_adder_regs[0x09] == 0x0080;
	if (!rasterop || !destination_enabled || !source1_enabled || source2_enabled ||
		!normal_mode)
		return;

	u16 const source_x = m_adder_regs[0x22] & 0x3fff;
	u16 const source_y = m_adder_regs[0x23] & 0x1fff;
	bool const source_is_e49 = BIT(source_y, 12);
	u16 const destination_x = m_adder_regs[0x24] & 0x3fff;
	u16 const destination_y = m_adder_regs[0x25] & 0x3fff;
	u16 const width = std::min<u16>(m_adder_regs[0x26] & 0x1fff, BITMAP_WIDTH);
	u16 const height = std::min<u16>(m_adder_regs[0x29] & 0x1fff, BITMAP_HEIGHT);
	u8 const logic = u8(m_viper_regs[4 + ((command >> 4) & 3)]);
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
			// E49 O0 is the leftmost pixel of each eight-pixel source word.
			// Mask registers use the same LSB-left 16-pixel word orientation.
			unsigned const word_bit = (destination_x + x) & 15;
			bool mask1 = BIT(m_viper_regs[8], word_bit);
			bool mask2 = BIT(m_viper_regs[9], word_bit);
			if (BIT(logic, 4))
				mask1 = !mask1;
			if (BIT(logic, 5))
				mask2 = !mask2;
			if (!mask1 || !mask2)
				continue;

			u32 const destination = (destination_y + y) * BITMAP_WIDTH + destination_x + x;
			for (unsigned plane = 0; plane < 4; plane++)
			{
				bool source_bit;
				if (source_is_e49)
					source_bit = BIT(rom_source, rom_x & 7);
				else if ((source_pixel_x < BITMAP_WIDTH) && (source_pixel_y < BITMAP_HEIGHT))
					source_bit = m_bitmap_planes[plane * BITMAP_PLANE_SIZE +
						source_pixel_y * BITMAP_WIDTH + source_pixel_x];
				else
					source_bit = false;
				if (!BIT(logic, 6))
					source_bit = !source_bit;
				bool const destination_bit = m_bitmap_planes[plane * BITMAP_PLANE_SIZE + destination];
				unsigned const logic_input = (destination_bit << 1) | source_bit;
				m_bitmap_planes[plane * BITMAP_PLANE_SIZE + destination] = BIT(logic, logic_input);
			}
		}
	}
}

u32 vt340_state::screen_update(screen_device &screen, bitmap_rgb32 &bitmap, rectangle const &cliprect)
{
	// Four serial bitmap planes form a 16-entry color-map index.  Until the
	// color-map programming path is decoded, expose index 0 as black and any
	// asserted plane as monochrome so genuine firmware-written pixels remain
	// visible without inventing RGB values.
	for (int y = cliprect.top(); y <= cliprect.bottom(); y++)
		for (int x = cliprect.left(); x <= cliprect.right(); x++)
		{
			u32 const address = y * BITMAP_WIDTH + x;
			u8 color = 0;
			for (unsigned plane = 0; plane < 4; plane++)
				color |= m_bitmap_planes[plane * BITMAP_PLANE_SIZE + address] << plane;
			if (BIT(m_palette_rg_valid & m_palette_gb_valid, color))
			{
				u8 const red = (m_palette_rg[color] & 0x0f) * 0x11;
				u8 const green = (m_palette_gb[color] & 0x0f) * 0x11;
				u8 const blue = (m_palette_gb[color] >> 4) * 0x11;
				bitmap.pix(y, x) = rgb_t(red, green, blue);
			}
			else
				bitmap.pix(y, x) = color ? rgb_t::white() : rgb_t::black();
		}
	return 0;
}

void vt340_state::machine_start()
{
	// The base MCS-51 core leaves reserved SFR reads at zero.  CPU1 firmware
	// deliberately reads reserved SFR C2 and requires the all-ones value
	// observed for this unimplemented location on the target processor.
	m_cpu1->space(MCS51_SFR_SPACE).install_read_handler(0xc2, 0xc2,
		read8smo_delegate(*this, FUNC(vt340_state::cpu1_reserved_c2_r)));
	m_eeprom.fill(0xff);
	std::fill_n(&m_bitmap_planes[0], 4 * BITMAP_PLANE_SIZE, 0);
	m_cpu2_hsync_timer = timer_alloc(FUNC(vt340_state::cpu2_hsync_tick), this);
	m_cpu2_vsync_timer = timer_alloc(FUNC(vt340_state::cpu2_vsync_tick), this);
	m_keyboard_timer = timer_alloc(FUNC(vt340_state::keyboard_tick), this);

	machine().add_notifier(MACHINE_NOTIFY_EXIT, machine_notify_delegate(&vt340_state::trace_exit, this));

	save_item(NAME(m_cpu1_p3));
	save_item(NAME(m_cpu2_p3));
	save_item(NAME(m_cpu1_p1));
	save_item(NAME(m_cpu2_p1));
	save_item(NAME(m_cpu2_p2));
	save_item(NAME(m_cpu1_status));
	save_item(NAME(m_video_test_select));
	save_item(NAME(m_cpu2_hsync_low));
	save_item(NAME(m_cpu1_brd_strobe));
	save_item(NAME(m_cpu2_t1_pulse));
	save_item(NAME(m_keyboard_rxd));
	save_item(NAME(m_keyboard_phase));
	save_item(NAME(m_cpu1_t1_pulses));
	save_item(NAME(m_adder_ready));
	save_item(NAME(m_bitmap_test_pending));
	save_item(NAME(m_bitmap_test_active));
	save_item(NAME(m_bitmap_post_done));
	save_item(NAME(m_bitmap_test_reads));
	save_item(NAME(m_adder_test_data));
	save_item(NAME(m_adder_raster_test));
	save_item(NAME(m_eeprom));
	save_item(NAME(m_adder_regs));
	save_item(NAME(m_viper_regs));
	save_item(NAME(m_dc7051_low));
	save_item(NAME(m_dc7051_high));
	save_item(NAME(m_palette_rg));
	save_item(NAME(m_palette_gb));
	save_item(NAME(m_palette_rg_valid));
	save_item(NAME(m_palette_gb_valid));
	save_item(NAME(m_video_operational));
	save_item(NAME(m_cpu1_trace_events));
	save_item(NAME(m_cpu2_trace_events));
	save_item(NAME(m_cpu1_io_trace_events));
	save_item(NAME(m_cpu2_io_trace_events));
}

void vt340_state::trace_exit()
{
	LOGMASKED(LOG_PORTS, "VT340 stop: CPU1 PC=%04X IE=%02X TCON=%02X B=%02X ERR=%02X; "
		"CPU2 PC=%04X IE=%02X TCON=%02X A=%02X B=%02X R2=%02X R3=%02X ROM=%s bitmap=%u/%u video=%02X pulses=%u\n",
		m_cpu1->pc(), m_cpu1->state_int(MCS51_IE), m_cpu1->state_int(MCS51_TCON),
		m_cpu1->state_int(MCS51_B), m_cpu1->space(MCS51_IDATA_SPACE).read_byte(0x42),
		m_cpu2->pc(), m_cpu2->state_int(MCS51_IE), m_cpu2->state_int(MCS51_TCON),
		m_cpu2->state_int(MCS51_ACC), m_cpu2->state_int(MCS51_B),
		m_cpu2->state_int(MCS51_R2), m_cpu2->state_int(MCS51_R3),
		BIT(m_cpu2->state_int(MCS51_P3), 3) ? "E4" : "E5", m_bitmap_test_active,
		m_bitmap_test_reads, m_video_test_select, m_cpu1_t1_pulses);
}

TIMER_CALLBACK_MEMBER(vt340_state::cpu2_hsync_tick)
{
	m_cpu2_hsync_low = !m_cpu2_hsync_low;
	m_cpu2->set_input_line(MCS51_T0_LINE, m_cpu2_hsync_low ? ASSERT_LINE : CLEAR_LINE);
}

TIMER_CALLBACK_MEMBER(vt340_state::cpu2_vsync_tick)
{
	m_cpu2->set_input_line(MCS51_INT0_LINE, ASSERT_LINE);
}

TIMER_CALLBACK_MEMBER(vt340_state::keyboard_tick)
{
	// An LK201 completes its power-up test within 70 ms and reports firmware
	// ID, hardware ID, error, and held-key code at 4800 baud, 8N1.  Model the
	// documented successful 01 00 00 00 response until the full keyboard device
	// can be connected to CPU1's internal UART.
	static constexpr u8 response[4] = { 0x01, 0x00, 0x00, 0x00 };
	if ((m_keyboard_phase == 0) &&
		(!BIT(m_cpu1->space(MCS51_SFR_SPACE).read_byte(0x98), 4) ||
		 (m_cpu1->space(MCS51_SFR_SPACE).read_byte(0x99) != 0xfd)))
	{
		m_keyboard_timer->adjust(attotime::from_msec(1));
		return;
	}
	if (m_keyboard_phase >= 40)
	{
		m_keyboard_rxd = true;
		m_keyboard_timer->adjust(attotime::never);
		return;
	}

	u8 const bit = m_keyboard_phase % 10;
	u8 const data = response[m_keyboard_phase / 10];
	m_keyboard_rxd = (bit == 0) ? false : (bit == 9) ? true : BIT(data, bit - 1);
	m_keyboard_phase++;
	m_keyboard_timer->adjust(attotime::from_hz(4'800));
}

void vt340_state::machine_reset()
{
	m_cpu1_p3 = 0xff;
	m_cpu2_p3 = 0xff;
	m_cpu1_p1 = 0xff;
	m_cpu2_p1 = 0xff;
	m_cpu2_p2 = 0xff;
	m_cpu1_status = 1;
	m_video_test_select = 0;
	m_cpu2_hsync_low = true;
	m_cpu1_brd_strobe = false;
	m_cpu2_t1_pulse = false;
	m_keyboard_rxd = true;
	m_keyboard_phase = 0;
	m_cpu1_t1_pulses = 0;
	m_adder_ready = false;
	m_bitmap_test_pending = false;
	m_bitmap_test_active = false;
	m_bitmap_post_done = false;
	m_bitmap_test_reads = 0;
	m_adder_test_data = 0;
	m_adder_raster_test = false;
	m_adder_regs.fill(0);
	m_viper_regs.fill(0);
	m_dc7051_low.fill(0);
	m_dc7051_high.fill(0);
	m_palette_rg.fill(0);
	m_palette_gb.fill(0);
	m_palette_rg_valid = 0;
	m_palette_gb_valid = 0;
	m_video_operational = false;
	std::fill_n(&m_bitmap_planes[0], 4 * BITMAP_PLANE_SIZE, 0);
	m_cpu1_trace_events = 0;
	m_cpu2_trace_events = 0;
	m_cpu1_io_trace_events = 0;
	m_cpu2_io_trace_events = 0;
	// Processor 1 T0 is tied to the active-low P1 BRD bus-read strobe.  The
	// startup bus test samples it while performing its probe read.
	m_cpu1->set_input_line(MCS51_T0_LINE, CLEAR_LINE);
	m_cpu1->set_input_line(MCS51_T1_LINE, ASSERT_LINE);
	// Unconnected serial inputs idle in the marking state.  Leaving these
	// device pins at their zero-initialized level presents a continuous break
	// to the firmware and can manufacture receive characters during startup.
	m_duart->rx_a_w(1);
	m_duart->rx_b_w(1);
	m_acia->rxd_w(1);
	m_acia->cts_w(1);
	m_acia->dcd_w(1);
	m_cpu2->set_input_line(MCS51_T0_LINE, ASSERT_LINE);
	m_cpu2_hsync_timer->adjust(attotime::from_hz(63'000), 0, attotime::from_hz(63'000));
	m_cpu2->set_input_line(MCS51_INT0_LINE, CLEAR_LINE);
	m_cpu2_vsync_timer->adjust(attotime::never);
	m_keyboard_timer->adjust(attotime::from_msec(70));
	LOGMASKED(LOG_PORTS, "VT340 reset: CPU1 E1/E2, CPU2 E3/E4 selected\n");
}

void vt340_state::vt340(machine_config &config)
{
	// The processors exchange sub-millisecond pulses on P2 DAT9/T1 during
	// POST.  Keep timeslices short enough that neither CPU can consume an
	// entire handshake pulse before the peer gets a chance to sample it.
	config.set_maximum_quantum(attotime::from_usec(10));

	// The schematic calls E57 an 8031.  Normal firmware serial service grows
	// the indirect stack through 8c before unwinding; an 8031 core corrupts at
	// 80, while the otherwise compatible 8032 RAM organization completes the
	// same path and returns with SP=4d.  Retain the 8032 storage behavior while
	// the production CPU marking/firmware discrepancy remains unresolved.
	I8032(config, m_cpu1, 12_MHz_XTAL);
	m_cpu1->set_addrmap(AS_PROGRAM, &vt340_state::cpu1_program_map);
	m_cpu1->set_addrmap(AS_DATA, &vt340_state::cpu1_data_map);
	m_cpu1->port_in_cb<1>().set(FUNC(vt340_state::cpu1_p1_r));
	m_cpu1->port_out_cb<1>().set(FUNC(vt340_state::cpu1_p1_w));
	m_cpu1->port_in_cb<3>().set(FUNC(vt340_state::cpu1_p3_r));
	m_cpu1->port_out_cb<3>().set(FUNC(vt340_state::cpu1_p3_w));

	// E61 is the SCN2681 DUART.  Its active-low interrupt output drives the
	// processor-1 INT0 input.  The 3.6864 MHz clock is the standard crystal
	// frequency used by the part's baud-rate generator.
	SCN2681(config, m_duart, 3.6864_MHz_XTAL);
	m_duart->irq_cb().set_inputline(m_cpu1, MCS51_INT0_LINE);
	m_duart->inport_cb().set_constant(0xff);

	// E81 is the SCN2641 printer communications interface.  Its interrupt
	// output is connected to processor-1 INT1; the keyboard instead uses the
	// processor's internal UART on P3.0/P3.1.
	SCN2641(config, m_acia, 3.6864_MHz_XTAL);
	m_acia->intr_handler().set_inputline(m_cpu1, MCS51_INT1_LINE);

	I8031(config, m_cpu2, 12_MHz_XTAL);
	m_cpu2->set_addrmap(AS_PROGRAM, &vt340_state::cpu2_program_map);
	m_cpu2->set_addrmap(AS_DATA, &vt340_state::cpu2_data_map);
	m_cpu2->port_in_cb<1>().set(FUNC(vt340_state::cpu2_p1_r));
	m_cpu2->port_out_cb<1>().set(FUNC(vt340_state::cpu2_p1_w));
	m_cpu2->port_in_cb<2>().set(FUNC(vt340_state::cpu2_p2_r));
	m_cpu2->port_out_cb<2>().set(FUNC(vt340_state::cpu2_p2_w));
	m_cpu2->port_in_cb<3>().set(FUNC(vt340_state::cpu2_p3_r));
	m_cpu2->port_out_cb<3>().set(FUNC(vt340_state::cpu2_p3_w));
	config.set_perfect_quantum(m_cpu1);

	// Y1 clocks the DC7051.  Its 32.3174 MHz rate divided by the programmed
	// 1026 clocks and 526 lines gives the measured 31.5 kHz / 59.89 Hz raster.
	// The 800x500 visible area includes the terminal's 25th status line.
	SCREEN(config, m_screen);
	m_screen->set_raw(XTAL(32'317'400), 1026, 0, 800, 526, 0, 500);
	m_screen->set_screen_update(FUNC(vt340_state::screen_update));
}


static INPUT_PORTS_START(vt340)
INPUT_PORTS_END


ROM_START(vt340)
	ROM_REGION(0x8000, "cpu1low", 0)
	ROM_LOAD("e1.bin", 0x7fff, 0x0001, CRC(68b3cbde) SHA1(d51677c17e056c69a5864b1673f7887b24f50958))
	ROM_CONTINUE(        0x0000, 0x7fff)
	// The lagged reader lost each EPROM's final byte.  CPU1's rotate/XOR ROM
	// tests at 3BDA reconstruct the unique values that make both checks pass.
	ROM_FILL(            0x7fff, 0x0001, 0x83)

	ROM_REGION(0x8000, "cpu1high", 0)
	ROM_LOAD("e2.bin", 0x7fff, 0x0001, CRC(19f788f0) SHA1(f4018501fee8c429bc1148014f2d9bb97e8cfdcf))
	ROM_CONTINUE(        0x0000, 0x7fff)
	// The boundary-corrupted byte at bbff makes the call at bbfd enter be20,
	// the second byte of the valid LCALL at be1f.  Decoding that byte stream as
	// ACALL bb35 recursively re-enters the timer worker through bbfd and grows
	// the stack until the firmware's overflow trap fires.  The intended be1f
	// target returns a DPTR from the table following the call, as required by
	// the caller at bc00.
	ROM_FILL(            0x3bff, 0x0001, 0x1f)
	// E2's rotate/XOR POST checksum reconstructs the missing final byte as f4
	// with the corrected byte at 3bff (the uncorrected dump required cb).
	ROM_FILL(            0x7fff, 0x0001, 0xf4)

	ROM_REGION(0x8000, "cpu2low", 0)
	ROM_LOAD("e3.bin", 0x7fff, 0x0001, CRC(83919be1) SHA1(937b36e0475a8947a01d03c8e800c54a6461caf7))
	ROM_CONTINUE(        0x0000, 0x7fff)
	// The lagged dump duplicated byte 0 and lost byte 7fff.  At 28ff, F0 would
	// write A and then poll its unchanged bit 4 forever; the surrounding
	// save/read/poll/restore routine proves the opcode must be E0 (MOVX A,@DPTR).
	// At 15ff, FD would fall through from SETB C into CLR C, making the timeout
	// result required by the caller impossible; the symmetric wait routine and
	// branch target at 1600 prove this byte must be 22 (RET).  With both repairs,
	// E3's rotate/XOR checksum reconstructs the missing final byte as 60.
	ROM_FILL(            0x15ff, 0x0001, 0x22)
	ROM_FILL(            0x28ff, 0x0001, 0xe0)
	ROM_FILL(            0x7fff, 0x0001, 0x60)

	ROM_REGION(0x10000, "cpu2banks", 0)
	ROM_LOAD("e4.bin", 0x7fff, 0x0001, CRC(d6eddc42) SHA1(df8097bcd04bd9fed5618d88cd0e0159f81c074b))
	ROM_CONTINUE(        0x0000, 0x7fff)
	// The lagged reader also corrupted E4 byte 12ff.  The decoder at 92f6
	// builds a three-byte state block at 60ab-60ad; after its two pointer-byte
	// stores, 92fe loads the packet length and must store it at 60ad before
	// falling through to the continuation at 9300.  The dumped 22 (RET) both
	// omits that store and returns through an empty stack; F0 is MOVX @DPTR,A.
	ROM_FILL(            0x12ff, 0x0001, 0xf0)
	// Command 21 is emitted as FF 21 01 xx.  Its descriptor's first byte is
	// therefore 02, followed by the intact C569 handler address.  The dump's
	// 69 69 C5 duplicates the adjacent handler byte, makes the decoder consume
	// 105 bytes, and swallows every following packet as payload.
	ROM_FILL(            0x622d, 0x0001, 0x02)
	// E4's rotate/XOR POST checksum reconstructs the missing final byte as aa
	// with both corrected bytes (12ff=f0 alone required c1).
	ROM_FILL(            0x7fff, 0x0001, 0xaa)
	ROM_LOAD("e5.bin", 0xffff, 0x0001, CRC(135c5c7c) SHA1(171d1582d6a62ec9fa8e42421693da6dac3b2a8a))
	ROM_CONTINUE(        0x8000, 0x7fff)
	// E5 F2DD walks the eight bits of the byte at 60af, with R5 numbering
	// entries 1 through 8.  The boundary-corrupted immediate at f2ff is FA,
	// making the loop run 249 times; 09 is the exclusive terminating value.
	ROM_FILL(            0xf2ff, 0x0001, 0x09)
	// E5's rotate/XOR POST checksum reconstructs the missing final byte as 86
	// with the corrected f2ff byte (the uncorrected dump happened to require
	// the duplicated first byte, 75).
	ROM_FILL(            0xffff, 0x0001, 0x86)

	ROM_REGION(0x8000, "chargen", 0)
	ROM_LOAD("vt340e49.bin", 0x0000, 0x8000, CRC(38379339) SHA1(394e8511581abc796c8c612149eff280146b0ac8))

	ROM_REGION(0x0200, "eeprom", ROMREGION_ERASEFF)
	ROM_LOAD("e80.bin", 0x0000, 0x0200, NO_DUMP) // Xicor X2804AP-45 (512 x 8 EEPROM)
ROM_END

} // anonymous namespace


COMP(1987, vt340, 0, 0, vt340, vt340, vt340_state, empty_init, "Digital Equipment Corporation", "VT340 Video Terminal", MACHINE_NO_SOUND | MACHINE_NOT_WORKING)
