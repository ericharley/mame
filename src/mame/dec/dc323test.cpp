// license:BSD-3-Clause
// copyright-holders:Harley Card
/***************************************************************************

    Firmware-free regression harness for the DEC DC323 device

    This is a firmware-free MAME unit-test system.  The reproduction script
    builds it as a dedicated subtarget and treats any fatal error as failure.

***************************************************************************/

#include "emu.h"

#include "video/dc323.h"


namespace {

class dc323_test_state : public driver_device
{
public:
	dc323_test_state(machine_config const &mconfig, device_type type, char const *tag) :
		driver_device(mconfig, type, tag),
		m_dc323(*this, "dc323")
	{
	}

	void dc323test(machine_config &config);

private:
	required_device<dc323_device> m_dc323;
	emu_timer *m_test_timer = nullptr;
	bool m_irq = false;

	virtual void machine_start() override ATTR_COLD;
	virtual void machine_reset() override ATTR_COLD;
	void irq_w(int state) { m_irq = bool(state); }
	void require(bool condition, char const *message);
	void reg_w(unsigned reg, u16 value) { m_dc323->write(reg, value); }
	void viper_w(unsigned reg, u16 value);
	void fill(unsigned x, unsigned y, unsigned width, unsigned height, bool value);
	void expect_pixel(unsigned x, unsigned y, bool value, char const *message);
	TIMER_CALLBACK_MEMBER(run_tests);
};


void dc323_test_state::machine_start()
{
	m_test_timer = timer_alloc(FUNC(dc323_test_state::run_tests), this);
}


void dc323_test_state::machine_reset()
{
	m_test_timer->adjust(attotime::zero);
}


void dc323_test_state::require(bool condition, char const *message)
{
	if (!condition)
		fatalerror("DC323 device regression failed: %s\n", message);
}


void dc323_test_state::viper_w(unsigned reg, u16 value)
{
	reg_w(dc323_device::REG_ID_DATA, value);
	reg_w(dc323_device::REG_COMMAND, 0x0180 | (reg & 0x1f));
}


void dc323_test_state::fill(unsigned x, unsigned y, unsigned width, unsigned height, bool value)
{
	viper_w(0x08, 0xffff);
	viper_w(0x09, 0xffff);
	viper_w(0x0a, value ? 0xffff : 0x0000);
	reg_w(dc323_device::REG_X_CONTROL, 0x0080);
	reg_w(dc323_device::REG_DESTINATION_X, x);
	reg_w(dc323_device::REG_DESTINATION_Y, y);
	reg_w(dc323_device::REG_WIDTH, width);
	reg_w(dc323_device::REG_DESTINATION_FAST_DY, 0);
	reg_w(dc323_device::REG_DESTINATION_SLOW_DX, 0);
	reg_w(dc323_device::REG_HEIGHT, height);
	reg_w(dc323_device::REG_COMMAND, 0x06c0);
}


void dc323_test_state::expect_pixel(unsigned x, unsigned y, bool value, char const *message)
{
	for (unsigned plane = 0; plane < dc323_device::BITMAP_PLANES; plane++)
		require(bool(m_dc323->pixel_r(plane, x, y)) == value, message);
}


TIMER_CALLBACK_MEMBER(dc323_test_state::run_tests)
{
	// Register storage and operational status/IRQ acknowledgement.
	require(m_dc323->viper_select_r() == 0, "Viper selects reset clear");
	reg_w(0x30, 0xa55a);
	require(m_dc323->register_r(0x30) == 0xa55a, "16-bit register retention");
	require(m_dc323->read(0x30) == 0x5a, "low data-bus readback");
	m_dc323->frame_event();
	require((m_dc323->status_r() &
		(dc323_device::STATUS_PAUSE_COMPLETE | dc323_device::STATUS_SCROLL_SERVICE)) == 0,
		"frame service is suppressed while reset holds the device non-operational");
	m_dc323->operational_w(1);
	require((m_dc323->status_r() & dc323_device::STATUS_RASTEROP_MASK) ==
		dc323_device::STATUS_RASTEROP_MASK, "idle command engines report complete");
	require((m_dc323->status_r() & dc323_device::STATUS_ID_DATA_READY) == 0,
		"idle I/D receive FIFO is not ready");

	// Diagnostic 0BC0 reads use the retained I/D test source while following
	// the ordinary one-byte FIFO completion path.
	reg_w(dc323_device::REG_WIDTH, 8);
	reg_w(dc323_device::REG_HEIGHT, 1);
	reg_w(dc323_device::REG_ID_DATA, 0x00c6);
	reg_w(dc323_device::REG_SOURCE_X, 0);
	reg_w(dc323_device::REG_COMMAND, 0x0bc0);
	require(m_dc323->read(dc323_device::REG_ID_DATA) == 0xaa,
		"raster diagnostic low address pattern");
	require((m_dc323->status_r() & dc323_device::STATUS_ADDRESS_COMPLETE) != 0 &&
		(m_dc323->status_r() & dc323_device::STATUS_ID_DATA_READY) == 0,
		"diagnostic read completes I/D address output");
	reg_w(dc323_device::REG_SOURCE_X, 8);
	reg_w(dc323_device::REG_COMMAND, 0x0bc0);
	require(m_dc323->read(dc323_device::REG_ID_DATA) == 0x55,
		"raster diagnostic high address pattern");
	reg_w(dc323_device::REG_ID_DATA, 0x00cf);
	reg_w(dc323_device::REG_COMMAND, 0x0bc0);
	require(m_dc323->read(dc323_device::REG_ID_DATA) == 0xff,
		"retained diagnostic all-ones pattern");
	reg_w(dc323_device::REG_WIDTH, 16);
	reg_w(dc323_device::REG_HEIGHT, 2);
	reg_w(dc323_device::REG_COMMAND, 0x0bc0);
	require((m_dc323->status_r() & dc323_device::STATUS_ID_DATA_READY) != 0,
		"multi-byte diagnostic transfer becomes ready");
	reg_w(dc323_device::REG_COMMAND, 0x0000);
	require((m_dc323->status_r() & dc323_device::STATUS_ID_DATA_READY) == 0 &&
		(m_dc323->status_r() & dc323_device::STATUS_ADDRESS_COMPLETE) != 0,
		"zero command aborts transfer into completed idle state");

	reg_w(dc323_device::REG_INTERRUPT_ENABLE, 0x0003);
	m_dc323->frame_event();
	require((m_dc323->status_r() & 0x0003) == 0x0003, "frame status generation");
	require(m_irq, "enabled frame status asserts IRQ");
	reg_w(dc323_device::REG_STATUS, 0x0000);
	require(m_dc323->status_r() == 0 && !m_irq, "status acknowledgement clears IRQ");
	m_dc323->viper_select_w(0x0f);
	viper_w(0x0e, 0x0000);
	viper_w(0x0f, 0xffff);
	reg_w(dc323_device::REG_SOURCE_FAST_DX, 1);
	reg_w(dc323_device::REG_SOURCE_SLOW_DY, 1);
	reg_w(dc323_device::REG_DESTINATION_FAST_DY, 0);
	reg_w(dc323_device::REG_DESTINATION_SLOW_DX, 0);
	reg_w(dc323_device::REG_FAST_SCALE, 0x1fff);
	reg_w(dc323_device::REG_SLOW_SCALE, 0x1fff);

	// Constant fill affects all planes and preserves pixels beyond the region.
	m_dc323->bitmap_clear();
	viper_w(0x04, 0x00ca);
	fill(4, 3, 4, 2, true);
	for (unsigned y = 3; y < 5; y++)
		for (unsigned x = 4; x < 8; x++)
			expect_pixel(x, y, true, "constant fill region");
	expect_pixel(3, 3, false, "constant fill left clipping");
	expect_pixel(8, 3, false, "constant fill right clipping");

	// Each Viper retains independent color registers.  The logic-unit result
	// selects foreground/background per plane, producing a four-bit color
	// index rather than broadcasting one Boolean result to every plane.
	m_dc323->bitmap_clear();
	viper_w(0x04, 0x00ca);
	viper_w(0x08, 0xffff);
	viper_w(0x09, 0xffff);
	viper_w(0x0a, 0xffff);
	reg_w(dc323_device::REG_X_CONTROL, 0x0080);
	reg_w(dc323_device::REG_DESTINATION_Y, 0);
	reg_w(dc323_device::REG_WIDTH, 1);
	reg_w(dc323_device::REG_HEIGHT, 1);
	for (unsigned color = 0; color < 16; color++)
	{
		for (unsigned plane = 0; plane < dc323_device::BITMAP_PLANES; plane++)
		{
			m_dc323->viper_select_w(1U << plane);
			viper_w(0x0e, 0x0000);
			viper_w(0x0f, BIT(color, plane) ? 0xffff : 0x0000);
		}
		m_dc323->viper_select_w(0x0f);
		reg_w(dc323_device::REG_DESTINATION_X, color);
		reg_w(dc323_device::REG_COMMAND, 0x06c0);
		for (unsigned plane = 0; plane < dc323_device::BITMAP_PLANES; plane++)
			require(bool(m_dc323->pixel_r(plane, color, 0)) == bool(BIT(color, plane)),
				"per-plane foreground produces color index");
	}
	require(m_dc323->viper_register_r(0, 0x0f) == 0xffff &&
		m_dc323->viper_register_r(1, 0x0f) == 0xffff &&
		m_dc323->viper_register_r(2, 0x0f) == 0xffff &&
		m_dc323->viper_register_r(3, 0x0f) == 0xffff,
		"independent foreground registers retain final color");
	m_dc323->bitmap_clear();

	// X-mode processor-to-bitmap transfers consume one I/D FIFO word per
	// destination bus word and scanline.  The sixel firmware uses the 1x6 form
	// to stage one sixel column in off-screen bitmap memory.
	viper_w(0x01, 0x0004); // 8-bit bitmap bus
	viper_w(0x05, 0x00ca); // function 1 copies the processor source bit
	viper_w(0x11, 0x0001); // CSR 1 loads processor data into the source register
	viper_w(0x08, 0xffff);
	viper_w(0x09, 0xffff);
	viper_w(0x0e, 0x0000);
	viper_w(0x0f, 0xffff);
	reg_w(dc323_device::REG_STATUS, 0x0000);
	reg_w(dc323_device::REG_DESTINATION_X, 8);
	reg_w(dc323_device::REG_DESTINATION_Y, 10);
	reg_w(dc323_device::REG_WIDTH, 1);
	reg_w(dc323_device::REG_HEIGHT, 6);
	reg_w(dc323_device::REG_COMMAND, 0x07d1);
	require((m_dc323->status_r() & dc323_device::STATUS_ID_DATA_TRANSMIT_READY) != 0,
		"PTB start accepts processor data");
	require((m_dc323->status_r() & dc323_device::STATUS_ADDRESS_COMPLETE) == 0,
		"PTB address completion waits for FIFO data");
	for (unsigned row = 0; row < 6; row++)
	{
		reg_w(dc323_device::REG_ID_DATA, BIT(row, 0) ? 0x0000 : 0x0001);
		if (row != 5)
			require((m_dc323->status_r() & dc323_device::STATUS_ADDRESS_COMPLETE) == 0,
				"PTB remains active before final word");
	}
	require((m_dc323->status_r() & dc323_device::STATUS_ADDRESS_COMPLETE) != 0,
		"PTB final word completes address output");
	for (unsigned row = 0; row < 6; row++)
		expect_pixel(8, 10 + row, !BIT(row, 0), "PTB 1x6 source data");

	// An unaligned rectangle consumes the leading and trailing bus words but
	// masks pixels outside the requested destination extent.
	m_dc323->bitmap_clear();
	reg_w(dc323_device::REG_DESTINATION_X, 3);
	reg_w(dc323_device::REG_DESTINATION_Y, 20);
	reg_w(dc323_device::REG_WIDTH, 7);
	reg_w(dc323_device::REG_HEIGHT, 1);
	reg_w(dc323_device::REG_COMMAND, 0x07d1);
	reg_w(dc323_device::REG_ID_DATA, 0x00a8);
	require((m_dc323->status_r() & dc323_device::STATUS_ADDRESS_COMPLETE) == 0,
		"unaligned PTB requires trailing word");
	reg_w(dc323_device::REG_ID_DATA, 0x0002);
	for (unsigned x = 3; x < 10; x++)
		expect_pixel(x, 20, BIT(x, 0), "unaligned PTB word alignment");
	expect_pixel(2, 20, false, "unaligned PTB preserves leading pixel");
	expect_pixel(10, 20, false, "unaligned PTB preserves trailing pixel");

	// The selected CSR controls the processor word's Viper destination.  A
	// mask load affects write enables while retaining the source register.
	m_dc323->bitmap_clear();
	viper_w(0x11, 0x0002); // CSR 1 loads mask 1 and mask 2
	viper_w(0x0a, 0xffff);
	reg_w(dc323_device::REG_DESTINATION_X, 0);
	reg_w(dc323_device::REG_DESTINATION_Y, 30);
	reg_w(dc323_device::REG_WIDTH, 4);
	reg_w(dc323_device::REG_HEIGHT, 1);
	reg_w(dc323_device::REG_COMMAND, 0x07d1);
	reg_w(dc323_device::REG_ID_DATA, 0x0005);
	require(m_dc323->viper_register_r(0, 0x08) == 0x0005 &&
		m_dc323->viper_register_r(0, 0x09) == 0x0005,
		"PTB CSR loads both Viper masks");
	for (unsigned x = 0; x < 4; x++)
		expect_pixel(x, 30, BIT(0x0005, x), "PTB mask data routing");
	viper_w(0x11, 0x0001);

	// Raster masks and bitmap clipping retain the established orientation.
	m_dc323->bitmap_clear();
	viper_w(0x08, 0x0005);
	viper_w(0x09, 0xffff);
	viper_w(0x0a, 0xffff);
	reg_w(dc323_device::REG_X_CONTROL, 0x0080);
	reg_w(dc323_device::REG_DESTINATION_X, 0);
	reg_w(dc323_device::REG_DESTINATION_Y, 0);
	reg_w(dc323_device::REG_WIDTH, 4);
	reg_w(dc323_device::REG_HEIGHT, 1);
	reg_w(dc323_device::REG_COMMAND, 0x06c0);
	expect_pixel(0, 0, true, "mask bit zero");
	expect_pixel(1, 0, false, "masked pixel one");
	expect_pixel(2, 0, true, "mask bit two");
	expect_pixel(3, 0, false, "masked pixel three");
	fill(1023, 1, 4, 1, true);
	expect_pixel(1023, 1, true, "right bitmap clipping");

	// Forward overlapping source copy is preserved as legacy behavior.
	m_dc323->bitmap_clear();
	fill(0, 5, 2, 1, true);
	viper_w(0x08, 0xffff);
	viper_w(0x09, 0xffff);
	reg_w(dc323_device::REG_SOURCE_X, 0);
	reg_w(dc323_device::REG_SOURCE_Y, 5);
	reg_w(dc323_device::REG_DESTINATION_X, 2);
	reg_w(dc323_device::REG_DESTINATION_Y, 5);
	reg_w(dc323_device::REG_WIDTH, 6);
	reg_w(dc323_device::REG_HEIGHT, 1);
	reg_w(dc323_device::REG_COMMAND, 0x0ec0);
	for (unsigned x = 0; x < 8; x++)
		expect_pixel(x, 5, true, "overlapping source copy");

	// Normal-mode up scaling maps one source row across a destination character
	// cell.  The VT340 uses this exact 1:20 form when restoring the terminal
	// backing store after leaving Set-Up.
	m_dc323->bitmap_clear();
	fill(0, 60, 8, 1, true);
	fill(0, 61, 8, 1, false);
	reg_w(dc323_device::REG_SOURCE_X, 0);
	reg_w(dc323_device::REG_SOURCE_Y, 60);
	reg_w(dc323_device::REG_DESTINATION_X, 20);
	reg_w(dc323_device::REG_DESTINATION_Y, 70);
	reg_w(dc323_device::REG_WIDTH, 8);
	reg_w(dc323_device::REG_HEIGHT, 20);
	reg_w(dc323_device::REG_SLOW_SCALE, 0x0199);
	reg_w(dc323_device::REG_COMMAND, 0x0ec0);
	for (unsigned y = 70; y < 90; y++)
		for (unsigned x = 20; x < 28; x++)
			expect_pixel(x, y, true, "normal-mode 1:20 slow scaling");
	reg_w(dc323_device::REG_SLOW_SCALE, 0x1fff);

	// Mode bits 0-1 select normal mode; hole-fill bit 4 must not cause the
	// operation to be rejected.  The two signed destination vectors are walked
	// independently, allowing the firmware to rotate a raster rectangle.
	m_dc323->bitmap_clear();
	viper_w(0x04, 0x00ca);
	viper_w(0x08, 0xffff);
	viper_w(0x09, 0xffff);
	viper_w(0x0a, 0xffff);
	reg_w(dc323_device::REG_X_CONTROL, 0x0090);
	reg_w(dc323_device::REG_DESTINATION_X, 10);
	reg_w(dc323_device::REG_DESTINATION_Y, 10);
	reg_w(dc323_device::REG_WIDTH, 0);
	reg_w(dc323_device::REG_DESTINATION_FAST_DY, 4);
	reg_w(dc323_device::REG_DESTINATION_SLOW_DX, 3);
	reg_w(dc323_device::REG_HEIGHT, 0);
	reg_w(dc323_device::REG_COMMAND, 0x06c0);
	for (unsigned y = 10; y < 14; y++)
		for (unsigned x = 10; x < 13; x++)
			expect_pixel(x, y, true, "rotated normal-mode rectangle");
	expect_pixel(13, 10, false, "rotated rectangle excludes vector endpoint");

	// The DC323 initializes Bresenham error to minus the major-axis magnitude.
	// A 4x2 vector therefore visits (0,0), (1,1), (2,1), and (3,2).
	m_dc323->bitmap_clear();
	reg_w(dc323_device::REG_X_CONTROL, 0x0080);
	reg_w(dc323_device::REG_DESTINATION_X, 20);
	reg_w(dc323_device::REG_DESTINATION_Y, 20);
	reg_w(dc323_device::REG_WIDTH, 4);
	reg_w(dc323_device::REG_DESTINATION_FAST_DY, 2);
	reg_w(dc323_device::REG_DESTINATION_SLOW_DX, 0);
	reg_w(dc323_device::REG_HEIGHT, 1);
	reg_w(dc323_device::REG_COMMAND, 0x06c0);
	expect_pixel(20, 20, true, "Bresenham vector origin");
	expect_pixel(21, 21, true, "Bresenham first minor step");
	expect_pixel(22, 21, true, "Bresenham retained minor coordinate");
	expect_pixel(23, 22, true, "Bresenham final selected point");
	expect_pixel(24, 22, false, "Bresenham excludes vector endpoint");

	// Operation-2 diagnostic forms with the destination disabled must not
	// modify bitmap memory even when the remaining raster state is drawable.
	m_dc323->bitmap_clear();
	reg_w(dc323_device::REG_X_CONTROL, 0x0080);
	reg_w(dc323_device::REG_DESTINATION_X, 45);
	reg_w(dc323_device::REG_DESTINATION_Y, 45);
	reg_w(dc323_device::REG_WIDTH, 2);
	reg_w(dc323_device::REG_HEIGHT, 2);
	reg_w(dc323_device::REG_COMMAND, 0x02c0);
	expect_pixel(45, 45, false, "destination-disabled raster does not draw");

	// Mode 01 is reserved, not fill mode.
	m_dc323->bitmap_clear();
	reg_w(dc323_device::REG_X_CONTROL, 0x0081);
	reg_w(dc323_device::REG_DESTINATION_X, 45);
	reg_w(dc323_device::REG_DESTINATION_Y, 45);
	reg_w(dc323_device::REG_WIDTH, 2);
	reg_w(dc323_device::REG_HEIGHT, 2);
	reg_w(dc323_device::REG_COMMAND, 0x06c0);
	expect_pixel(45, 45, false, "reserved mode 01 does not draw");

	// Fill mode uses the destination slow generator for edge A and the source
	// generator for edge B.  X fill scans horizontally between two edges while
	// advancing in Y; both edge pixels are included and the vector endpoints
	// are excluded.
	m_dc323->bitmap_clear();
	viper_w(0x04, 0x00ca);
	viper_w(0x08, 0xffff);
	viper_w(0x09, 0xffff);
	viper_w(0x0a, 0xffff);
	reg_w(dc323_device::REG_X_CONTROL, 0x0083);
	reg_w(dc323_device::REG_DESTINATION_X, 50);
	reg_w(dc323_device::REG_DESTINATION_Y, 50);
	reg_w(dc323_device::REG_SOURCE_X, 54);
	reg_w(dc323_device::REG_SOURCE_Y, 0);
	reg_w(dc323_device::REG_DESTINATION_SLOW_DX, 0);
	reg_w(dc323_device::REG_HEIGHT, 4);
	reg_w(dc323_device::REG_SOURCE_FAST_DX, 0);
	reg_w(dc323_device::REG_SOURCE_SLOW_DY, 4);
	reg_w(dc323_device::REG_COMMAND, 0x06c0);
	for (unsigned y = 50; y < 54; y++)
		for (unsigned x = 50; x <= 54; x++)
			expect_pixel(x, y, true, "two-edge X fill interior");
	expect_pixel(49, 50, false, "two-edge X fill left exterior");
	expect_pixel(55, 50, false, "two-edge X fill right exterior");
	expect_pixel(50, 54, false, "two-edge X fill excludes edge endpoint");

	// A polygon is submitted as a vector string.  After one paired edge
	// command, the next pair starts at the previous A/B endpoints without
	// reloading either origin.  These two pairs form the upper and lower halves
	// of a small diamond; the final endpoint remains excluded.
	m_dc323->bitmap_clear();
	reg_w(dc323_device::REG_DESTINATION_X, 100);
	reg_w(dc323_device::REG_DESTINATION_Y, 100);
	reg_w(dc323_device::REG_SOURCE_X, 100);
	reg_w(dc323_device::REG_DESTINATION_SLOW_DX, 0x3ffc); // -4
	reg_w(dc323_device::REG_HEIGHT, 4);
	reg_w(dc323_device::REG_SOURCE_FAST_DX, 4);
	reg_w(dc323_device::REG_SOURCE_SLOW_DY, 4);
	reg_w(dc323_device::REG_COMMAND, 0x06c0);
	reg_w(dc323_device::REG_DESTINATION_SLOW_DX, 4);
	reg_w(dc323_device::REG_HEIGHT, 4);
	reg_w(dc323_device::REG_SOURCE_FAST_DX, 0x3ffc); // -4
	reg_w(dc323_device::REG_SOURCE_SLOW_DY, 4);
	reg_w(dc323_device::REG_COMMAND, 0x06c0);
	for (unsigned x = 96; x <= 104; x++)
		expect_pixel(x, 104, true, "chained fill begins at previous edge endpoints");
	for (unsigned x = 99; x <= 101; x++)
		expect_pixel(x, 107, true, "chained fill converging edge pair");
	expect_pixel(95, 104, false, "chained fill lower left exterior");
	expect_pixel(105, 104, false, "chained fill lower right exterior");
	expect_pixel(100, 108, false, "chained fill excludes final endpoint");

	// Loading a destination origin terminates the prior vector string and
	// initializes both edge positions for a new fill.
	reg_w(dc323_device::REG_DESTINATION_X, 120);
	reg_w(dc323_device::REG_DESTINATION_Y, 120);
	reg_w(dc323_device::REG_SOURCE_X, 124);
	reg_w(dc323_device::REG_DESTINATION_SLOW_DX, 0);
	reg_w(dc323_device::REG_HEIGHT, 2);
	reg_w(dc323_device::REG_SOURCE_FAST_DX, 0);
	reg_w(dc323_device::REG_SOURCE_SLOW_DY, 2);
	reg_w(dc323_device::REG_COMMAND, 0x06c0);
	for (unsigned x = 120; x <= 124; x++)
		expect_pixel(x, 120, true, "destination origin restarts fill string");
	expect_pixel(100, 108, false, "restarted fill does not continue old string");

	// Y fill swaps the axis roles: the source Y origin supplies edge B and the
	// hardware scans vertically between the two horizontal edges.
	m_dc323->bitmap_clear();
	reg_w(dc323_device::REG_X_CONTROL, 0x0087);
	reg_w(dc323_device::REG_DESTINATION_X, 60);
	reg_w(dc323_device::REG_DESTINATION_Y, 60);
	reg_w(dc323_device::REG_SOURCE_X, 0);
	reg_w(dc323_device::REG_SOURCE_Y, 64);
	reg_w(dc323_device::REG_DESTINATION_SLOW_DX, 4);
	reg_w(dc323_device::REG_HEIGHT, 0);
	reg_w(dc323_device::REG_SOURCE_FAST_DX, 4);
	reg_w(dc323_device::REG_SOURCE_SLOW_DY, 0);
	reg_w(dc323_device::REG_COMMAND, 0x06c0);
	for (unsigned x = 60; x < 64; x++)
		for (unsigned y = 60; y <= 64; y++)
			expect_pixel(x, y, true, "two-edge Y fill interior");
	expect_pixel(64, 60, false, "two-edge Y fill excludes edge endpoint");
	expect_pixel(60, 65, false, "two-edge Y fill exterior");

	// Chaining is axis-independent.  This is the same two-pair diamond with
	// X/Y roles exchanged, ensuring both retained endpoints advance in Y-fill.
	m_dc323->bitmap_clear();
	reg_w(dc323_device::REG_DESTINATION_X, 100);
	reg_w(dc323_device::REG_DESTINATION_Y, 100);
	reg_w(dc323_device::REG_SOURCE_Y, 100);
	reg_w(dc323_device::REG_DESTINATION_SLOW_DX, 4);
	reg_w(dc323_device::REG_HEIGHT, 0x3ffc); // -4
	reg_w(dc323_device::REG_SOURCE_FAST_DX, 4);
	reg_w(dc323_device::REG_SOURCE_SLOW_DY, 4);
	reg_w(dc323_device::REG_COMMAND, 0x06c0);
	reg_w(dc323_device::REG_DESTINATION_SLOW_DX, 4);
	reg_w(dc323_device::REG_HEIGHT, 4);
	reg_w(dc323_device::REG_SOURCE_FAST_DX, 4);
	reg_w(dc323_device::REG_SOURCE_SLOW_DY, 0x3ffc); // -4
	reg_w(dc323_device::REG_COMMAND, 0x06c0);
	for (unsigned y = 96; y <= 104; y++)
		expect_pixel(104, y, true, "chained Y fill begins at prior endpoints");
	for (unsigned y = 99; y <= 101; y++)
		expect_pixel(107, y, true, "chained Y fill converging edge pair");
	expect_pixel(104, 95, false, "chained Y fill upper exterior");
	expect_pixel(104, 105, false, "chained Y fill lower exterior");
	expect_pixel(108, 100, false, "chained Y fill excludes final endpoint");

	// Baseline X fill locks edge B to the source X origin.  The source delta
	// still identifies the scan duration but does not move the baseline.
	m_dc323->bitmap_clear();
	reg_w(dc323_device::REG_X_CONTROL, 0x008b);
	reg_w(dc323_device::REG_DESTINATION_X, 70);
	reg_w(dc323_device::REG_DESTINATION_Y, 70);
	reg_w(dc323_device::REG_SOURCE_X, 76);
	reg_w(dc323_device::REG_DESTINATION_SLOW_DX, 2);
	reg_w(dc323_device::REG_HEIGHT, 4);
	reg_w(dc323_device::REG_SOURCE_FAST_DX, 0);
	reg_w(dc323_device::REG_SOURCE_SLOW_DY, 4);
	reg_w(dc323_device::REG_COMMAND, 0x06c0);
	for (unsigned x = 70; x <= 76; x++)
		expect_pixel(x, 70, true, "baseline X fill first scan");
	for (unsigned x = 71; x <= 76; x++)
		expect_pixel(x, 71, true, "baseline X fill sloped scan");
	expect_pixel(70, 71, false, "baseline X fill follows edge A");

	// Baseline Y fill uses the source Y origin as its fixed horizontal edge.
	m_dc323->bitmap_clear();
	reg_w(dc323_device::REG_X_CONTROL, 0x008f);
	reg_w(dc323_device::REG_DESTINATION_X, 80);
	reg_w(dc323_device::REG_DESTINATION_Y, 80);
	reg_w(dc323_device::REG_SOURCE_Y, 86);
	reg_w(dc323_device::REG_DESTINATION_SLOW_DX, 4);
	reg_w(dc323_device::REG_HEIGHT, 2);
	reg_w(dc323_device::REG_SOURCE_FAST_DX, 4);
	reg_w(dc323_device::REG_SOURCE_SLOW_DY, 0);
	reg_w(dc323_device::REG_COMMAND, 0x06c0);
	for (unsigned y = 80; y <= 86; y++)
		expect_pixel(80, y, true, "baseline Y fill first scan");
	for (unsigned y = 81; y <= 86; y++)
		expect_pixel(81, y, true, "baseline Y fill sloped scan");
	expect_pixel(81, 80, false, "baseline Y fill follows edge A");

	// The independent fast and slow Bresenham paths can leave holes inside a
	// broad rotated constant-source parallelogram.  Mode bit 4 requests the
	// Adder's hole-filling scan modification.
	m_dc323->bitmap_clear();
	reg_w(dc323_device::REG_X_CONTROL, 0x0080);
	reg_w(dc323_device::REG_DESTINATION_X, 100);
	reg_w(dc323_device::REG_DESTINATION_Y, 100);
	reg_w(dc323_device::REG_WIDTH, 4);
	reg_w(dc323_device::REG_DESTINATION_FAST_DY, 2);
	reg_w(dc323_device::REG_DESTINATION_SLOW_DX, 0x3ffe); // -2
	reg_w(dc323_device::REG_HEIGHT, 4);
	reg_w(dc323_device::REG_COMMAND, 0x06c0);
	expect_pixel(100, 101, false, "rotated broad vector exposes hole when disabled");
	m_dc323->bitmap_clear();
	reg_w(dc323_device::REG_X_CONTROL, 0x0090);
	reg_w(dc323_device::REG_COMMAND, 0x06c0);
	expect_pixel(100, 101, true, "hole fill repairs first interior gap");
	expect_pixel(102, 102, true, "hole fill repairs second interior gap");

	// Linear-pattern mode uses the same destination vector generators.  This
	// rotated 1x4 operation is the form used for ReGIS grid lines.
	m_dc323->bitmap_clear();
	fill(0, 100, 1, 1, true);
	reg_w(dc323_device::REG_SOURCE_X, 0);
	reg_w(dc323_device::REG_SOURCE_Y, 100);
	reg_w(dc323_device::REG_SOURCE_FAST_DX, 1);
	reg_w(dc323_device::REG_SOURCE_SLOW_DY, 1);
	reg_w(dc323_device::REG_DESTINATION_X, 40);
	reg_w(dc323_device::REG_DESTINATION_Y, 40);
	reg_w(dc323_device::REG_WIDTH, 0);
	reg_w(dc323_device::REG_DESTINATION_FAST_DY, 1);
	reg_w(dc323_device::REG_DESTINATION_SLOW_DX, 4);
	reg_w(dc323_device::REG_HEIGHT, 0);
	reg_w(dc323_device::REG_X_CONTROL, 0x0082);
	reg_w(dc323_device::REG_COMMAND, 0x0ec0);
	for (unsigned x = 40; x < 44; x++)
		expect_pixel(x, 40, true, "rotated linear-pattern destination");
	reg_w(dc323_device::REG_DESTINATION_FAST_DY, 0);
	reg_w(dc323_device::REG_DESTINATION_SLOW_DX, 0);
	reg_w(dc323_device::REG_X_CONTROL, 0x0080);

	// Bitmap-to-processor transfers use bit zero as the leftmost pixel and
	// source data from the Viper whose active CSR enables I/D bus output.
	m_dc323->bitmap_clear();
	m_dc323->viper_select_w(0x04);
	viper_w(0x04, 0x00ca);
	fill(0, 8, 4, 1, true);
	viper_w(0x10, 0x0010);
	reg_w(dc323_device::REG_SOURCE_X, 0);
	reg_w(dc323_device::REG_SOURCE_Y, 8);
	reg_w(dc323_device::REG_WIDTH, 8);
	reg_w(dc323_device::REG_HEIGHT, 1);
	reg_w(dc323_device::REG_COMMAND, 0x0b00);
	require(m_dc323->read(dc323_device::REG_ID_DATA) == 0x0f, "bitmap-to-processor packing");
	for (unsigned plane = 0; plane < dc323_device::BITMAP_PLANES; plane++)
		require(bool(m_dc323->pixel_r(plane, 0, 8)) == (plane == 2),
			"bitmap-to-processor source plane setup");
	require(m_dc323->status_r() & dc323_device::STATUS_ADDRESS_COMPLETE, "transfer completion status");
	reg_w(dc323_device::REG_STATUS, 0x0000);
	m_dc323->viper_select_w(0x0f);

	// Configure the retained Viper scroll backend for a four-pixel region.
	viper_w(0x01, 0x0000);
	viper_w(0x0b, 0x0000);
	viper_w(0x0c, 0x0000);
	viper_w(0x0d, 0xffff);
	reg_w(dc323_device::REG_SCROLL_X_MIN, 0);
	reg_w(dc323_device::REG_SCROLL_X_MAX, 4);
	reg_w(dc323_device::REG_SCROLL_Y_OFFSET, 0);

	// Upward one-line scroll executes only on the next frame.
	m_dc323->bitmap_clear();
	fill(0, 10, 4, 1, true);
	fill(0, 11, 4, 1, false);
	fill(0, 12, 4, 1, true);
	reg_w(dc323_device::REG_SCROLL_Y_MIN, 10);
	reg_w(dc323_device::REG_SCROLL_Y_MAX, 13);
	reg_w(dc323_device::REG_SCROLL_Y, 1);
	require(m_dc323->scroll_pending(), "scroll scheduled");
	expect_pixel(0, 10, true, "scroll deferred until frame");
	m_dc323->frame_event();
	require(!m_dc323->scroll_pending(), "scroll consumed at frame");
	expect_pixel(0, 10, false, "up scroll first row");
	expect_pixel(0, 11, true, "up scroll copied row");
	expect_pixel(0, 12, false, "up scroll fill row");
	reg_w(dc323_device::REG_STATUS, 0x0000);

	// Unaligned logical edges are represented by aligned Adder words plus
	// Viper masks.  Only x=2..5 moves; pixels outside remain untouched.
	m_dc323->bitmap_clear();
	fill(0, 40, 8, 1, true);
	fill(0, 41, 8, 1, false);
	viper_w(0x0c, 0x0003);
	viper_w(0x0d, 0x000c);
	reg_w(dc323_device::REG_SCROLL_X_MIN, 2);
	reg_w(dc323_device::REG_SCROLL_X_MAX, 6);
	reg_w(dc323_device::REG_SCROLL_Y_MIN, 40);
	reg_w(dc323_device::REG_SCROLL_Y_MAX, 42);
	reg_w(dc323_device::REG_SCROLL_Y, 1);
	m_dc323->frame_event();
	expect_pixel(0, 40, true, "left scroll mask preservation");
	expect_pixel(1, 40, true, "left scroll edge preservation");
	expect_pixel(2, 40, false, "unaligned scroll first pixel");
	expect_pixel(5, 40, false, "unaligned scroll last pixel");
	expect_pixel(6, 40, true, "right scroll edge preservation");
	expect_pixel(7, 40, true, "right scroll mask preservation");
	reg_w(dc323_device::REG_STATUS, 0x0000);
	viper_w(0x0c, 0x0000);
	viper_w(0x0d, 0xffff);
	reg_w(dc323_device::REG_SCROLL_X_MIN, 0);
	reg_w(dc323_device::REG_SCROLL_X_MAX, 4);

	// Downward scroll, zero distance, saturated distance, and erase mode.
	m_dc323->bitmap_clear();
	fill(0, 20, 4, 1, true);
	reg_w(dc323_device::REG_SCROLL_Y_MIN, 20);
	reg_w(dc323_device::REG_SCROLL_Y_MAX, 23);
	reg_w(dc323_device::REG_SCROLL_Y, 0x1001);
	m_dc323->frame_event();
	expect_pixel(0, 20, false, "down scroll fill row");
	expect_pixel(0, 21, true, "down scroll copied row");
	reg_w(dc323_device::REG_STATUS, 0x0000);
	reg_w(dc323_device::REG_SCROLL_Y, 0x0000);
	m_dc323->frame_event();
	expect_pixel(0, 21, true, "zero-distance scroll preservation");
	reg_w(dc323_device::REG_STATUS, 0x0000);
	reg_w(dc323_device::REG_SCROLL_Y, 0x0fff);
	m_dc323->frame_event();
	for (unsigned y = 20; y < 23; y++)
		expect_pixel(0, y, false, "saturated scroll fills region");
	reg_w(dc323_device::REG_STATUS, 0x0000);

	// The terminal's normal character cell is twenty scanlines high.
	m_dc323->bitmap_clear();
	fill(0, 120, 4, 1, true);
	reg_w(dc323_device::REG_SCROLL_Y_MIN, 100);
	reg_w(dc323_device::REG_SCROLL_Y_MAX, 140);
	reg_w(dc323_device::REG_SCROLL_Y, 20);
	m_dc323->frame_event();
	expect_pixel(0, 100, true, "character-height scroll copy");
	expect_pixel(0, 120, false, "character-height scroll fill");
	reg_w(dc323_device::REG_STATUS, 0x0000);

	reg_w(dc323_device::REG_SCROLL_Y_MIN, 20);
	reg_w(dc323_device::REG_SCROLL_Y_MAX, 23);
	viper_w(0x0b, 0xffff);
	reg_w(dc323_device::REG_SCROLL_Y, 0x2000);
	m_dc323->frame_event();
	for (unsigned y = 20; y < 23; y++)
		expect_pixel(0, y, true, "erase mode fill");
	reg_w(dc323_device::REG_STATUS, 0x0000);

	// Y-offset wrapping and repeated writes preserve the single pending slot;
	// the last command is the one serviced at the frame.
	viper_w(0x0b, 0x0000);
	m_dc323->bitmap_clear();
	fill(0, 0, 4, 1, true);
	reg_w(dc323_device::REG_SCROLL_Y_MIN, 0);
	reg_w(dc323_device::REG_SCROLL_Y_MAX, 2);
	reg_w(dc323_device::REG_SCROLL_Y_OFFSET, 2047);
	reg_w(dc323_device::REG_SCROLL_Y, 1);
	m_dc323->frame_event();
	expect_pixel(0, 2047, true, "Y-offset wrapped source row");
	expect_pixel(0, 0, false, "Y-offset wrapped fill row");
	reg_w(dc323_device::REG_STATUS, 0x0000);

	reg_w(dc323_device::REG_SCROLL_Y_OFFSET, 0);
	m_dc323->bitmap_clear();
	fill(0, 31, 4, 1, true);
	reg_w(dc323_device::REG_SCROLL_Y_MIN, 30);
	reg_w(dc323_device::REG_SCROLL_Y_MAX, 34);
	reg_w(dc323_device::REG_SCROLL_Y, 1);
	reg_w(dc323_device::REG_SCROLL_Y, 2);
	m_dc323->frame_event();
	expect_pixel(0, 30, false, "repeated scroll uses last distance row zero");
	expect_pixel(0, 31, false, "repeated scroll uses last distance row one");
	reg_w(dc323_device::REG_STATUS, 0x0000);

	// Repeated frame/acknowledgement cycles must neither lose nor stick IRQ.
	for (unsigned frame = 0; frame < 1000; frame++)
	{
		m_dc323->frame_event();
		require(m_irq, "repeated frame IRQ assertion");
		reg_w(dc323_device::REG_STATUS, 0x0000);
		require(!m_irq, "repeated frame IRQ acknowledgement");
	}

	osd_printf_info("DC323 firmware-free device regression passed\n");
	machine().schedule_exit();
}


void dc323_test_state::dc323test(machine_config &config)
{
	DC323(config, m_dc323, 0);
	m_dc323->set_chargen_tag("^chargen");
	m_dc323->irq_handler().set(FUNC(dc323_test_state::irq_w));
}


static INPUT_PORTS_START(dc323test)
INPUT_PORTS_END

ROM_START(dc323test)
	ROM_REGION(0x8000, "chargen", ROMREGION_ERASE00)
ROM_END

} // anonymous namespace


COMP(2026, dc323test, 0, 0, dc323test, dc323test, dc323_test_state, empty_init, "MAME", "DEC DC323 device regression", MACHINE_NO_SOUND_HW)
