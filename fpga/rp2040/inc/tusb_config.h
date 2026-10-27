/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2019 Ha Thach (tinyusb.org)
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */

#ifndef _TUSB_CONFIG_H_
#define _TUSB_CONFIG_H_

#ifdef __cplusplus
 extern "C" {
#endif

// MSXNANO_CARRIER = 0: variante clasica (Zero/Pico, el propio USB-C hace de host, TinyUSB del SDK).
// MSXNANO_CARRIER = 1: portadora MSXnano v2 (host por Pico-PIO-USB, TinyUSB >= 0.21 de lib/tinyusb).
// MSXNANO_DEBUG_CDC = 1 (solo portadora): el USB-C de la Zero es ademas DISPOSITIVO CDC de depuracion.
#ifndef MSXNANO_CARRIER
#define MSXNANO_CARRIER   0
#endif
#ifndef MSXNANO_DEBUG_CDC
#define MSXNANO_DEBUG_CDC 0
#endif

#define CFG_TUSB_MCU          OPT_MCU_RP2040

#if MSXNANO_CARRIER
// Host en el rhport 1 = Pico-PIO-USB (el rhport 0 es el controlador nativo, que aqui solo
// puede ser dispositivo). PIO-USB cuelga de ese rhport 1 sus puertos raiz: TinyUSB los ve
// como rhport 1, 2 y 3 (J1, J2 y J5 de la portadora; ver main.c).
#define BOARD_TUH_RHPORT        1
#define CFG_TUH_ENABLED         1
#define CFG_TUH_MAX_SPEED       OPT_MODE_DEFAULT_SPEED
#define CFG_TUH_RPI_PIO_USB     1

#if MSXNANO_DEBUG_CDC
#define BOARD_TUD_RHPORT        0
#define CFG_TUD_ENABLED         1
#define CFG_TUD_MAX_SPEED       OPT_MODE_DEFAULT_SPEED
#define CFG_TUD_ENDPOINT0_SIZE  64
#define CFG_TUD_CDC             1
#define CFG_TUD_CDC_RX_BUFSIZE  64
#define CFG_TUD_CDC_TX_BUFSIZE  256
#define CFG_TUD_CDC_RX_EPSIZE   64
#define CFG_TUD_CDC_TX_EPSIZE   64
#else
#define CFG_TUD_ENABLED         0
#endif
#else
#define CFG_TUSB_RHPORT0_MODE OPT_MODE_HOST
#endif

#ifndef CFG_TUSB_OS
#define CFG_TUSB_OS           OPT_OS_PICO
#endif

#ifndef CFG_TUH_MEM_SECTION
#define CFG_TUH_MEM_SECTION
#endif

#ifndef CFG_TUH_MEM_ALIGN
#define CFG_TUH_MEM_ALIGN        __attribute__ ((aligned(4)))
#endif

#define CFG_TUH_ENUMERATION_BUFSIZE 2048  // was 256; some HID gamepads have large report descriptors

// Con TinyUSB >= 0.21 la cola de "attach" diferido solo existe con CFG_TUH_HUB >= 1 y tiene
// EXACTAMENTE CFG_TUH_HUB entradas: mientras un puerto enumera, los demas dejan ahi su attach.
// Si se llena, el attach se descarta y el puerto no vuelve a enumerar hasta apagar. Hacen
// falta >= (puertos raiz - 1): 2 con los tres de la portadora. Se deja en 2 aunque no se usen hubs.
#define CFG_TUH_HUB                 2
#if MSXNANO_CARRIER && CFG_TUH_HUB < 2
#error "CFG_TUH_HUB < 2: la cola de attach diferido no cabe para 3 puertos raiz (un 3.er dispositivo en frio no enumeraria)"
#endif
#if MSXNANO_CARRIER
#define CFG_TUH_DEVICE_MAX          8   // 3 puertos raiz + sitio para hubs
#else
#define CFG_TUH_DEVICE_MAX          6
#endif

#define CFG_TUH_HID                 16
#define CFG_TUH_XINPUT              1   // Ryzee119 XInput host driver: number of XInput pads (Xbox / dongles)
#define CFG_TUH_HID_EPIN_BUFSIZE    128 // default 64
#define CFG_TUH_HID_EPOUT_BUFSIZE   128 // default 64

#define CFG_TUSB_HOST_DEVICE_MAX    (CFG_TUH_HUB ? 5 : 1) // normal hub has 4 ports
#define CFG_TUH_CDC                 1
#define CFG_TUH_HID_KEYBOARD        1
#define CFG_TUH_HID_MOUSE           0
#define CFG_TUH_MSC                 1  // Enable Mass Storage
#define CFG_TUSB_HOST_HID_GENERIC   0  // (not yet supported)

#ifdef __cplusplus
}
#endif

#endif /* _TUSB_CONFIG_H_ */
