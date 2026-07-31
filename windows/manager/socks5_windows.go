/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package manager

import (
	"fmt"

	"golang.org/x/sys/windows"
	"golang.zx2c4.com/wireguard/windows/conf"
	"golang.zx2c4.com/wireguard/windows/tunnel/winipcfg"
)

func findAdapterLUID(name string) (winipcfg.LUID, error) {
	interfaces, err := winipcfg.GetAdaptersAddresses(windows.AF_UNSPEC, winipcfg.GAAFlagIncludeAll)
	if err != nil {
		return 0, err
	}
	for _, iface := range interfaces {
		if iface.FriendlyName() == name {
			return iface.LUID, nil
		}
	}
	return 0, fmt.Errorf("no adapter named %q", name)
}

func attachSocks5RuntimeCounters(config *conf.Config) error {
	luid, err := findAdapterLUID(config.Name)
	if err != nil {
		return err
	}
	row, err := luid.Interface()
	if err != nil {
		return err
	}
	config.Obfuscation.RxBytes = conf.Bytes(row.InOctets)
	config.Obfuscation.TxBytes = conf.Bytes(row.OutOctets)
	return nil
}
