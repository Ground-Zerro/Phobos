//go:build windows

/* SPDX-License-Identifier: MIT
 *
 * Copyright (C) 2017-2026 WireGuard LLC. All Rights Reserved.
 */

package dllloader

import (
	"fmt"
	"sync"
	"sync/atomic"
	"unsafe"
)

func New(name string, onLoad func(d *LazyDLL)) *LazyDLL {
	return &LazyDLL{Name: name, onLoad: onLoad}
}

func (d *LazyDLL) NewProc(name string) *LazyProc {
	return &LazyProc{dll: d, Name: name}
}

type LazyProc struct {
	Name string
	mu   sync.Mutex
	dll  *LazyDLL
	addr uintptr
}

func (p *LazyProc) Find() error {
	if atomic.LoadPointer((*unsafe.Pointer)(unsafe.Pointer(&p.addr))) != nil {
		return nil
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.addr != 0 {
		return nil
	}

	err := p.dll.Load()
	if err != nil {
		return fmt.Errorf("Error loading %v DLL: %w", p.dll.Name, err)
	}
	addr, err := p.nameToAddr()
	if err != nil {
		return fmt.Errorf("Error getting %v address: %w", p.Name, err)
	}

	atomic.StorePointer((*unsafe.Pointer)(unsafe.Pointer(&p.addr)), unsafe.Pointer(addr))
	return nil
}

func (p *LazyProc) Addr() uintptr {
	err := p.Find()
	if err != nil {
		panic(err)
	}
	return p.addr
}
