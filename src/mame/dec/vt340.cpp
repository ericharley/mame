// license:BSD-3-Clause
// copyright-holders:Harley Card
/***************************************************************************

    Digital Equipment Corporation VT340

    ROM-level hardware reconstruction.  The original firmware drives the
    emulated processors, serial devices and Dragon graphics hardware; the
    driver does not replace terminal protocols or synthesize display text.

    Terminal control module (54-16965-01):
      E57  Intel 8031, processor 1 (see reserved-SFR compatibility note)
      E24  Intel 8031, processor 2
      Y2   12 MHz oscillator feeding CPUACLK/CPUBCLK

    Cartridge program buses:
      CPU 1: E1 at 0000-7fff, E2 at 8000-ffff
      CPU 2: E3 at 0000-7fff, E4/E5 banked at 8000-ffff

    The published cartridge dumps lag the requested address by one byte:
    byte 1 contains EPROM address 0, while raw page-boundary bytes preserve
    otherwise lost xxFF locations.  Loading reconstructs that address stream,
    repairs one independently corrupt descriptor byte, and derives the
    uncaptured checksum bytes.  The lag is consistent with the original
    Arduino reader sampling immediately after changing its address outputs,
    without an EPROM access-time delay.

    The processor-2 INT1/P3.3 latch is ROMBANK1 L.  Controlled execution of
    the five-27256 cartridge establishes its effective mapping: E4 is selected
    when the latch is high and E5 when it is low.

***************************************************************************/

#include "emu.h"

#include "lk201.h"

#include "bus/rs232/rs232.h"
#include "cpu/mcs51/i8051.h"
#include "machine/eeprompar.h"
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
constexpr unsigned SCREEN_WIDTH = 800;
constexpr unsigned SCREEN_HEIGHT = 500;
constexpr unsigned BITMAP_WIDTH = 1024;
constexpr unsigned BITMAP_HEIGHT = 2048;
constexpr unsigned BITMAP_PLANES = 4;
constexpr unsigned BITMAP_PLANE_SIZE = BITMAP_WIDTH * BITMAP_HEIGHT;
constexpr unsigned BITMAP_POST_SIZE = 0x10000;

constexpr u32 bitmap_plane_address(unsigned plane, unsigned x, unsigned y)
{
	return plane * BITMAP_PLANE_SIZE + y * BITMAP_WIDTH + x;
}

enum : unsigned
{
	DC323_REG_INTERRUPT_ENABLE = 0x02,
	DC323_REG_STATUS = 0x03,
	DC323_REG_ID_DATA = 0x07,
	DC323_REG_COMMAND = 0x08,
	DC323_REG_X_CONTROL = 0x09,
	DC323_REG_SCROLL_X_MIN = 0x0e,
	DC323_REG_SCROLL_X_MAX = 0x0f,
	DC323_REG_SCROLL_Y_MIN = 0x10,
	DC323_REG_SCROLL_Y_MAX = 0x11,
	DC323_REG_SCROLL_Y_OFFSET = 0x13,
	DC323_REG_SCROLL_Y = 0x14,
	DC323_REG_NEW_X_INDEX = 0x17,
	DC323_REG_NEW_Y_INDEX = 0x18,
	DC323_REG_OLD_X_INDEX = 0x19,
	DC323_REG_OLD_Y_INDEX = 0x1a,
	DC323_REG_SOURCE_X = 0x22,
	DC323_REG_SOURCE_Y = 0x23,
	DC323_REG_DESTINATION_X = 0x24,
	DC323_REG_DESTINATION_Y = 0x25,
	DC323_REG_WIDTH = 0x26,
	DC323_REG_HEIGHT = 0x29
};

enum : u16
{
	DC323_STATUS_PAUSE_COMPLETE = 0x0001,
	DC323_STATUS_SCROLL_SERVICE = 0x0002,
	DC323_STATUS_RASTEROP_INITIALIZED = 0x0004,
	DC323_STATUS_RASTEROP_COMPLETE = 0x0008,
	DC323_STATUS_ADDRESS_COMPLETE = 0x0010,
	DC323_STATUS_ID_DATA_READY = 0x0020,
	DC323_STATUS_ID_DATA_TRANSMIT_READY = 0x0040,
	DC323_STATUS_RASTEROP_MASK = DC323_STATUS_RASTEROP_INITIALIZED | DC323_STATUS_RASTEROP_COMPLETE |
		DC323_STATUS_ADDRESS_COMPLETE,
	DC323_STATUS_COMMAND_MASK = DC323_STATUS_RASTEROP_MASK | DC323_STATUS_ID_DATA_READY
};

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

enum dc323_post_mode : u8
{
	DC323_POST_INACTIVE,
	DC323_POST_ARMED,
	DC323_POST_PATTERN_AA,
	DC323_POST_EXPECT_PATTERN_55,
	DC323_POST_PATTERN_55,
	DC323_POST_VERIFY_CLEAR,
	DC323_POST_RELEASE_PENDING
};

enum dat9_bus_phase : u8
{
	DAT9_WAIT_BRD_READ,
	DAT9_BRD_READ_LOW,
	DAT9_WAIT_STARTUP_PULSE,
	DAT9_STARTUP_RESPONSE_LOW,
	DAT9_WAIT_DC323_RESET,
	DAT9_WAIT_DC323_STATUS,
	DAT9_DC323_STATUS_HIGH,
	DAT9_DC323_STATUS_LOW,
	DAT9_RESOLVED_PORTS
};

bool should_log_xdata(offs_t offset, u16 &trace_events, u16 &io_trace_events)
{
	bool const io_access = ((offset & 0xfff0) == 0x7ff0) || (offset >= 0xf000);
	return (trace_events++ < 256) || (io_access && (io_trace_events++ < 512));
}

// Match the active communication setup produced by the recovered E80 image.
// These defaults apply to byte-stream endpoint devices; changing the
// terminal's Set-Up values also requires changing the attached endpoint to
// the same framing.
static DEVICE_INPUT_DEFAULTS_START(comm1_defaults)
	DEVICE_INPUT_DEFAULTS("RS232_TXBAUD", 0xff, RS232_BAUD_19200)
	DEVICE_INPUT_DEFAULTS("RS232_RXBAUD", 0xff, RS232_BAUD_19200)
	DEVICE_INPUT_DEFAULTS("RS232_DATABITS", 0xff, RS232_DATABITS_8)
	DEVICE_INPUT_DEFAULTS("RS232_PARITY", 0xff, RS232_PARITY_NONE)
	DEVICE_INPUT_DEFAULTS("RS232_STOPBITS", 0xff, RS232_STOPBITS_1)
	DEVICE_INPUT_DEFAULTS("FLOW_CONTROL", 0x07, 0x00)
DEVICE_INPUT_DEFAULTS_END

static DEVICE_INPUT_DEFAULTS_START(comm2_defaults)
	DEVICE_INPUT_DEFAULTS("RS232_TXBAUD", 0xff, RS232_BAUD_9600)
	DEVICE_INPUT_DEFAULTS("RS232_RXBAUD", 0xff, RS232_BAUD_9600)
	DEVICE_INPUT_DEFAULTS("RS232_DATABITS", 0xff, RS232_DATABITS_8)
	DEVICE_INPUT_DEFAULTS("RS232_PARITY", 0xff, RS232_PARITY_NONE)
	DEVICE_INPUT_DEFAULTS("RS232_STOPBITS", 0xff, RS232_STOPBITS_1)
	DEVICE_INPUT_DEFAULTS("FLOW_CONTROL", 0x07, 0x00)
DEVICE_INPUT_DEFAULTS_END

class vt340_state : public driver_device
{
public:
	vt340_state(machine_config const &mconfig, device_type type, char const *tag) :
		driver_device(mconfig, type, tag),
		m_cpu1(*this, "cpu1"),
		m_cpu2(*this, "cpu2"),
		m_keyboard(*this, "keyboard"),
		m_duart(*this, "duart"),
		m_comm1(*this, "comm1"),
		m_comm2(*this, "comm2"),
		m_printer_uart(*this, "acia"),
		m_eeprom(*this, "eeprom"),
		m_screen(*this, "screen"),
		m_cpu2banks_rom(*this, "cpu2banks"),
		m_chargen_rom(*this, "chargen"),
		m_shared_ram(*this, "shared_ram", 0x10000, ENDIANNESS_LITTLE),
		m_bitmap_ram(*this, "bitmap_ram", BITMAP_POST_SIZE, ENDIANNESS_LITTLE),
		m_bitmap_planes(*this, "bitmap_planes", BITMAP_PLANES * BITMAP_PLANE_SIZE, ENDIANNESS_LITTLE)
	{
	}

	void vt340(machine_config &config);
	void init_vt340();

private:
	required_device<mcs51_cpu_device> m_cpu1;
	required_device<i8031_device> m_cpu2;
	required_device<lk201_device> m_keyboard;
	required_device<scn2681_device> m_duart;
	required_device<rs232_port_device> m_comm1;
	required_device<rs232_port_device> m_comm2;
	required_device<scn2641_device> m_printer_uart;
	required_device<eeprom_parallel_2804_device> m_eeprom;
	required_device<screen_device> m_screen;
	required_region_ptr<u8> m_cpu2banks_rom;
	required_region_ptr<u8> m_chargen_rom;
	memory_share_creator<u8> m_shared_ram;
	memory_share_creator<u8> m_bitmap_ram;
	memory_share_creator<u8> m_bitmap_planes;
	emu_timer *m_cpu2_hsync_timer = nullptr;
	emu_timer *m_cpu2_vsync_timer = nullptr;

	// Processor port latches and board-level handshake state
	u8 m_cpu1_p3 = 0xff;
	u8 m_cpu2_p3 = 0xff;
	u8 m_cpu1_p1 = 0xff;
	u8 m_cpu2_p1 = 0xff;
	u8 m_cpu2_p2 = 0xff;
	u8 m_dat9_bus_phase = DAT9_WAIT_BRD_READ;
	bool m_board_status = false;
	u8 m_video_test_select = 0;
	bool m_cpu2_hsync_low = true;
	bool m_cpu1_brd_strobe = false;
	bool m_cpu2_t1_pulse = false;
	bool m_keyboard_rxd = true;
	u8 m_cpu1_t1_pulses = 0;

	// Graphics POST compatibility state
	bool m_adder_ready = false;
	u8 m_dc323_post_mode = DC323_POST_INACTIVE;
	bool m_bitmap_post_done = false;
	u32 m_bitmap_test_reads = 0;
	u8 m_adder_test_data = 0;
	bool m_adder_raster_test = false;

	// Operational DC323 Adder, Viper, timing and palette state
	std::array<u16, 0x40> m_adder_regs{};
	u16 m_adder_status = 0;
	bool m_scroll_pending = false;
	std::array<u16, 0x20> m_viper_regs{};
	bool m_pbt_read_active = false;
	u32 m_pbt_read_index = 0;
	u32 m_pbt_read_count = 0;
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
	bool eeprom_selected(offs_t offset);
	u8 cpu1_reserved_c2_r();
	u8 cpu1_p3_r();
	u8 cpu2_upper_r(offs_t offset);
	u8 cpu2_xdata_r(offs_t offset);
	void cpu2_xdata_w(offs_t offset, u8 data);
	void cpu1_p3_w(u8 data);
	void keyboard_rxd_w(int state);
	u8 duart_input_r();
	void cpu2_p3_w(u8 data);
	u8 cpu1_p1_r();
	void cpu1_p1_w(u8 data);
	u8 cpu2_p1_r();
	void cpu2_p1_w(u8 data);
	bool dat9_device_low() const;
	void update_dat9_input();
	u8 cpu2_p2_r();
	void cpu2_p2_w(u8 data);
	u8 cpu2_p3_r();
	u8 dc323_id_data_r();
	void dc323_command_w(u16 command);
	void update_dc323_interrupt();
	bool dc323_post_bitmap_selected() const;
	void release_dc323_post();
	void execute_rasterop(u16 command);
	void execute_scroll();
	u32 screen_update(screen_device &, bitmap_rgb32 &bitmap, rectangle const &cliprect);

	virtual void machine_start() override ATTR_COLD;
	virtual void machine_reset() override ATTR_COLD;
	TIMER_CALLBACK_MEMBER(cpu2_hsync_tick);
	TIMER_CALLBACK_MEMBER(cpu2_vsync_tick);
	void trace_exit();
};


void vt340_state::init_vt340()
{
	// The published Arduino dump changes the high address byte before the low
	// byte and samples without a settling delay.  Apart from byte zero, the
	// file is one byte behind the requested address.  At each page transition,
	// raw xx00 consequently preserves logical xxFF while the usual shifted
	// reconstruction incorrectly substitutes the following page's last byte.
	auto reconstruct = [this](char const *destination, u32 destination_offset, char const *source)
	{
		u8 *const dest = memregion(destination)->base() + destination_offset;
		u8 const *const raw = memregion(source)->base();

		std::copy_n(raw + 1, 0x7fff, dest);
		for (u32 page = 1; page < 0x7f; page++)
			dest[(page << 8) | 0xff] = raw[page << 8];
	};

	auto finish_checksum = [this](char const *region, u32 offset, u8 seed)
	{
		u8 *const data = memregion(region)->base() + offset;
		u8 checksum = seed;
		for (u32 address = 0; address < 0x7fff; address++)
			checksum = u8((data[address] << 1) | (data[address] >> 7)) ^ checksum;
		data[0x7fff] = u8((checksum >> 1) | (checksum << 7));
	};

	reconstruct("cpu1low", 0x0000, "e1raw");
	reconstruct("cpu1high", 0x0000, "e2raw");
	reconstruct("cpu2low", 0x0000, "e3raw");
	reconstruct("cpu2banks", 0x0000, "e4raw");
	reconstruct("cpu2banks", 0x8000, "e5raw");

	// This descriptor byte is an independent non-boundary dump defect.  CPU1
	// emits command 21 as FF 21 01 xx, so the E4 descriptor is length 02 and
	// handler C569; dumped 69 would consume the following packets as payload.
	memregion("cpu2banks")->base()[0x622d] = 0x02;

	// The last byte was not captured.  The firmware's rotate/XOR POST yields
	// its unique value after all recoverable page-boundary bytes are restored.
	finish_checksum("cpu1low", 0x0000, 0x07);
	finish_checksum("cpu1high", 0x0000, 0x08);
	finish_checksum("cpu2low", 0x0000, 0x07);
	finish_checksum("cpu2banks", 0x0000, 0x08);
	finish_checksum("cpu2banks", 0x8000, 0x09);
}


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
	if (should_log_xdata(offset, m_cpu1_trace_events, m_cpu1_io_trace_events))
		LOGMASKED(LOG_XDATA, "%s CPU1 XDATA R %04X (PC=%04X)\n", machine().describe_context(), offset, m_cpu1->pc());
	// E80's A0-A8 inputs are driven directly by CPU1's multiplexed external
	// address bus.  E10 shifts P1.3 (NVRDS L) into the active-low NVRCS latch
	// under P1.7 (NVRCLK H); every firmware access performs that sequence at
	// 4156 immediately before MOVX.  The live port latch is required here
	// because MCS-51 bit instructions do not pass through the port callback.
	// While selected, E80 owns the bus even at addresses which overlap the
	// ordinary serial-device decode.
	if (eeprom_selected(offset))
		return m_eeprom->read(m_cpu1->space(AS_DATA), offset & 0x01ff);
	// E78 decodes the CPU1 I/O page into two 64-byte serial apertures.  E81
	// (SCN2641) occupies F000-F03F and E61 (SCN2681) occupies F040-F07F;
	// their register-select inputs use the low two and low four address bits.
	if ((offset & 0xffc0) == 0xf000)
		return m_printer_uart->read(offset & 0x03);
	if ((offset & 0xffc0) == 0xf040)
		return m_duart->read(offset & 0x0f);
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
	if (should_log_xdata(offset, m_cpu1_trace_events, m_cpu1_io_trace_events))
		LOGMASKED(LOG_XDATA, "%s CPU1 XDATA W %04X=%02X (PC=%04X)\n", machine().describe_context(), offset, data, m_cpu1->pc());
	if (eeprom_selected(offset))
	{
		m_eeprom->write(offset & 0x01ff, data);
		return;
	}
	if ((offset & 0xffc0) == 0xf000)
	{
		m_printer_uart->write(offset & 0x03, data);
		return;
	}
	if ((offset & 0xffc0) == 0xf040)
	{
		m_duart->write(offset & 0x0f, data);
		return;
	}
	m_shared_ram[offset] = data;
}

bool vt340_state::eeprom_selected(offs_t offset)
{
	// E10 latches active-low NVRCS from P1.3 (NVRDS L) under P1.7
	// (NVRCLK H).  MCS-51 bit instructions bypass the port callback, so use
	// the live port latch for both reads and writes.
	return !BIT(m_cpu1->state_int(MCS51_P1), 3) && ((offset & 0xfe00) == 0xf000);
}

u8 vt340_state::cpu2_xdata_r(offs_t offset)
{
	if (should_log_xdata(offset, m_cpu2_trace_events, m_cpu2_io_trace_events))
		LOGMASKED(LOG_XDATA, "%s CPU2 XDATA R %04X (PC=%04X)\n", machine().describe_context(), offset, m_cpu2->pc());

	// The first external access after the three bitmap sweeps returns the bus
	// to normal decoding.  The intervening DAT9 handshakes do not use XDATA.
	if (m_dc323_post_mode == DC323_POST_RELEASE_PENDING)
		release_dc323_post();

	// DC323 POST selects bitmap memory for the two 0000-EFFF pattern sweeps
	// and the final 0000-FFFF verify/clear pass.  Firmware performs
	// write/read AA, write/read 55, then verify-55/write-zero/read-zero.  Track
	// phase completion from the value at the last decoded address rather than
	// from the program counter of the generic memory-test routine.
	u16 const pc = m_cpu2->pc();
	if (dc323_post_bitmap_selected())
	{
		u8 const data = m_bitmap_ram[offset];
		++m_bitmap_test_reads;
		if (offset == 0xefff)
		{
			if ((m_dc323_post_mode == DC323_POST_PATTERN_AA) && (data == 0xaa))
				m_dc323_post_mode = DC323_POST_EXPECT_PATTERN_55;
			else if ((m_dc323_post_mode == DC323_POST_PATTERN_55) && (data == 0x55))
				m_dc323_post_mode = DC323_POST_VERIFY_CLEAR;
		}
		else if ((offset == 0xffff) && (m_dc323_post_mode == DC323_POST_VERIFY_CLEAR) && (data == 0x00))
			m_dc323_post_mode = DC323_POST_RELEASE_PENDING;
		return data;
	}

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
		// Register 07 is the I/D data port.  During graphics POST the firmware
		// writes equal-byte test words here, issues 00Cx commands through the
		// command register, and then reads the retained diagnostic value.
		unsigned const reg = offset & 0x3f;
		if ((reg == DC323_REG_ID_DATA) && (m_cpu2->pc() == 0x1bd1))
		{
			if (m_adder_raster_test)
				return BIT(m_adder_regs[DC323_REG_SOURCE_X], 3) ? 0x55 : 0xaa;
			return m_adder_test_data;
		}

		// Register 7 is the six-word I/D FIFO, not a readable copy of the
		// last word written to it.  Source-1 bitmap-to-processor transfers
		// stream either E49 character ROM data or off-screen bitmap storage
		// through this port.
		if ((reg == DC323_REG_ID_DATA) && m_pbt_read_active)
			return dc323_id_data_r();

		u8 data = u8(m_adder_regs[reg]);
		// Register 3 is a read-status/write-clear register once graphics POST
		// has released the DC323.  Status bits are sticky until firmware writes
		// a zero in the corresponding position.
		if ((reg == DC323_REG_STATUS) && m_bitmap_post_done)
			data = u8(m_adder_status);
		// POST verifies that every decoded register can round-trip its test
		// pattern.  The ready outputs are external status inputs, not stored
		// register bits.  The firmware's confirmed F003 polling routines wait
		// on ready outputs in bits 2, 4, and 5.
		if ((reg == DC323_REG_STATUS) && m_adder_ready &&
			((pc == 0x2900) || (pc == 0xbba0) || (pc == 0xbbaa) || (pc == 0xbbb4)))
			data |= DC323_STATUS_COMMAND_MASK;
		return data;
	}

	// P2 BRD L is also presented on the multiplexed DAT9/TSTATUS net.  Retain
	// the low level from the bus cycle until CPU2 samples its port immediately
	// afterwards; subsequent ownership is advanced by the resolved bus model.
	if (m_dat9_bus_phase == DAT9_WAIT_BRD_READ)
	{
		m_dat9_bus_phase = DAT9_BRD_READ_LOW;
		update_dat9_input();
	}
	return m_shared_ram[offset];
}

bool vt340_state::dc323_post_bitmap_selected() const
{
	return (m_dc323_post_mode >= DC323_POST_PATTERN_AA) &&
		(m_dc323_post_mode <= DC323_POST_VERIFY_CLEAR);
}

void vt340_state::release_dc323_post()
{
	m_dc323_post_mode = DC323_POST_INACTIVE;
	m_bitmap_post_done = true;
}

u8 vt340_state::dc323_id_data_r()
{
	u16 const width = m_adder_regs[DC323_REG_WIDTH] & 0x1fff;
	u32 const bytes_per_row = (width + 7) / 8;
	u32 const row = m_pbt_read_index / bytes_per_row;
	u32 const column = m_pbt_read_index % bytes_per_row;
	u16 const source_origin_x = m_adder_regs[DC323_REG_SOURCE_X] & 0x3fff;
	u16 const source_origin_y = m_adder_regs[DC323_REG_SOURCE_Y] & 0x1fff;
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
		// The operational paths use identical data in all four Vipers.  In
		// eight-bit mode, bit zero is the leftmost source pixel.
		for (unsigned bit = 0; bit < 8 && (source_x + bit) < BITMAP_WIDTH; bit++)
			data |= (m_bitmap_planes[bitmap_plane_address(0, source_x + bit, source_y)] & 1) << bit;
	}

	if (++m_pbt_read_index >= m_pbt_read_count)
	{
		m_pbt_read_active = false;
		m_adder_status &= ~DC323_STATUS_ID_DATA_READY;
		m_adder_status |= DC323_STATUS_ADDRESS_COMPLETE;
		update_dc323_interrupt();
	}

	return data;
}

void vt340_state::cpu2_xdata_w(offs_t offset, u8 data)
{
	if (should_log_xdata(offset, m_cpu2_trace_events, m_cpu2_io_trace_events))
		LOGMASKED(LOG_XDATA, "%s CPU2 XDATA W %04X=%02X (PC=%04X)\n", machine().describe_context(), offset, data, m_cpu2->pc());
	if (m_dc323_post_mode == DC323_POST_RELEASE_PENDING)
		release_dc323_post();

	// F072 arms the DC323 bitmap diagnostic.  The following write of AA to
	// address zero begins the first explicit test phase.
	if ((m_dc323_post_mode == DC323_POST_ARMED) && (offset == 0x0000) && (data == 0xaa))
	{
		m_dc323_post_mode = DC323_POST_PATTERN_AA;
		m_bitmap_test_reads = 0;
		m_video_operational = false;
		m_palette_rg_valid = 0;
		m_palette_gb_valid = 0;
	}
	if ((m_dc323_post_mode == DC323_POST_EXPECT_PATTERN_55) &&
		(offset == 0x0000) && (data == 0x55))
		m_dc323_post_mode = DC323_POST_PATTERN_55;
	if (dc323_post_bitmap_selected())
	{
		m_bitmap_ram[offset] = data;
		// The second sweep reaches the last decoded bitmap address with 55 after
		// the timing generator's reset interval.
		if ((m_dc323_post_mode == DC323_POST_PATTERN_55) &&
			(offset == 0xefff) && (data == 0x55))
			m_adder_ready = true;
		return;
	}

	// F0E0 selects a timing-generator signal onto P1.0 for the firmware's
	// measured horizontal/vertical timing diagnostics.
	if (m_board_status && (offset == 0xf0e0))
	{
		m_video_test_select = data;
		return;
	}

	// Graphics initialization finishes its F072 control sequence with FF just
	// before exercising the separately addressed bitmap store.
	if (!m_bitmap_post_done && (offset == 0xf072) && (data == 0xff))
	{
		m_dc323_post_mode = DC323_POST_ARMED;
		if (m_dat9_bus_phase == DAT9_WAIT_DC323_RESET)
			m_dat9_bus_phase = DAT9_WAIT_DC323_STATUS;
		return;
	}
	// The second board-control initialization terminates DC323 reset.  DAT9 is
	// released high for one status sample, then the DC323 supplies the low
	// completion phase before leaving the shared net to the processor ports.
	if ((m_dat9_bus_phase == DAT9_WAIT_DC323_STATUS) && (offset == 0xf060) && (data == 0x00))
	{
		m_dat9_bus_phase = DAT9_DC323_STATUS_HIGH;
		update_dat9_input();
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
		unsigned const reg = offset & 0x3f;
		u16 const value = (u16(m_cpu2_p1) << 8) | data;
		LOGMASKED(LOG_XDATA, "%s DC323 W %02X=%04X (PC=%04X)\n", machine().describe_context(), reg, value, m_cpu2->pc());
		m_adder_regs[reg] = value;
		if ((reg == DC323_REG_ID_DATA) && (u8(value >> 8) == u8(value)))
		{
			m_adder_test_data = u8(value);
			m_adder_raster_test = false;
		}
		// The 00CF setup command starts the following address/plane tests with
		// erased bitmap data.  Subsequent 0BC0 reads return that FF value.
		if ((reg == DC323_REG_ID_DATA) && (value == 0x00cf))
		{
			m_adder_test_data = 0xff;
			m_adder_raster_test = false;
		}
		if ((reg == DC323_REG_ID_DATA) && (value == 0x00c6))
			m_adder_raster_test = true;
		if ((reg == DC323_REG_INTERRUPT_ENABLE) && m_bitmap_post_done)
		{
			attotime const frame_period = attotime::from_ticks(526, 31'500);
			m_cpu2_vsync_timer->adjust(value ? frame_period : attotime::never, 0,
				value ? frame_period : attotime::never);
			if (!(m_adder_status & value))
				m_cpu2->set_input_line(MCS51_INT0_LINE, CLEAR_LINE);
		}
		if ((reg == DC323_REG_STATUS) && m_bitmap_post_done)
		{
			m_adder_status &= value;
			update_dc323_interrupt();
		}
		if ((reg == DC323_REG_SCROLL_Y) && m_bitmap_post_done)
			m_scroll_pending = true;
		if (reg == DC323_REG_COMMAND)
			dc323_command_w(value);
		return;
	}

	m_shared_ram[offset] = data;
}

void vt340_state::dc323_command_w(u16 command)
{
	unsigned const operation = (command >> 8) & 3;

	// Loading a rasterop or processor/bitmap transfer clears the
	// initialization, rasterop-complete and address-output-complete
	// indications.  Rasterops execute synchronously in this driver, so all
	// three conditions become true again before the register write returns.
	if (m_bitmap_post_done && ((operation == 2) || (operation == 3)))
	{
		m_adder_status &= ~DC323_STATUS_COMMAND_MASK;
		m_adder_status |= DC323_STATUS_ID_DATA_TRANSMIT_READY;
		m_pbt_read_active = false;
	}

	// I/D commands 0180-019f load a Viper register from the retained I/D data
	// word.  The currently modeled paths use a common broadcast value; separate
	// per-Viper chip-select/register state is not represented yet.
	if ((command & 0xffe0) == 0x0180)
		m_viper_regs[command & 0x1f] = m_adder_regs[DC323_REG_ID_DATA];

	// Function 3 with source 1 enabled and destination disabled is a
	// bitmap-to-processor transfer.  E49 is selected by source Y bit 12;
	// otherwise the source is bitmap memory.  In eight-bit mode one FIFO read
	// returns eight source pixels.
	if ((operation == 3) && BIT(command, 11) && !BIT(command, 10))
	{
		u32 const width = m_adder_regs[DC323_REG_WIDTH] & 0x1fff;
		u32 const height = m_adder_regs[DC323_REG_HEIGHT] & 0x1fff;
		m_pbt_read_index = 0;
		m_pbt_read_count = ((width + 7) / 8) * height;
		m_pbt_read_active = m_pbt_read_count != 0;
		if (m_bitmap_post_done)
		{
			m_adder_status |= DC323_STATUS_RASTEROP_INITIALIZED | DC323_STATUS_RASTEROP_COMPLETE;
			m_adder_status |= m_pbt_read_active
				? DC323_STATUS_ID_DATA_READY
				: DC323_STATUS_ADDRESS_COMPLETE;
		}
	}

	execute_rasterop(command);
	if (m_bitmap_post_done && (operation == 2))
	{
		m_adder_status |= DC323_STATUS_RASTEROP_MASK;
		update_dc323_interrupt();
	}
}

void vt340_state::update_dc323_interrupt()
{
	int const state = (m_adder_status & m_adder_regs[DC323_REG_INTERRUPT_ENABLE]) ? ASSERT_LINE : CLEAR_LINE;
	m_cpu2->set_input_line(MCS51_INT0_LINE, state);
}

void vt340_state::cpu1_p3_w(u8 data)
{
	u8 const old = m_cpu1_p3;
	if (data != m_cpu1_p3)
		LOGMASKED(LOG_PORTS, "%s CPU1 P3 %02X -> %02X (PC=%04X)\n", machine().describe_context(), m_cpu1_p3, data, m_cpu1->pc());
	m_cpu1_p3 = data;
	update_dat9_input();
	// CPU1 P3.1/TXD is the terminal-to-keyboard half of the LK201 serial
	// connection.  Feed the live port level to the keyboard so the ROM's
	// native 4800-baud command stream is observed by the real device firmware.
	m_keyboard->rx_w(BIT(data, 1));
	// Retain a narrow T1 pulse only while CPU2 is actually in its 170E-1711
	// rendezvous.  Earlier CPU1 diagnostic pulses are not queued by the real
	// pin and must not satisfy a later handshake.
	if (BIT(old, 5) && !BIT(data, 5))
	{
		bool const peer_waiting = (m_cpu2->pc() >= 0x1701) && (m_cpu2->pc() <= 0x1711);
		if (peer_waiting && !m_cpu1_t1_pulses)
			m_cpu1_t1_pulses = 1;
	}
	if (BIT(old, 5) != BIT(data, 5))
		m_cpu1->abort_timeslice();
}

void vt340_state::keyboard_rxd_w(int state)
{
	m_keyboard_rxd = bool(state);
}

u8 vt340_state::duart_input_r()
{
	// E61 input pins, schematic sheet 5: Comm 1 supplies CTS, DSR, speed
	// indication and carrier detect.  The 25-pin RS-232 and six-pin DEC-423
	// connectors are alternate electrical interfaces for channel A, so the
	// abstract Comm 1 endpoint supplies both DSR inputs.  Comm 2 supplies DSR
	// only.  IP6 is TVSYNC and retains the previously established idle level.
	return BIT(m_comm1->cts_r(), 0)
		| (BIT(m_comm1->dsr_r(), 0) << 1)
		| (BIT(m_comm1->si_r(), 0) << 2)
		| (BIT(m_comm1->dcd_r(), 0) << 3)
		| (BIT(m_comm1->dsr_r(), 0) << 4)
		| (BIT(m_comm2->dsr_r(), 0) << 5)
		| 0x40;
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
	if (dat9_device_low())
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
	// P1.4 is the NVREN output and P1.5 is MFGTEST/STATUS.  Both are driven by
	// CPU1 firmware during startup; do not replace either live output latch
	// with the separate graphics-diagnostic state tracked by the driver.
	return m_cpu1_p1;
}

void vt340_state::cpu1_p1_w(u8 data)
{
	if (data != m_cpu1_p1)
		LOGMASKED(LOG_PORTS, "%s CPU1 P1 %02X -> %02X (PC=%04X)\n", machine().describe_context(), m_cpu1_p1, data, m_cpu1->pc());
	m_cpu1_p1 = data;

	// CPU1 P1.0 is the active-high P1 RESET H net connected directly to
	// CPU2's RST pin (terminal-control-module schematic sheets 1 and 2).
	m_cpu2->set_input_line(INPUT_LINE_RESET, BIT(data, 0) ? ASSERT_LINE : CLEAR_LINE);
}

u8 vt340_state::cpu2_p1_r()
{
	// P1 is the bidirectional P2 DAT8-15/status bus.  DAT9 is wired to CPU1's
	// T1/P3.5 pin, so either processor can pull the quasi-bidirectional net
	// low.  This is the power-on interprocessor handshake at CPU2 1701-1710.
	u8 data = m_cpu2_p1;
	if (!BIT(m_cpu1_p3, 5))
		data &= ~0x02;
	if (dat9_device_low())
		data &= ~0x02;

	// A port sample completes retained bus-turnaround phases.  The returned
	// value is from the phase that owned DAT9 for this sample; ownership changes
	// take effect on the resolved net after the read.
	u16 const pc = m_cpu2->pc();
	if ((pc == 0x1711) && m_cpu1_t1_pulses)
	{
		data &= ~0x02;
		m_cpu1_t1_pulses--;
	}
	switch (m_dat9_bus_phase)
	{
	case DAT9_BRD_READ_LOW:
		m_dat9_bus_phase = DAT9_WAIT_STARTUP_PULSE;
		break;
	case DAT9_STARTUP_RESPONSE_LOW:
		m_dat9_bus_phase = DAT9_WAIT_DC323_RESET;
		break;
	case DAT9_DC323_STATUS_HIGH:
		m_dat9_bus_phase = DAT9_DC323_STATUS_LOW;
		break;
	case DAT9_DC323_STATUS_LOW:
		m_dat9_bus_phase = DAT9_RESOLVED_PORTS;
		m_board_status = true;
		break;
	default:
		break;
	}
	update_dat9_input();
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
	if ((m_dat9_bus_phase == DAT9_WAIT_STARTUP_PULSE) && !BIT(old, 1) && BIT(data, 1))
		m_dat9_bus_phase = DAT9_STARTUP_RESPONSE_LOW;
	if (BIT(old, 1) && !BIT(data, 1) && (m_cpu2->pc() == 0x1703))
		m_cpu2_t1_pulse = true;
	// P1.1 is the board's P2 DAT9/STATUS H net and is wired directly to
	// processor 1's external T1 pin.  MAME input-line ASSERT means that the
	// active-low external pin is being pulled low.
	update_dat9_input();
	if (BIT(old, 1) != BIT(data, 1))
		m_cpu2->abort_timeslice();
}

bool vt340_state::dat9_device_low() const
{
	return (m_dat9_bus_phase == DAT9_BRD_READ_LOW) ||
		(m_dat9_bus_phase == DAT9_STARTUP_RESPONSE_LOW) ||
		(m_dat9_bus_phase == DAT9_DC323_STATUS_LOW);
}

void vt340_state::update_dat9_input()
{
	bool const high = BIT(m_cpu1_p3, 5) && BIT(m_cpu2_p1, 1) && !dat9_device_low();
	m_cpu1->set_input_line(MCS51_T1_LINE, high ? CLEAR_LINE : ASSERT_LINE);
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
	if (dc323_post_bitmap_selected() && BIT(old, 5) && !BIT(data, 5))
		std::fill_n(&m_bitmap_ram[0], BITMAP_POST_SIZE, 0x55);
}

void vt340_state::execute_rasterop(u16 command)
{
	// Bits 8-9 select a rasterop, bits 10-12 enable destination/source 1/
	// source 2, and I/D command C0/D0/E0/F0 selects Viper logic register
	// 0/1/2/3.  This path covers normal destination operations with either no
	// memory source (the Viper source register supplies a constant), or source
	// 1 from bitmap memory or E49.  Source 2 and non-zero index translation are
	// not yet implemented; the firmware's indexed text-scroll redraws use zero
	// pending/new/old indexes and therefore share the unindexed addresses.
	// XCON=014D and schematic sheet 28 reduce E49 to 32 bytes per scanline.
	bool const rasterop = ((command >> 8) & 3) == 2;
	bool const destination_enabled = BIT(command, 10);
	bool const source1_enabled = BIT(command, 11);
	bool const source2_enabled = BIT(command, 12);
	u16 const x_control = m_adder_regs[DC323_REG_X_CONTROL];
	bool const normal_mode = ((x_control & 0x001f) == 0) && BIT(x_control, 7);
	bool const indexed = BIT(x_control, 5) || BIT(x_control, 6);
	bool const zero_indexes = !(m_adder_regs[DC323_REG_NEW_X_INDEX] |
		m_adder_regs[DC323_REG_NEW_Y_INDEX] | m_adder_regs[DC323_REG_OLD_X_INDEX] |
		m_adder_regs[DC323_REG_OLD_Y_INDEX]);
	if (!rasterop || !destination_enabled || source2_enabled ||
		!normal_mode || (indexed && !zero_indexes))
		return;

	u16 const source_x = m_adder_regs[DC323_REG_SOURCE_X] & 0x3fff;
	u16 const source_y = m_adder_regs[DC323_REG_SOURCE_Y] & 0x1fff;
	bool const source_is_e49 = source1_enabled && BIT(source_y, 12);
	u16 const destination_x = m_adder_regs[DC323_REG_DESTINATION_X] & 0x3fff;
	u16 const destination_y = m_adder_regs[DC323_REG_DESTINATION_Y] & 0x3fff;
	u16 const width = std::min<u16>(m_adder_regs[DC323_REG_WIDTH] & 0x1fff, BITMAP_WIDTH);
	u16 const height = std::min<u16>(m_adder_regs[DC323_REG_HEIGHT] & 0x1fff, BITMAP_HEIGHT);
	u8 const logic = u8(m_viper_regs[VIPER_REG_LOGIC_BASE + ((command >> 4) & 3)]);
	if (source_is_e49 && (destination_x < SCREEN_WIDTH) && (destination_y < SCREEN_HEIGHT) &&
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
			bool mask1 = BIT(m_viper_regs[VIPER_REG_MASK_1], word_bit);
			bool mask2 = BIT(m_viper_regs[VIPER_REG_MASK_2], word_bit);
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
					source_bit = BIT(m_viper_regs[VIPER_REG_SOURCE], word_bit);
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

void vt340_state::execute_scroll()
{
	if (!m_scroll_pending)
		return;
	m_scroll_pending = false;

	// Loading the Y scroll constant schedules one operation for the following
	// frame.  Bits 0-11 hold the unsigned distance, bit 12 selects downward
	// motion, and bit 13 selects erase mode.  Y bounds are exclusive and the
	// Y offset translates device coordinates to bitmap-memory coordinates.
	// For normal scrolling, the Adder X bounds identify edge words and the
	// Viper boundary masks select pixels within them; exposed pixels use the
	// Viper fill word.  Erase mode clears the literal Adder region.
	u16 const scroll = m_adder_regs[DC323_REG_SCROLL_Y];
	u16 const x_min = std::min<u16>(m_adder_regs[DC323_REG_SCROLL_X_MIN] & 0x3ffc, BITMAP_WIDTH);
	u16 const x_max = std::min<u16>(m_adder_regs[DC323_REG_SCROLL_X_MAX] & 0x3ffc, BITMAP_WIDTH);
	u16 const y_min = std::min<u16>(m_adder_regs[DC323_REG_SCROLL_Y_MIN] & 0x1fff, BITMAP_HEIGHT);
	u16 const y_max = std::min<u16>(m_adder_regs[DC323_REG_SCROLL_Y_MAX] & 0x1fff, BITMAP_HEIGHT);
	u16 const y_offset = m_adder_regs[DC323_REG_SCROLL_Y_OFFSET] & 0x1fff;
	u16 const fill = m_viper_regs[VIPER_REG_FILL];
	if ((x_min >= x_max) || (y_min >= y_max))
		return;

	bool const erase = BIT(scroll, 13);
	unsigned const bus_width_select = (m_viper_regs[VIPER_REG_BUS_WIDTH] >> 2) & 3;
	u16 const scroll_word_width = (bus_width_select == 0) ? 4 : (bus_width_select == 3) ? 16 : 8;
	u16 const left_word = x_min & ~(scroll_word_width - 1);
	u16 const right_word = x_max & ~(scroll_word_width - 1);
	u16 const operation_x_min = erase ? x_min : left_word;
	u16 const operation_x_max = erase
		? x_max
		: std::min<u16>(right_word + scroll_word_width, BITMAP_WIDTH);
	u16 const left_mask = m_viper_regs[VIPER_REG_SCROLL_LEFT];
	u16 const right_mask = m_viper_regs[VIPER_REG_SCROLL_RIGHT];
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

	u16 const distance = std::min<u16>(scroll & 0x0fff, y_max - y_min);
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

u32 vt340_state::screen_update(screen_device &, bitmap_rgb32 &bitmap, rectangle const &cliprect)
{
	// Four serial bitmap planes form a 16-entry E51/E52 color-map index.  Use
	// genuine 12-bit RGB after firmware has programmed both halves of an entry.
	// Entries not programmed after graphics POST retain a monochrome fallback
	// so firmware-written pixels remain visible without inventing RGB values.
	for (int y = cliprect.top(); y <= cliprect.bottom(); y++)
		for (int x = cliprect.left(); x <= cliprect.right(); x++)
		{
			u8 color = 0;
			for (unsigned plane = 0; plane < BITMAP_PLANES; plane++)
				color |= m_bitmap_planes[bitmap_plane_address(plane, x, y)] << plane;
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
	std::fill_n(&m_bitmap_planes[0], BITMAP_PLANES * BITMAP_PLANE_SIZE, 0);
	m_cpu2_hsync_timer = timer_alloc(FUNC(vt340_state::cpu2_hsync_tick), this);
	m_cpu2_vsync_timer = timer_alloc(FUNC(vt340_state::cpu2_vsync_tick), this);

	machine().add_notifier(MACHINE_NOTIFY_EXIT, machine_notify_delegate(&vt340_state::trace_exit, this));

	save_item(NAME(m_cpu1_p3));
	save_item(NAME(m_cpu2_p3));
	save_item(NAME(m_cpu1_p1));
	save_item(NAME(m_cpu2_p1));
	save_item(NAME(m_cpu2_p2));
	save_item(NAME(m_dat9_bus_phase));
	save_item(NAME(m_board_status));
	save_item(NAME(m_video_test_select));
	save_item(NAME(m_cpu2_hsync_low));
	save_item(NAME(m_cpu1_brd_strobe));
	save_item(NAME(m_cpu2_t1_pulse));
	save_item(NAME(m_keyboard_rxd));
	save_item(NAME(m_cpu1_t1_pulses));
	save_item(NAME(m_adder_ready));
	save_item(NAME(m_dc323_post_mode));
	save_item(NAME(m_bitmap_post_done));
	save_item(NAME(m_bitmap_test_reads));
	save_item(NAME(m_adder_test_data));
	save_item(NAME(m_adder_raster_test));
	save_item(NAME(m_adder_regs));
	save_item(NAME(m_adder_status));
	save_item(NAME(m_scroll_pending));
	save_item(NAME(m_viper_regs));
	save_item(NAME(m_pbt_read_active));
	save_item(NAME(m_pbt_read_index));
	save_item(NAME(m_pbt_read_count));
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
		BIT(m_cpu2->state_int(MCS51_P3), 3) ? "E4" : "E5", dc323_post_bitmap_selected(),
		m_bitmap_test_reads, m_video_test_select, m_cpu1_t1_pulses);
}

TIMER_CALLBACK_MEMBER(vt340_state::cpu2_hsync_tick)
{
	m_cpu2_hsync_low = !m_cpu2_hsync_low;
	m_cpu2->set_input_line(MCS51_T0_LINE, m_cpu2_hsync_low ? ASSERT_LINE : CLEAR_LINE);
}

TIMER_CALLBACK_MEMBER(vt340_state::cpu2_vsync_tick)
{
	execute_scroll();
	// Pause Complete and Scroll Service are generated at the vertical frame
	// boundary.  Both are sticky DC323 status conditions; interrupt assertion
	// additionally depends on the matching enable bit in register 2.
	m_adder_status |= DC323_STATUS_PAUSE_COMPLETE | DC323_STATUS_SCROLL_SERVICE;
	update_dc323_interrupt();
}

void vt340_state::machine_reset()
{
	m_cpu1_p3 = 0xff;
	m_cpu2_p3 = 0xff;
	m_cpu1_p1 = 0xff;
	m_cpu2_p1 = 0xff;
	m_cpu2_p2 = 0xff;
	m_dat9_bus_phase = DAT9_WAIT_BRD_READ;
	m_board_status = true;
	m_video_test_select = 0;
	m_cpu2_hsync_low = true;
	m_cpu1_brd_strobe = false;
	m_cpu2_t1_pulse = false;
	m_keyboard_rxd = true;
	m_cpu1_t1_pulses = 0;
	m_adder_ready = false;
	m_dc323_post_mode = DC323_POST_INACTIVE;
	m_bitmap_post_done = false;
	m_bitmap_test_reads = 0;
	m_adder_test_data = 0;
	m_adder_raster_test = false;
	m_adder_regs.fill(0);
	m_adder_status = 0;
	m_scroll_pending = false;
	m_viper_regs.fill(0);
	m_pbt_read_active = false;
	m_pbt_read_index = 0;
	m_pbt_read_count = 0;
	m_dc7051_low.fill(0);
	m_dc7051_high.fill(0);
	m_palette_rg.fill(0);
	m_palette_gb.fill(0);
	m_palette_rg_valid = 0;
	m_palette_gb_valid = 0;
	m_video_operational = false;
	std::fill_n(&m_bitmap_planes[0], BITMAP_PLANES * BITMAP_PLANE_SIZE, 0);
	m_cpu1_trace_events = 0;
	m_cpu2_trace_events = 0;
	m_cpu1_io_trace_events = 0;
	m_cpu2_io_trace_events = 0;
	// Processor 1 T0 is tied to the active-low P1 BRD bus-read strobe.  The
	// startup bus test samples it while performing its probe read.
	m_cpu1->set_input_line(MCS51_T0_LINE, CLEAR_LINE);
	update_dat9_input();
	m_cpu2->set_input_line(INPUT_LINE_RESET, ASSERT_LINE);
	// Unconnected serial inputs idle in the marking state.  Leaving these
	// device pins at their zero-initialized level presents a continuous break
	// to the firmware and can manufacture receive characters during startup.
	m_duart->rx_a_w(1);
	m_duart->rx_b_w(1);
	m_printer_uart->rxd_w(1);
	// E81's active-low CTS and DCD inputs are tied to ground on schematic
	// sheet 8P0.  Local loopback ignores both pins, but normal mode must see
	// the permanently asserted levels implemented by the board.
	m_printer_uart->cts_w(0);
	m_printer_uart->dcd_w(0);
	m_cpu2->set_input_line(MCS51_T0_LINE, ASSERT_LINE);
	m_cpu2_hsync_timer->adjust(attotime::from_hz(63'000), 0, attotime::from_hz(63'000));
	m_cpu2->set_input_line(MCS51_INT0_LINE, CLEAR_LINE);
	m_cpu2_vsync_timer->adjust(attotime::never);
	LOGMASKED(LOG_PORTS, "VT340 reset: CPU1 E1/E2, CPU2 E3/E4 selected\n");
}

void vt340_state::vt340(machine_config &config)
{
	// E57 is an Intel 8031 on the terminal-control-module schematic.
	I8031(config, m_cpu1, 12_MHz_XTAL);
	m_cpu1->set_addrmap(AS_PROGRAM, &vt340_state::cpu1_program_map);
	m_cpu1->set_addrmap(AS_DATA, &vt340_state::cpu1_data_map);
	m_cpu1->port_in_cb<1>().set(FUNC(vt340_state::cpu1_p1_r));
	m_cpu1->port_out_cb<1>().set(FUNC(vt340_state::cpu1_p1_w));
	m_cpu1->port_in_cb<3>().set(FUNC(vt340_state::cpu1_p3_r));
	m_cpu1->port_out_cb<3>().set(FUNC(vt340_state::cpu1_p3_w));

	LK201(config, m_keyboard);
	m_keyboard->tx_handler().set(FUNC(vt340_state::keyboard_rxd_w));

	// E61 is the SCN2681 DUART.  Its active-low interrupt output drives the
	// processor-1 INT0 input.  The 3.6864 MHz clock is the standard crystal
	// frequency used by the part's baud-rate generator.
	SCN2681(config, m_duart, 3.6864_MHz_XTAL);
	m_duart->irq_cb().set_inputline(m_cpu1, MCS51_INT0_LINE);
	m_duart->a_tx_cb().set(m_comm1, FUNC(rs232_port_device::write_txd));
	m_duart->b_tx_cb().set(m_comm2, FUNC(rs232_port_device::write_txd));
	m_duart->inport_cb().set(FUNC(vt340_state::duart_input_r));
	m_duart->outport_cb().set(m_comm1, FUNC(rs232_port_device::write_rts)).bit(0);
	m_duart->outport_cb().append(m_comm1, FUNC(rs232_port_device::write_dtr)).bit(1);
	m_duart->outport_cb().append(m_comm1, FUNC(rs232_port_device::write_spds)).bit(2);
	m_duart->outport_cb().append(m_comm2, FUNC(rs232_port_device::write_dtr)).bit(7);

	RS232_PORT(config, m_comm1, default_rs232_devices, nullptr);
	m_comm1->set_option_device_input_defaults("null_modem", DEVICE_INPUT_DEFAULTS_NAME(comm1_defaults));
	m_comm1->set_option_device_input_defaults("pty", DEVICE_INPUT_DEFAULTS_NAME(comm1_defaults));
	m_comm1->rxd_handler().set(m_duart, FUNC(scn2681_device::rx_a_w));
	m_comm1->cts_handler().set(m_duart, FUNC(scn2681_device::ip0_w));
	m_comm1->dsr_handler().set(m_duart, FUNC(scn2681_device::ip1_w));
	m_comm1->dsr_handler().append(m_duart, FUNC(scn2681_device::ip4_w));
	m_comm1->si_handler().set(m_duart, FUNC(scn2681_device::ip2_w));
	m_comm1->dcd_handler().set(m_duart, FUNC(scn2681_device::ip3_w));

	RS232_PORT(config, m_comm2, default_rs232_devices, nullptr);
	m_comm2->set_option_device_input_defaults("null_modem", DEVICE_INPUT_DEFAULTS_NAME(comm2_defaults));
	m_comm2->set_option_device_input_defaults("pty", DEVICE_INPUT_DEFAULTS_NAME(comm2_defaults));
	m_comm2->rxd_handler().set(m_duart, FUNC(scn2681_device::rx_b_w));
	m_comm2->dsr_handler().set(m_duart, FUNC(scn2681_device::ip5_w));

	// E81 is the SCN2641 printer communications interface.  Its interrupt
	// output is connected to processor-1 INT1; the keyboard instead uses the
	// processor's internal UART on P3.0/P3.1.
	SCN2641(config, m_printer_uart, 3.6864_MHz_XTAL);
	m_printer_uart->intr_handler().set_inputline(m_cpu1, MCS51_INT1_LINE);

	EEPROM_2804(config, m_eeprom); // E80, Xicor X2804AP-45

	I8031(config, m_cpu2, 12_MHz_XTAL);
	m_cpu2->set_addrmap(AS_PROGRAM, &vt340_state::cpu2_program_map);
	m_cpu2->set_addrmap(AS_DATA, &vt340_state::cpu2_data_map);
	m_cpu2->port_in_cb<1>().set(FUNC(vt340_state::cpu2_p1_r));
	m_cpu2->port_out_cb<1>().set(FUNC(vt340_state::cpu2_p1_w));
	m_cpu2->port_in_cb<2>().set(FUNC(vt340_state::cpu2_p2_r));
	m_cpu2->port_out_cb<2>().set(FUNC(vt340_state::cpu2_p2_w));
	m_cpu2->port_in_cb<3>().set(FUNC(vt340_state::cpu2_p3_r));
	m_cpu2->port_out_cb<3>().set(FUNC(vt340_state::cpu2_p3_w));
	// Y1 clocks the DC7051.  Its 32.3174 MHz rate divided by the programmed
	// 1026 clocks and 526 lines gives the measured 31.5 kHz / 59.89 Hz raster.
	// The 800x500 visible area includes the terminal's 25th status line.
	SCREEN(config, m_screen);
	m_screen->set_raw(XTAL(32'317'400), 1026, 0, SCREEN_WIDTH, 526, 0, SCREEN_HEIGHT);
	m_screen->set_screen_update(FUNC(vt340_state::screen_update));
}


static INPUT_PORTS_START(vt340)
INPUT_PORTS_END


ROM_START(vt340)
	// Keep the published files byte-for-byte intact.  init_vt340 reconstructs
	// their lagged address stream, including every recoverable xxFF boundary.
	ROM_REGION(0x8000, "e1raw", 0)
	ROM_LOAD("e1.bin", 0x0000, 0x8000, CRC(68b3cbde) SHA1(d51677c17e056c69a5864b1673f7887b24f50958))
	ROM_REGION(0x8000, "e2raw", 0)
	ROM_LOAD("e2.bin", 0x0000, 0x8000, CRC(19f788f0) SHA1(f4018501fee8c429bc1148014f2d9bb97e8cfdcf))
	ROM_REGION(0x8000, "e3raw", 0)
	ROM_LOAD("e3.bin", 0x0000, 0x8000, CRC(83919be1) SHA1(937b36e0475a8947a01d03c8e800c54a6461caf7))
	ROM_REGION(0x8000, "e4raw", 0)
	ROM_LOAD("e4.bin", 0x0000, 0x8000, CRC(d6eddc42) SHA1(df8097bcd04bd9fed5618d88cd0e0159f81c074b))
	ROM_REGION(0x8000, "e5raw", 0)
	ROM_LOAD("e5.bin", 0x0000, 0x8000, CRC(135c5c7c) SHA1(171d1582d6a62ec9fa8e42421693da6dac3b2a8a))

	ROM_REGION(0x8000, "cpu1low", ROMREGION_ERASEFF)
	ROM_REGION(0x8000, "cpu1high", ROMREGION_ERASEFF)
	ROM_REGION(0x8000, "cpu2low", ROMREGION_ERASEFF)
	ROM_REGION(0x10000, "cpu2banks", ROMREGION_ERASEFF)

	ROM_REGION(0x8000, "chargen", 0)
	ROM_LOAD("vt340e49.bin", 0x0000, 0x8000, CRC(38379339) SHA1(394e8511581abc796c8c612149eff280146b0ac8))

	ROM_REGION(0x0200, "eeprom", ROMREGION_ERASEFF)
	ROM_LOAD("e80.bin", 0x0000, 0x0200, CRC(d1fd44bb) SHA1(ffbdeeffb55374211a371a77ed633b780cd0f526)) // Xicor X2804AP-45 (512 x 8 EEPROM)
ROM_END

} // anonymous namespace


COMP(1987, vt340, 0, 0, vt340, vt340, vt340_state, init_vt340, "Digital Equipment Corporation", "VT340 Video Terminal", MACHINE_NO_SOUND | MACHINE_NOT_WORKING)
