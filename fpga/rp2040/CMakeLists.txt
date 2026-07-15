cmake_minimum_required(VERSION 3.17)

include(src/pico_sdk_import.cmake)

project(goauld_friend C CXX ASM)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O3")

pico_sdk_init()

set(FAMILY rp2040)

add_executable(goauld_friend
    src/main.c
    src/usbin.c
    src/xinput_host.c
)

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

# The keyboard link OWNS uart0 (GPIO0 = TX). Keep stdio OFF the UART so it
# never claims GPIO0/uart0 and corrupts the keyboard stream.
#
# NOTE: the RP2040's single USB controller is already in HOST mode for the
# keyboard (CFG_TUSB_RHPORT0_MODE = OPT_MODE_HOST), so it CANNOT also run a
# USB-CDC device for stdio. We therefore disable stdio entirely; DEBUG printf
# becomes a harmless no-op. (If you need a debug console, wire a 2nd UART,
# e.g. uart1 on GPIO8, and call pico_enable_stdio_uart with that instead.)
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

target_compile_definitions(goauld_friend PRIVATE
    CFG_TUSB_MCU=OPT_MCU_RP2040
    PICO_PLATFORM=rp2040
    RP2040_ZERO=${RP2040_ZERO}
    DEBUG_BAUDRATE=115200
)

pico_add_extra_outputs(goauld_friend)
