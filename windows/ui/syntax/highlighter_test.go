/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package syntax

import (
	"strings"
	"testing"
)

const phobosConfig = `[Interface]
PrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=
Address = 10.8.0.2/32
MTU = 1420
DNS = 1.1.1.1

[Peer]
PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
Endpoint = 127.0.0.1:51822

[instance]
source-if = 127.0.0.1
source-lport = 51822
target = vpn.example.com:51823
key = Ic0OGtSf1BdMmMDzs7GmYRuPS/HGmNXsSU9EOWEeuQI=
masking = MEDIA
obfuscate-bytes = 16
max-dummy = 4
media-pt = 102
media-ssrc = 0xDEADBEEF
media-clock = 30
verbose = 2
`

const phobosSocks5Config = `[instance]
mode = socks5
role = client
source-lport = 1080
target = vpn.example.com:51824
key = Ic0OGtSf1BdMmMDzs7GmYRuPS/HGmNXsSU9EOWEeuQI=
masking = STUN

[socks5]
login = phobos-user
password = s3cr3t
`

func errorSpans(t *testing.T, config string) []string {
	t.Helper()
	var offenders []string
	for _, span := range highlightConfig(config) {
		if span.t == highlightError {
			offenders = append(offenders, config[span.s:span.s+span.len])
		}
	}
	return offenders
}

func TestPhobosSectionsHighlightWithoutErrors(t *testing.T) {
	for name, config := range map[string]string{"wireguard": phobosConfig, "socks5": phobosSocks5Config} {
		t.Run(name, func(t *testing.T) {
			if offenders := errorSpans(t, config); offenders != nil {
				t.Fatalf("unexpected error spans: %q", offenders)
			}
		})
	}
}

func TestPhobosFieldsAreFlaggedOutsideTheirSection(t *testing.T) {
	misplaced := strings.Replace(phobosConfig, "MTU = 1420", "masking = STUN", 1)
	if offenders := errorSpans(t, misplaced); len(offenders) == 0 {
		t.Fatal("masking in [Interface] should be an error")
	}
}

func TestPhobosInvalidValuesAreFlagged(t *testing.T) {
	cases := map[string]string{
		"masking":      strings.Replace(phobosConfig, "masking = MEDIA", "masking = quic", 1),
		"mode":         strings.Replace(phobosSocks5Config, "mode = socks5", "mode = tcp", 1),
		"role":         strings.Replace(phobosSocks5Config, "role = client", "role = server", 1),
		"target":       strings.Replace(phobosConfig, "target = vpn.example.com:51823", "target = vpn.example.com", 1),
		"source-lport": strings.Replace(phobosConfig, "source-lport = 51822", "source-lport = 70000", 1),
		"media-pt":     strings.Replace(phobosConfig, "media-pt = 102", "media-pt = 300", 1),
		"media-clock":  strings.Replace(phobosConfig, "media-clock = 30", "media-clock = 4000", 1),
		"empty key":    strings.Replace(phobosConfig, "key = Ic0OGtSf1BdMmMDzs7GmYRuPS/HGmNXsSU9EOWEeuQI=", "key =", 1),
		"unknown key":  strings.Replace(phobosConfig, "max-dummy = 4", "threads = 2", 1),
	}
	for name, config := range cases {
		if offenders := errorSpans(t, config); len(offenders) == 0 {
			t.Errorf("%s: expected an error span", name)
		}
	}
}

func TestWireGuardSectionsStillHighlight(t *testing.T) {
	plain := `[Interface]
PrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=
Address = 10.8.0.2/32
Table = off

[Peer]
PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
AllowedIPs = 0.0.0.0/0
Endpoint = demo.wireguard.com:12912
PersistentKeepalive = 25
`
	if offenders := errorSpans(t, plain); offenders != nil {
		t.Fatalf("unexpected error spans in a plain config: %q", offenders)
	}
}
