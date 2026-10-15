cmake_minimum_required(VERSION 3.17)

include(src/pico_sdk_import.cmake)

project(goauld_friend C CXX ASM)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O3")

# ---- Variantes -------------------------------------------------------------
# Clasica (por defecto): Zero/Pico con su propio USB-C como host (y hub), TinyUSB del SDK.
# Portadora MSXnano v2 (-DMSXNANO_CARRIER=ON): Zero en el zocalo de la portadora; el USB-C deja
#   de ser host y el host USB sale por Pico-PIO-USB con tres puertos raiz (J1 GP26/27, J2 GP28/29,
#   J5 GP0/1), con TinyUSB y Pico-PIO-USB de los submodulos de lib/.
# Depuracion (-DMSXNANO_DEBUG_CDC=ON, solo portadora): el USB-C es un dispositivo CDC con el
#   registro de dbg_printf().
option(MSXNANO_CARRIER   "Firmware de la portadora MSXnano v2 (host USB por Pico-PIO-USB)" OFF)
option(MSXNANO_DEBUG_CDC "Portadora: USB-C como dispositivo CDC de depuracion (dbg_printf)" OFF)
if(MSXNANO_DEBUG_CDC AND NOT MSXNANO_CARRIER)
    message(FATAL_ERROR "MSXNANO_DEBUG_CDC solo tiene sentido con MSXNANO_CARRIER=ON: en la variante clasica el USB-C es el host")
endif()

if(MSXNANO_CARRIER)
    # PICO_TINYUSB_PATH y PICO_PIO_USB_PATH se leen cuando pico_sdk_init() procesa
    # src/rp2_common/tinyusb: tienen que estar fijados ANTES. Pico-PIO-USB va en una copia del
    # directorio de build con PIO_USB_ROOT_PORT_CNT = 3 (ver cmake/stage_pio_usb.cmake).
    set(MSXNANO_TINYUSB_DIR ${CMAKE_CURRENT_LIST_DIR}/lib/tinyusb)
    set(MSXNANO_PIO_USB_DIR ${CMAKE_CURRENT_LIST_DIR}/lib/Pico-PIO-USB)
    if(NOT EXISTS ${MSXNANO_TINYUSB_DIR}/hw/bsp/rp2040)
        message(FATAL_ERROR "Falta lib/tinyusb: ejecuta 'git submodule update --init fpga/rp2040/lib/tinyusb'")
    endif()
    include(cmake/stage_pio_usb.cmake)
    msxnano_stage_pio_usb(${MSXNANO_PIO_USB_DIR} ${CMAKE_BINARY_DIR}/Pico-PIO-USB 3)
    set(PICO_TINYUSB_PATH ${MSXNANO_TINYUSB_DIR})
    set(PICO_PIO_USB_PATH ${CMAKE_BINARY_DIR}/Pico-PIO-USB)
endif()

pico_sdk_init()

set(FAMILY rp2040)

if(MSXNANO_CARRIER)
    # family.cmake de TinyUSB crea tinyusb_pico_pio_usb al cargarse; si la funcion
    # pico_generate_pio_header aun no existia en ese momento, se crea ahora.
    if(NOT TARGET tinyusb_pico_pio_usb AND COMMAND check_and_add_pico_pio_usb_support)
        check_and_add_pico_pio_usb_support()
    endif()
    if(NOT TARGET tinyusb_pico_pio_usb)
        message(FATAL_ERROR "TinyUSB no ha creado tinyusb_pico_pio_usb (PICO_PIO_USB_PATH=${PICO_PIO_USB_PATH})")
    endif()
endif()

add_executable(goauld_friend
    src/main.c
    src/usbin.c
    src/xinput_host.c
)
if(MSXNANO_DEBUG_CDC)
    target_sources(goauld_friend PRIVATE
        src/dbg_log.c
        src/usb_descriptors.c
    )
endif()

# Generate the WS2812 (status LED) PIO header for the RP2040-Zero on-board NeoPixel.
pico_generate_pio_header(goauld_friend ${CMAKE_CURRENT_LIST_DIR}/ws2812.pio)
# Generate the PIO UART TX header (FPGA link on GP15, a non-hardware-UART pin).
pico_generate_pio_header(goauld_friend ${CMAKE_CURRENT_LIST_DIR}/uart_tx.pio)

target_include_directories(goauld_friend PRIVATE
    ${CMAKE_CURRENT_LIST_DIR}/inc
    ${CMAKE_CURRENT_LIST_DIR}/src
    ${PICO_SDK_PATH}/src
)

target_link_libraries(goauld_friend
    pico_stdlib
    hardware_uart
    hardware_gpio
    hardware_pio
    tinyusb_host
    tinyusb_board
    pico_multicore
)
if(MSXNANO_CARRIER)
    target_link_libraries(goauld_friend
        hardware_dma
        tinyusb_pico_pio_usb
    )
    # El BSP de TinyUSB (family.c) exige un pin D+ por defecto cuando el host es PIO-USB; main.c
    # no llama a board_init() y configura PIO-USB el mismo (J1 = GP26).
    target_compile_definitions(goauld_friend PRIVATE PICO_DEFAULT_PIO_USB_DP_PIN=26)
    # Pila del nucleo 0 de 4 KB en vez de 2 (todo SCRATCH_Y, que esta vacio): las transferencias de
    # PIO-USB corren dentro de una IRQ de 1 ms que se apila encima de tuh_task() y los callbacks.
    target_compile_definitions(goauld_friend PRIVATE PICO_STACK_SIZE=0x1000)
    if(MSXNANO_DEBUG_CDC)
        target_link_libraries(goauld_friend tinyusb_device)
    endif()
endif()

# The keyboard link OWNS uart0 (GPIO0 = TX). Keep stdio OFF the UART so it
# never claims GPIO0/uart0 and corrupts the keyboard stream.
#
# NOTE: the RP2040's single USB controller is already in HOST mode for the
# keyboard (CFG_TUSB_RHPORT0_MODE = OPT_MODE_HOST), so it CANNOT also run a
# USB-CDC device for stdio. We therefore disable stdio entirely; DEBUG printf
# becomes a harmless no-op. (If you need a debug console, wire a 2nd UART,
# e.g. uart1 on GPIO8, and call pico_enable_stdio_uart with that instead.)
# En la portadora el USB-C no es host (el host es PIO-USB), pero stdio USB de
# pico_stdio_usb tampoco se usa: choca con nuestro tusb_config.h. El registro de
# depuracion es dbg_printf() sobre un CDC propio (MSXNANO_DEBUG_CDC).
pico_enable_stdio_uart(goauld_friend 0)
pico_enable_stdio_usb(goauld_friend 0)

if(CMAKE_BUILD_TYPE MATCHES Debug)
    set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -Og")
    target_compile_definitions(goauld_friend PRIVATE DEBUG)
else()
    set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -O3")
endif()

# Board select: default = Waveshare RP2040-Zero (LED on GPIO16).
# Pass -DRP2040_ZERO=0 to target a Raspberry Pi Pico (LED on GPIO25).
if(NOT DEFINED RP2040_ZERO)
    set(RP2040_ZERO 1)
endif()

if(MSXNANO_CARRIER)
    set(MSXNANO_CARRIER_VALUE 1)
else()
    set(MSXNANO_CARRIER_VALUE 0)
endif()
if(MSXNANO_DEBUG_CDC)
    set(MSXNANO_DEBUG_CDC_VALUE 1)
else()
    set(MSXNANO_DEBUG_CDC_VALUE 0)
endif()

target_compile_definitions(goauld_friend PRIVATE
    CFG_TUSB_MCU=OPT_MCU_RP2040
    PICO_PLATFORM=rp2040
    RP2040_ZERO=${RP2040_ZERO}
    DEBUG_BAUDRATE=115200
    MSXNANO_CARRIER=${MSXNANO_CARRIER_VALUE}
    MSXNANO_DEBUG_CDC=${MSXNANO_DEBUG_CDC_VALUE}
)

pico_add_extra_outputs(goauld_friend)
