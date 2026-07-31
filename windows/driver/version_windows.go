/* SPDX-License-Identifier: MIT
 *
 * Copyright (C) 2017-2026 WireGuard LLC. All Rights Reserved.
 */

package driver

import (
	"fmt"
	"unsafe"

	"golang.org/x/sys/windows"
)

// Version returns the version of the driver DLL.
func Version() string {
	if modwireguard.Load() != nil {
		return "unknown"
	}
	resInfo, err := windows.FindResource(modwireguard.Base, windows.ResourceID(1), windows.RT_VERSION)
	if err != nil {
		return "unknown"
	}
	data, err := windows.LoadResourceData(modwireguard.Base, resInfo)
	if err != nil {
		return "unknown"
	}

	var fixedInfo *windows.VS_FIXEDFILEINFO
	fixedInfoLen := uint32(unsafe.Sizeof(*fixedInfo))
	err = windows.VerQueryValue(unsafe.Pointer(&data[0]), `\`, unsafe.Pointer(&fixedInfo), &fixedInfoLen)
	if err != nil {
		return "unknown"
	}
	version := fmt.Sprintf("%d.%d", (fixedInfo.FileVersionMS>>16)&0xff, (fixedInfo.FileVersionMS>>0)&0xff)
	if nextNibble := (fixedInfo.FileVersionLS >> 16) & 0xff; nextNibble != 0 {
		version += fmt.Sprintf(".%d", nextNibble)
	}
	if nextNibble := (fixedInfo.FileVersionLS >> 0) & 0xff; nextNibble != 0 {
		version += fmt.Sprintf(".%d", nextNibble)
	}
	return version
}
