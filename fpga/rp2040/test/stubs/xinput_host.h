#ifndef XINPUT_HOST_STUB_H
#define XINPUT_HOST_STUB_H

/* Parte de inc/xinput_host.h que usa usbin.c (valores y campos iguales). */

#include "sdk_stub.h"

#define XINPUT_GAMEPAD_DPAD_UP    0x0001
#define XINPUT_GAMEPAD_DPAD_DOWN  0x0002
#define XINPUT_GAMEPAD_DPAD_LEFT  0x0004
#define XINPUT_GAMEPAD_DPAD_RIGHT 0x0008
#define XINPUT_GAMEPAD_A 0x1000
#define XINPUT_GAMEPAD_B 0x2000
#define XINPUT_GAMEPAD_X 0x4000
#define XINPUT_GAMEPAD_Y 0x8000

typedef struct xinput_gamepad {
    uint16_t wButtons;
    uint8_t bLeftTrigger;
    uint8_t bRightTrigger;
    int16_t sThumbLX;
    int16_t sThumbLY;
    int16_t sThumbRX;
    int16_t sThumbRY;
} xinput_gamepad_t;

typedef struct {
    xinput_gamepad_t pad;
    uint8_t connected;
    uint8_t new_pad_data;
} xinputh_interface_t;

typedef struct { int unused; } usbh_class_driver_t;
extern usbh_class_driver_t const usbh_xinput_driver;

bool tuh_xinput_receive_report(uint8_t dev_addr, uint8_t instance);
void tuh_xinput_mount_cb(uint8_t dev_addr, uint8_t instance, const xinputh_interface_t *xinput_itf);
void tuh_xinput_umount_cb(uint8_t dev_addr, uint8_t instance);
void tuh_xinput_report_received_cb(uint8_t dev_addr, uint8_t instance, xinputh_interface_t const* xid_itf, uint16_t len);

#endif
