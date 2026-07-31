/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package conf

import (
	"encoding/base64"
	"strings"
	"testing"

	"golang.zx2c4.com/wireguard/windows/phobos"
)

const specWireGuardLink = "phobos://W0ludGVyZmFjZV0KUHJpdmF0ZUtleSA9IE1Ccm5ab1RkeVQvTFI0WHBCN3RFbFN4eVZUUWRYRncwdHZWSk9NU0wvR0k9CkFkZHJlc3MgPSAxMC44LjAuNC8zMiwgZmRjYzphZDk0OmJhY2Y6NjFhNDo6Y2FmZTo0LzEyOApNVFUgPSAxNDIwCkROUyA9IDguOC44LjgsIDIwMDE6NDg2MDo0ODYwOjo4ODg4CgpbUGVlcl0KUHVibGljS2V5ID0gZy9HNHkyWGtUWTVtUExNWVlYWENhcnZ5eFVTSFV6TTF2cElZUkh3d0ZUND0KUHJlc2hhcmVkS2V5ID0gbDVURldNM3RJUjBEazg3dVBFblZrcXFsNExta2NQb2VXbU9LWktmeWVmWT0KQWxsb3dlZElQcyA9IDAuMC4wLjAvMCwgOjovMApQZXJzaXN0ZW50S2VlcGFsaXZlID0gMApFbmRwb2ludCA9IDEyNy4wLjAuMToxMzI1NQoKW2luc3RhbmNlXQpzb3VyY2UtaWYgPSAxMjcuMC4wLjEKc291cmNlLWxwb3J0ID0gMTMyNTUKdGFyZ2V0ID0gMTMwLjQ5LjE4NS4xMzY6NTE4MjQKa2V5ID0gWFIwTkVmOE1oR0FHY0NwYwptYXNraW5nID0gU1RVTgp2ZXJib3NlID0gSU5GTwppZGxlLXRpbWVvdXQgPSAzMDAKbWF4LWR1bW15ID0gNDU#Mobil-phone"

const specSocks5Link = "phobos://W2luc3RhbmNlXQptb2RlID0gc29ja3M1CnJvbGUgPSBjbGllbnQKc291cmNlLWlmID0gMTI3LjAuMC4xCnNvdXJjZS1scG9ydCA9IDEwODAKdGFyZ2V0ID0gdnBuLmV4YW1wbGUuY29tOjUxODI0CmtleSA9IFhSME5FZjhNaEdBR2NDcGMKbWFza2luZyA9IE1FRElBCnZlcmJvc2UgPSBlcnJvcgptZWRpYS1zc3JjID0gMzA1NDE5ODk2Cgpbc29ja3M1XQpsb2dpbiA9IEFiM0txCnBhc3N3b3JkID0gWng5TG0#Mobil-phone"

func linkFrom(config, fragment string) string {
	return PhobosLinkScheme + base64.RawURLEncoding.EncodeToString([]byte(config)) + "#" + fragment
}

func TestDecodeSpecWireGuardLink(t *testing.T) {
	text, name, err := DecodePhobosLink(specWireGuardLink)
	if err != nil {
		t.Fatalf("unable to decode: %v", err)
	}
	if name != "Mobil-phone" {
		t.Errorf("name = %q", name)
	}

	config, err := FromWgQuick(text, name)
	if err != nil {
		t.Fatalf("unable to parse the decoded configuration: %v", err)
	}
	if len(config.Peers) != 1 {
		t.Fatalf("expected one peer, got %d", len(config.Peers))
	}
	o := config.Peers[0].Obfuscation
	if o == nil {
		t.Fatal("the peer carries no obfuscation")
	}
	if o.Target.Host != "130.49.185.136" || o.Target.Port != 51824 {
		t.Errorf("target = %v", o.Target.String())
	}
	if o.Masking != phobos.MaskingSTUN {
		t.Errorf("masking = %v", o.Masking)
	}
	if o.MaxDummy != 45 || o.SourceListenPort != 13255 {
		t.Errorf("max-dummy = %d, source-lport = %d", o.MaxDummy, o.SourceListenPort)
	}
	if config.Interface.MTU != 1420 || len(config.Interface.DNS) != 2 {
		t.Errorf("interface = %+v", config.Interface)
	}
}

func TestDecodeSpecSocks5Link(t *testing.T) {
	text, name, err := DecodePhobosLink(specSocks5Link)
	if err != nil {
		t.Fatalf("unable to decode: %v", err)
	}
	config, err := FromWgQuick(text, name)
	if err != nil {
		t.Fatalf("unable to parse the decoded configuration: %v", err)
	}
	if !config.IsSocks5() {
		t.Fatal("expected a SOCKS5 tunnel")
	}
	o := config.Obfuscation
	if o.Target.Host != "vpn.example.com" || o.SourceListenPort != 1080 {
		t.Errorf("target = %v, source-lport = %d", o.Target.String(), o.SourceListenPort)
	}
	if o.Masking != phobos.MaskingMEDIA || o.MediaSSRC != 305419896 {
		t.Errorf("masking = %v, media-ssrc = %d", o.Masking, o.MediaSSRC)
	}
	if o.Login != "Ab3Kq" || o.Password != "Zx9Lm" {
		t.Errorf("credentials = %q/%q", o.Login, o.Password)
	}
}

func TestDecodeTreatsNoneAsUnset(t *testing.T) {
	text, _, err := DecodePhobosLink(linkFrom(`[Interface]
PrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=
Address = 10.8.0.2/32
MTU = none
DNS = none

[Peer]
PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
PresharedKey = none
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 0
Endpoint = 127.0.0.1:51822

[instance]
source-if = 127.0.0.1
source-lport = 51822
target = vpn.example.com:51823
key = secret
masking = none
verbose = none
idle-timeout = none
max-dummy = none
`, "peer"))
	if err != nil {
		t.Fatalf("unable to decode: %v", err)
	}
	if strings.Contains(text, "none") {
		t.Fatalf("unset fields survived decoding:\n%s", text)
	}

	config, err := FromWgQuick(text, "peer")
	if err != nil {
		t.Fatalf("unable to parse: %v", err)
	}
	if config.Interface.MTU != 0 || len(config.Interface.DNS) != 0 {
		t.Errorf("unset interface fields leaked: %+v", config.Interface)
	}
	if !config.Peers[0].PresharedKey.IsZero() {
		t.Error("unset preshared key leaked")
	}
	if config.Peers[0].Obfuscation.Masking != phobos.MaskingNone {
		t.Error("masking should fall back to none")
	}
}

func TestDecodeNames(t *testing.T) {
	for fragment, want := range map[string]string{
		"Mobil-phone":              "Mobil-phone",
		"none":                     "phobos",
		"":                         "phobos",
		"My%20Laptop":              "My-Laptop",
		"%D0%A2%D0%B5%D1%81%D1%82": "phobos",
		"a/b\\c":                   "a-b-c",
		"...":                      "phobos",
		strings.Repeat("x", 64):    strings.Repeat("x", 32),
	} {
		_, name, err := DecodePhobosLink(linkFrom("[Interface]\nPrivateKey = x\n", fragment))
		if err != nil {
			t.Fatalf("unable to decode %q: %v", fragment, err)
		}
		if name != want {
			t.Errorf("fragment %q gave name %q, want %q", fragment, name, want)
		}
		if !TunnelNameIsValid(name) {
			t.Errorf("fragment %q produced an invalid tunnel name %q", fragment, name)
		}
	}
}

func TestDecodeRejectsBadLinks(t *testing.T) {
	for name, link := range map[string]string{
		"wrong scheme": "https://example.com/#x",
		"no payload":   "phobos://#x",
		"bad base64":   "phobos://!!!!#x",
		"empty":        "",
	} {
		if _, _, err := DecodePhobosLink(link); err == nil {
			t.Errorf("%s: expected an error", name)
		}
	}
}

func TestIsPhobosLink(t *testing.T) {
	for link, want := range map[string]bool{
		"phobos://abc#n":    true,
		"  phobos://abc#n ": true,
		"PHOBOS://abc#n":    true,
		"phobos:/abc":       false,
		"http://abc":        false,
		"":                  false,
	} {
		if got := IsPhobosLink(link); got != want {
			t.Errorf("IsPhobosLink(%q) = %v", link, got)
		}
	}
}
