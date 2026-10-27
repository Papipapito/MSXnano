#ifndef SDK_STUB_H
#define SDK_STUB_H

/*
 * Lo minimo de TinyUSB y del Pico SDK que necesita usbin.c para compilar en el
 * PC. Los valores de las constantes HID son los de class/hid/hid.h de TinyUSB
 * (los descriptores de prueba son bytes HID reales, asi que un valor equivocado
 * haria fallar el parseo, no pasaria en silencio).
 */

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#define CFG_TUH_HID 16
#define TU_ATTR_PACKED __attribute__((packed))
#define TU_ATTR_WEAK   __attribute__((weak))
#define tu_memclr(buffer, size) memset((buffer), 0, (size))

typedef struct { uint8_t bLength; uint8_t bDescriptorType; } tusb_desc_device_t;

typedef enum {
  HID_ITF_PROTOCOL_NONE     = 0,
  HID_ITF_PROTOCOL_KEYBOARD = 1,
  HID_ITF_PROTOCOL_MOUSE    = 2
} hid_interface_protocol_enum_t;

enum { HID_PROTOCOL_BOOT = 0, HID_PROTOCOL_REPORT = 1 };
enum { HID_REPORT_TYPE_INVALID = 0, HID_REPORT_TYPE_INPUT, HID_REPORT_TYPE_OUTPUT, HID_REPORT_TYPE_FEATURE };

enum { RI_TYPE_MAIN = 0, RI_TYPE_GLOBAL = 1, RI_TYPE_LOCAL = 2 };
enum {
  RI_MAIN_INPUT = 8, RI_MAIN_OUTPUT = 9, RI_MAIN_COLLECTION = 10,
  RI_MAIN_FEATURE = 11, RI_MAIN_COLLECTION_END = 12
};
enum {
  RI_GLOBAL_USAGE_PAGE = 0, RI_GLOBAL_LOGICAL_MIN = 1, RI_GLOBAL_LOGICAL_MAX = 2,
  RI_GLOBAL_PHYSICAL_MIN = 3, RI_GLOBAL_PHYSICAL_MAX = 4, RI_GLOBAL_UNIT_EXPONENT = 5,
  RI_GLOBAL_UNIT = 6, RI_GLOBAL_REPORT_SIZE = 7, RI_GLOBAL_REPORT_ID = 8,
  RI_GLOBAL_REPORT_COUNT = 9
};
enum { RI_LOCAL_USAGE = 0 };

enum {
  HID_USAGE_PAGE_DESKTOP  = 0x01,
  HID_USAGE_PAGE_KEYBOARD = 0x07,
  HID_USAGE_PAGE_BUTTON   = 0x09
};
enum {
  HID_USAGE_DESKTOP_JOYSTICK   = 0x04,
  HID_USAGE_DESKTOP_GAMEPAD    = 0x05,
  HID_USAGE_DESKTOP_KEYBOARD   = 0x06,
  HID_USAGE_DESKTOP_X          = 0x30,
  HID_USAGE_DESKTOP_Y          = 0x31,
  HID_USAGE_DESKTOP_HAT_SWITCH = 0x39
};

// Igual que en TinyUSB: 4 bytes (usbin.c lo usa en un sizeof, aunque su tabla sea mas grande).
typedef struct {
  uint8_t  report_id;
  uint8_t  usage;
  uint16_t usage_page;
} tuh_hid_report_info_t;

bool    tuh_hid_receive_report(uint8_t dev_addr, uint8_t instance);
uint8_t tuh_hid_interface_protocol(uint8_t dev_addr, uint8_t instance);
uint8_t tuh_hid_get_protocol(uint8_t dev_addr, uint8_t instance);
bool    tuh_hid_set_protocol(uint8_t dev_addr, uint8_t instance, uint8_t protocol);
bool    tuh_hid_set_report(uint8_t dev_addr, uint8_t idx, uint8_t report_id, uint8_t report_type, void* report, uint16_t len);
bool    tuh_vid_pid_get(uint8_t dev_addr, uint16_t* vid, uint16_t* pid);
void    board_led_write(bool state);

#endif
