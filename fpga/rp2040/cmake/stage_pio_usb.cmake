# Pico-PIO-USB con tres puertos raiz.
#
# Pico-PIO-USB fija el numero de puertos raiz en pio_usb_configuration.h con un
# `#define PIO_USB_ROOT_PORT_CNT 2` sin proteger por #ifndef, asi que no se puede
# cambiar desde la linea de comandos del compilador. En vez de editar el submodulo
# (lib/Pico-PIO-USB se queda EXACTAMENTE en el commit fijado), se prepara en el
# directorio de build una copia de su src/ y se cambia solo esa linea en la copia.
# Esta es la unica modificacion: si el submodulo se actualiza y la linea cambia, el
# parche falla con un error en vez de aplicarse a medias.
#
# Uso:  msxnano_stage_pio_usb(<submodulo> <destino> <numero de puertos raiz>)
# Despues, PICO_PIO_USB_PATH = <destino> (TinyUSB lee <destino>/src/*).

function(msxnano_stage_pio_usb SRC DST ROOT_PORTS)
    if(NOT EXISTS ${SRC}/src/pio_usb.c)
        message(FATAL_ERROR "Falta ${SRC}/src/pio_usb.c: ejecuta 'git submodule update --init fpga/rp2040/lib/Pico-PIO-USB'")
    endif()

    file(GLOB _files RELATIVE ${SRC}/src ${SRC}/src/*)
    foreach(_f ${_files})
        if(_f STREQUAL "pio_usb_configuration.h")
            continue()
        endif()
        # configure_file con COPYONLY no toca el destino si el contenido es igual
        # y deja el origen como dependencia de configuracion (si cambia, se regenera).
        configure_file(${SRC}/src/${_f} ${DST}/src/${_f} COPYONLY)
    endforeach()

    set(_hdr ${SRC}/src/pio_usb_configuration.h)
    file(READ ${_hdr} _txt)
    string(REGEX MATCH "#define[ \t]+PIO_USB_ROOT_PORT_CNT[ \t]+[0-9]+" _found "${_txt}")
    if(NOT _found)
        message(FATAL_ERROR "No encuentro '#define PIO_USB_ROOT_PORT_CNT <n>' en ${_hdr}: el submodulo ha cambiado, revisa cmake/stage_pio_usb.cmake")
    endif()
    string(REGEX REPLACE "(#define[ \t]+PIO_USB_ROOT_PORT_CNT[ \t]+)[0-9]+" "\\1${ROOT_PORTS}" _new "${_txt}")

    # Solo se reescribe si cambia, para no recompilar PIO-USB en cada configure.
    set(_out ${DST}/src/pio_usb_configuration.h)
    set(_old "")
    if(EXISTS ${_out})
        file(READ ${_out} _old)
    endif()
    if(NOT _old STREQUAL _new)
        file(WRITE ${_out} "${_new}")
    endif()
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${_hdr})
endfunction()
