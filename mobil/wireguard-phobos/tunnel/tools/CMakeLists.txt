# SPDX-License-Identifier: Apache-2.0
#
# Copyright © 2017-2025 WireGuard LLC. All Rights Reserved.

cmake_minimum_required(VERSION 3.4.1)
project("WireGuard")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}")
add_link_options(LINKER:--build-id=none)
add_compile_options(-Wall -Werror)

add_executable(libwg-quick.so wireguard-tools/src/wg-quick/android.c ndk-compat/compat.c)
target_compile_options(libwg-quick.so PUBLIC -std=gnu11 -include ${CMAKE_CURRENT_SOURCE_DIR}/ndk-compat/compat.h -DWG_PACKAGE_NAME=\"${ANDROID_PACKAGE_NAME}\")
target_link_libraries(libwg-quick.so -ldl)

file(GLOB WG_SOURCES wireguard-tools/src/*.c ndk-compat/compat.c)
add_executable(libwg.so ${WG_SOURCES})
target_include_directories(libwg.so PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/wireguard-tools/src/uapi/linux/" "${CMAKE_CURRENT_SOURCE_DIR}/wireguard-tools/src/")
target_compile_options(libwg.so PUBLIC -std=gnu11 -include ${CMAKE_CURRENT_SOURCE_DIR}/ndk-compat/compat.h -DRUNSTATEDIR=\"/data/data/${ANDROID_PACKAGE_NAME}/cache\")

add_custom_target(libwg-go.so WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/libwg-go" COMMENT "Building wireguard-go" VERBATIM COMMAND "${ANDROID_HOST_PREBUILTS}/bin/make"
    ANDROID_ARCH_NAME=${ANDROID_ARCH_NAME}
    ANDROID_PACKAGE_NAME=${ANDROID_PACKAGE_NAME}
    GRADLE_USER_HOME=${GRADLE_USER_HOME}
    CC=${CMAKE_C_COMPILER}
    CFLAGS=${CMAKE_C_FLAGS}
    LDFLAGS=${CMAKE_SHARED_LINKER_FLAGS}
    SYSROOT=${CMAKE_SYSROOT}
    TARGET=${CMAKE_C_COMPILER_TARGET}
    DESTDIR=${CMAKE_LIBRARY_OUTPUT_DIRECTORY}
    BUILDDIR=${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/../generated-src
)

# Strip unwanted ELF sections to prevent DT_FLAGS_1 warnings on old Android versions
file(GLOB ELF_CLEANER_SOURCES elf-cleaner/*.c elf-cleaner/*.cpp)
add_custom_target(elf-cleaner COMMENT "Building elf-cleaner" VERBATIM COMMAND cc
        -O2 -DPACKAGE_NAME="elf-cleaner" -DPACKAGE_VERSION="" -DCOPYRIGHT=""
        -o "${CMAKE_CURRENT_BINARY_DIR}/elf-cleaner" ${ELF_CLEANER_SOURCES}
)
add_custom_command(TARGET libwg.so POST_BUILD VERBATIM COMMAND "${CMAKE_CURRENT_BINARY_DIR}/elf-cleaner"
        --api-level "${ANDROID_NATIVE_API_LEVEL}" "$<TARGET_FILE:libwg.so>")
add_dependencies(libwg.so elf-cleaner)
add_custom_command(TARGET libwg-quick.so POST_BUILD VERBATIM COMMAND "${CMAKE_CURRENT_BINARY_DIR}/elf-cleaner"
        --api-level "${ANDROID_NATIVE_API_LEVEL}" "$<TARGET_FILE:libwg-quick.so>")
add_dependencies(libwg-quick.so elf-cleaner)

set(WG_OBFUSCATOR_JNI "${CMAKE_CURRENT_SOURCE_DIR}/../src/main/jni/wg-obfuscator")
set(WG_OBFUSCATOR_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../../../../src/phobos-obfuscator")
add_library(libwg-obfuscator.so SHARED
    "${WG_OBFUSCATOR_JNI}/wg-obfuscator-jni.c"
    "${WG_OBFUSCATOR_JNI}/wg-obfuscator-socks5-jni.c"
    "${WG_OBFUSCATOR_SRC}/socks5.c"
    "${WG_OBFUSCATOR_SRC}/socks5_proto.c"
    "${WG_OBFUSCATOR_SRC}/socks5_mask.c"
    "${WG_OBFUSCATOR_SRC}/masking.c"
    "${WG_OBFUSCATOR_SRC}/masking_media.c"
    "${WG_OBFUSCATOR_SRC}/masking_stun.c"
    "${WG_OBFUSCATOR_SRC}/resolve.c"
    "${WG_OBFUSCATOR_SRC}/runtime.c")
set_target_properties(libwg-obfuscator.so PROPERTIES PREFIX "" SUFFIX "")
target_include_directories(libwg-obfuscator.so PRIVATE "${WG_OBFUSCATOR_SRC}")
target_compile_options(libwg-obfuscator.so PRIVATE -std=gnu11 -O3 -Wno-error)

set(HEV_DIR "${CMAKE_CURRENT_SOURCE_DIR}/hev-socks5-tunnel")
add_custom_target(libhev-socks5-tunnel.so ALL
    WORKING_DIRECTORY "${HEV_DIR}"
    COMMENT "Building hev-socks5-tunnel"
    VERBATIM
    COMMAND "${CMAKE_ANDROID_NDK}/ndk-build"
        "NDK_PROJECT_PATH=null"
        "APP_BUILD_SCRIPT=${HEV_DIR}/Android.mk"
        "NDK_APPLICATION_MK=${HEV_DIR}/Application.mk"
        "APP_ABI=${ANDROID_ABI}"
        "APP_PLATFORM=${ANDROID_PLATFORM}"
        "APP_MODULES=hev-socks5-tunnel"
        "APP_CFLAGS=-O3 -DPKGNAME=com/wireguard/android/backend/tun2socks"
        "NDK_OUT=${CMAKE_CURRENT_BINARY_DIR}/hev-obj"
        "NDK_LIBS_OUT=${CMAKE_CURRENT_BINARY_DIR}/hev-libs"
        "-j4"
    COMMAND "${CMAKE_COMMAND}" -E copy
        "${CMAKE_CURRENT_BINARY_DIR}/hev-libs/${ANDROID_ABI}/libhev-socks5-tunnel.so"
        "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/libhev-socks5-tunnel.so"
)
