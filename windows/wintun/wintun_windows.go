/* SPDX-License-Identifier: MIT
 *
 * Copyright (C) 2017-2026 WireGuard LLC. All Rights Reserved.
 * Phobos
 */

package wintun

import (
	"errors"
	"runtime"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
	"golang.zx2c4.com/wireguard/windows/dllloader"
	"golang.zx2c4.com/wireguard/windows/tunnel/winipcfg"
)

const (
	RingCapacityMin = 0x20000
	RingCapacityMax = 0x4000000
	PacketSizeMax   = 0xffff
)

var (
	modwintun                         = dllloader.New("wintun.dll", nil)
	procWintunCreateAdapter           = modwintun.NewProc("WintunCreateAdapter")
	procWintunCloseAdapter            = modwintun.NewProc("WintunCloseAdapter")
	procWintunDeleteDriver            = modwintun.NewProc("WintunDeleteDriver")
	procWintunGetAdapterLUID          = modwintun.NewProc("WintunGetAdapterLUID")
	procWintunGetRunningDriverVersion = modwintun.NewProc("WintunGetRunningDriverVersion")
	procWintunAllocateSendPacket      = modwintun.NewProc("WintunAllocateSendPacket")
	procWintunEndSession              = modwintun.NewProc("WintunEndSession")
	procWintunGetReadWaitEvent        = modwintun.NewProc("WintunGetReadWaitEvent")
	procWintunReceivePacket           = modwintun.NewProc("WintunReceivePacket")
	procWintunReleaseReceivePacket    = modwintun.NewProc("WintunReleaseReceivePacket")
	procWintunSendPacket              = modwintun.NewProc("WintunSendPacket")
	procWintunStartSession            = modwintun.NewProc("WintunStartSession")
)

var ErrNoMorePackets = errors.New("wintun: no more packets are available")

type Adapter struct {
	handle uintptr
}

type Session struct {
	handle uintptr
}

func CreateAdapter(name, tunnelType string, requestedGUID *windows.GUID) (*Adapter, error) {
	name16, err := windows.UTF16PtrFromString(name)
	if err != nil {
		return nil, err
	}
	tunnelType16, err := windows.UTF16PtrFromString(tunnelType)
	if err != nil {
		return nil, err
	}
	handle, _, lastError := syscall.SyscallN(procWintunCreateAdapter.Addr(),
		uintptr(unsafe.Pointer(name16)), uintptr(unsafe.Pointer(tunnelType16)), uintptr(unsafe.Pointer(requestedGUID)))
	if handle == 0 {
		return nil, lastError
	}
	return &Adapter{handle: handle}, nil
}

func (a *Adapter) Close() error {
	if a.handle == 0 {
		return nil
	}
	_, _, lastError := syscall.SyscallN(procWintunCloseAdapter.Addr(), a.handle)
	a.handle = 0
	if lastError != windows.ERROR_SUCCESS {
		return lastError
	}
	return nil
}

func Uninstall() error {
	result, _, lastError := syscall.SyscallN(procWintunDeleteDriver.Addr())
	if result == 0 {
		return lastError
	}
	return nil
}

func RunningVersion() (uint32, error) {
	version, _, lastError := syscall.SyscallN(procWintunGetRunningDriverVersion.Addr())
	if version == 0 {
		return 0, lastError
	}
	return uint32(version), nil
}

func (a *Adapter) LUID() winipcfg.LUID {
	var luid uint64
	syscall.SyscallN(procWintunGetAdapterLUID.Addr(), a.handle, uintptr(unsafe.Pointer(&luid)))
	return winipcfg.LUID(luid)
}

func (a *Adapter) StartSession(capacity uint32) (*Session, error) {
	handle, _, lastError := syscall.SyscallN(procWintunStartSession.Addr(), a.handle, uintptr(capacity))
	if handle == 0 {
		return nil, lastError
	}
	return &Session{handle: handle}, nil
}

func (s *Session) End() {
	if s.handle == 0 {
		return
	}
	syscall.SyscallN(procWintunEndSession.Addr(), s.handle)
	s.handle = 0
}

func (s *Session) ReadWaitEvent() windows.Handle {
	handle, _, _ := syscall.SyscallN(procWintunGetReadWaitEvent.Addr(), s.handle)
	return windows.Handle(handle)
}

func (s *Session) ReceivePacket() ([]byte, error) {
	var size uint32
	packet, _, lastError := syscall.SyscallN(procWintunReceivePacket.Addr(), s.handle, uintptr(unsafe.Pointer(&size)))
	if packet == 0 {
		if lastError == windows.ERROR_NO_MORE_ITEMS {
			return nil, ErrNoMorePackets
		}
		return nil, lastError
	}
	return unsafe.Slice((*byte)(unsafe.Pointer(packet)), size), nil
}

func (s *Session) ReleaseReceivePacket(packet []byte) {
	syscall.SyscallN(procWintunReleaseReceivePacket.Addr(), s.handle, uintptr(unsafe.Pointer(unsafe.SliceData(packet))))
	runtime.KeepAlive(packet)
}

func (s *Session) AllocateSendPacket(size int) ([]byte, error) {
	packet, _, lastError := syscall.SyscallN(procWintunAllocateSendPacket.Addr(), s.handle, uintptr(size))
	if packet == 0 {
		return nil, lastError
	}
	return unsafe.Slice((*byte)(unsafe.Pointer(packet)), size), nil
}

func (s *Session) SendPacket(packet []byte) {
	syscall.SyscallN(procWintunSendPacket.Addr(), s.handle, uintptr(unsafe.Pointer(unsafe.SliceData(packet))))
	runtime.KeepAlive(packet)
}
