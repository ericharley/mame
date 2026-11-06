// license:BSD-3-Clause
// copyright-holders:Nathan Woods, Miodrag Milanovic
/*********************************************************************

    bitbngr.c

*********************************************************************/

#include "emu.h"
#include "bitbngr.h"

#include "softlist_dev.h"

#include <cstring>

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
// The browser frontend owns the WebSocket; only raw serial bytes cross here.
EM_JS(void, mame_bitbanger_output, (int data), {
	if (Module.serialOutput) Module.serialOutput(data);
});
EM_JS(unsigned, mame_bitbanger_input, (void *buffer, unsigned length), {
	return Module.serialInput ? Module.serialInput(buffer, length) : 0;
});
#endif



/***************************************************************************
    IMPLEMENTATION
***************************************************************************/

DEFINE_DEVICE_TYPE(BITBANGER, bitbanger_device, "bitbanger", "Bitbanger")

/*-------------------------------------------------
    ctor
-------------------------------------------------*/

bitbanger_device::bitbanger_device(const machine_config &mconfig, const char *tag, device_t *owner, uint32_t clock) :
	device_t(mconfig, BITBANGER, tag, owner, clock),
	device_image_interface(mconfig, *this),
	m_interface(nullptr),
	m_is_readonly(false)
{
}



/*-------------------------------------------------
    native_output - outputs data to a file
-------------------------------------------------*/

void bitbanger_device::output(uint8_t data)
{
#ifdef __EMSCRIPTEN__
	if (exists() && !strcmp(basename(), "browser-serial"))
	{
		mame_bitbanger_output(data);
		return;
	}
#endif
	if (!loaded_through_softlist() && exists() && !device_image_interface::is_readonly())
		fwrite(&data, 1);
}


/*-------------------------------------------------
    native_input - inputs data from a file
-------------------------------------------------*/

uint32_t bitbanger_device::input(void *buffer, uint32_t length)
{
#ifdef __EMSCRIPTEN__
	if (exists() && !strcmp(basename(), "browser-serial"))
		return mame_bitbanger_input(buffer, length);
#endif
	if (exists())
		return fread(buffer, length);
	else
		return 0;
}



/*-------------------------------------------------
    device_start
-------------------------------------------------*/

void bitbanger_device::device_start()
{
}



/*-------------------------------------------------
    get_software_list_loader
-------------------------------------------------*/

const software_list_loader &bitbanger_device::get_software_list_loader() const
{
	return image_software_list_loader::instance();
}



/*-------------------------------------------------
    call_load
-------------------------------------------------*/

std::pair<std::error_condition, std::string> bitbanger_device::call_load()
{
	// Image hashing and a previous output attempt may leave the shared stream
	// position away from the beginning.  A newly loaded input stream starts at
	// its first byte.
	fseek(0, SEEK_SET);
	return std::make_pair(std::error_condition(), std::string());
}

std::pair<std::error_condition, std::string> bitbanger_device::call_create(int format_type, util::option_resolution *format_options)
{
	// we don't need to do anything special
	return std::make_pair(std::error_condition(), std::string());
}

/*-------------------------------------------------
    call_unload
-------------------------------------------------*/

void bitbanger_device::call_unload()
{
	// we don't need to do anything special
}
