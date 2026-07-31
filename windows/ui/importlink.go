//go:build windows

/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package ui

import (
	"os"
	"runtime"
	"time"
	"unsafe"

	"github.com/lxn/win"
	"golang.org/x/sys/windows"

	"golang.zx2c4.com/wireguard/windows/l18n"
)

const importLinkMessageID = 0x50484f42

type copyDataStruct struct {
	data uintptr
	size uint32
	ptr  unsafe.Pointer
}

func sendImportLinkTo(hwnd win.HWND, link string) bool {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	utf16, err := windows.UTF16FromString(link)
	if err != nil {
		return false
	}
	payload := copyDataStruct{
		data: importLinkMessageID,
		size: uint32(len(utf16) * 2),
		ptr:  unsafe.Pointer(&utf16[0]),
	}
	delivered := win.SendMessage(hwnd, win.WM_COPYDATA, 0, uintptr(unsafe.Pointer(&payload))) != 0
	runtime.KeepAlive(utf16)
	if delivered {
		raiseRemote(hwnd)
	}
	return delivered
}

// SendImportLink hands a phobos:// link to an already running Phobos window.
func SendImportLink(link string) bool {
	hwnd := win.FindWindow(windows.StringToUTF16Ptr(manageWindowWindowClass), nil)
	if hwnd == 0 {
		return false
	}
	return sendImportLinkTo(hwnd, link)
}

// WaitForUIThenImportLink blocks until the Phobos window shows up, hands it the
// link and quits. It gives up after the timeout so a stuck launch cannot leave
// the process behind.
func WaitForUIThenImportLink(link string, timeout time.Duration) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if SendImportLink(link) {
			os.Exit(0)
		}
		time.Sleep(250 * time.Millisecond)
	}
	showErrorCustom(nil, l18n.Sprintf("Phobos Detection Error"), l18n.Sprintf("Phobos did not start in time to import the link."))
	os.Exit(1)
}

func (mtw *ManageTunnelsWindow) onImportLinkMessage(lParam uintptr) uintptr {
	payload := (*copyDataStruct)(unsafe.Pointer(lParam))
	if payload == nil || payload.data != importLinkMessageID || payload.size == 0 {
		return 0
	}
	link := windows.UTF16ToString(unsafe.Slice((*uint16)(payload.ptr), payload.size/2))
	mtw.Synchronize(func() {
		if mtw.tunnelsPage == nil {
			return
		}
		if mtw.tabs != nil {
			mtw.tabs.SetCurrentIndex(0)
		}
		mtw.tunnelsPage.importLink(link)
	})
	return 1
}
