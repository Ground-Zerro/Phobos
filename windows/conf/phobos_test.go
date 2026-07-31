/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package conf

import (
	"reflect"
	"strconv"
	"strings"
	"testing"

	"golang.zx2c4.com/wireguard/windows/phobos"
)

const wireGuardModeConfig = `[Interface]
PrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=
Address = 10.8.0.2/32, fdcc:ad94:bacf:61a3::2/128
MTU = 1420
DNS = 1.1.1.1

[Peer]
PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
PresharedKey = TrMvSoP4jYQlY6RIzBgbssQqY3vxI2Pi+y71lOWWXX0=
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
verbose = 2
`

const socks5ModeConfig = `[instance]
mode = socks5
role = client
source-if = 127.0.0.1
source-lport = 1080
target = vpn.example.com:51824
key = Ic0OGtSf1BdMmMDzs7GmYRuPS/HGmNXsSU9EOWEeuQI=
masking = STUN
verbose = 2

[socks5]
login = phobos-user
password = s3cr3t
`

func parseConfig(t *testing.T, text string) *Config {
	t.Helper()
	config, err := FromWgQuick(text, "test")
	if err != nil {
		t.Fatalf("unable to parse: %v", err)
	}
	return config
}

func TestParseWireGuardModeObfuscation(t *testing.T) {
	config := parseConfig(t, wireGuardModeConfig)

	if config.IsSocks5() {
		t.Fatal("config must not be a SOCKS5 tunnel")
	}
	if len(config.Peers) != 1 {
		t.Fatalf("expected one peer, got %d", len(config.Peers))
	}
	o := config.Peers[0].Obfuscation
	if o == nil {
		t.Fatal("peer has no obfuscation")
	}
	if o.Mode != ObfuscationModeWireGuard {
		t.Errorf("mode = %v", o.Mode)
	}
	if o.Target.Host != "vpn.example.com" || o.Target.Port != 51823 {
		t.Errorf("target = %v", o.Target.String())
	}
	if o.Key != "Ic0OGtSf1BdMmMDzs7GmYRuPS/HGmNXsSU9EOWEeuQI=" {
		t.Errorf("key = %q", o.Key)
	}
	if o.Masking != phobos.MaskingMEDIA {
		t.Errorf("masking = %v", o.Masking)
	}
	if o.ObfuscateBytes != 16 || o.MaxDummy != 4 || o.SourceListenPort != 51822 {
		t.Errorf("obfuscate-bytes = %d, max-dummy = %d, source-lport = %d", o.ObfuscateBytes, o.MaxDummy, o.SourceListenPort)
	}
}

func TestParseSocks5Mode(t *testing.T) {
	config := parseConfig(t, socks5ModeConfig)

	if !config.IsSocks5() {
		t.Fatal("config must be a SOCKS5 tunnel")
	}
	if len(config.Peers) != 0 {
		t.Fatalf("SOCKS5 tunnels carry no peers, got %d", len(config.Peers))
	}
	o := config.Obfuscation
	if o.Target.Host != "vpn.example.com" || o.Target.Port != 51824 {
		t.Errorf("target = %v", o.Target.String())
	}
	if o.Masking != phobos.MaskingSTUN {
		t.Errorf("masking = %v", o.Masking)
	}
	if o.SourceListenPort != 1080 {
		t.Errorf("source-lport = %d", o.SourceListenPort)
	}
	if o.Login != "phobos-user" || o.Password != "s3cr3t" {
		t.Errorf("credentials = %q/%q", o.Login, o.Password)
	}
}

func TestObfuscationSurvivesRoundTrip(t *testing.T) {
	for name, text := range map[string]string{"wireguard": wireGuardModeConfig, "socks5": socks5ModeConfig} {
		t.Run(name, func(t *testing.T) {
			first := parseConfig(t, text)
			serialized := first.ToWgQuick()
			second := parseConfig(t, serialized)
			if serialized != second.ToWgQuick() {
				t.Fatalf("round trip is not stable:\n%s\n---\n%s", serialized, second.ToWgQuick())
			}

			firstObfuscation, secondObfuscation := first.Obfuscation, second.Obfuscation
			if !first.IsSocks5() {
				firstObfuscation, secondObfuscation = first.Peers[0].Obfuscation, second.Peers[0].Obfuscation
			}
			firstObfuscation.Comments, firstObfuscation.Socks5Comments = SectionComments{}, SectionComments{}
			secondObfuscation.Comments, secondObfuscation.Socks5Comments = SectionComments{}, SectionComments{}
			if !reflect.DeepEqual(*firstObfuscation, *secondObfuscation) {
				t.Fatalf("obfuscation drifted:\n%+v\n%+v", *firstObfuscation, *secondObfuscation)
			}
		})
	}
}

func TestSerializedSocks5HasNoInterface(t *testing.T) {
	serialized := parseConfig(t, socks5ModeConfig).ToWgQuick()
	if strings.Contains(serialized, "[Interface]") || strings.Contains(serialized, "PrivateKey") {
		t.Fatalf("SOCKS5 tunnel must not serialize a WireGuard interface:\n%s", serialized)
	}
	if !strings.Contains(serialized, "mode = socks5") || !strings.Contains(serialized, "[Socks5]") {
		t.Fatalf("missing SOCKS5 sections:\n%s", serialized)
	}
}

func TestMediaObfuscateBytesDefaultsWhenAbsent(t *testing.T) {
	text := strings.Replace(wireGuardModeConfig, "obfuscate-bytes = 16\n", "", 1)
	config := parseConfig(t, text)
	if got := config.Peers[0].Obfuscation.ObfuscateBytes; got != phobos.MediaObfuscateBytesDefault {
		t.Fatalf("obfuscate-bytes = %d, want %d", got, phobos.MediaObfuscateBytesDefault)
	}
}

func TestMediaObfuscateBytesKeepsExplicitZero(t *testing.T) {
	text := strings.Replace(wireGuardModeConfig, "obfuscate-bytes = 16", "obfuscate-bytes = 0", 1)
	config := parseConfig(t, text)
	if got := config.Peers[0].Obfuscation.ObfuscateBytes; got != 0 {
		t.Fatalf("obfuscate-bytes = %d, want 0", got)
	}
}

func TestObfuscateBytesSurvivesSerialization(t *testing.T) {
	for _, value := range []uint16{0, 16} {
		text := strings.Replace(wireGuardModeConfig, "obfuscate-bytes = 16",
			"obfuscate-bytes = "+strconv.Itoa(int(value)), 1)
		serialized := parseConfig(t, text).ToWgQuick()
		if got := parseConfig(t, serialized).Peers[0].Obfuscation.ObfuscateBytes; got != value {
			t.Fatalf("obfuscate-bytes = %d after round trip, want %d:\n%s", got, value, serialized)
		}
	}
}

func TestMediaSSRCAcceptsHexAndDecimal(t *testing.T) {
	for value, want := range map[string]uint32{"0xDEADBEEF": 0xDEADBEEF, "3735928559": 0xDEADBEEF, "0": 0} {
		text := strings.Replace(wireGuardModeConfig, "masking = MEDIA", "masking = MEDIA\nmedia-ssrc = "+value, 1)
		config := parseConfig(t, text)
		if got := config.Peers[0].Obfuscation.MediaSSRC; got != want {
			t.Errorf("media-ssrc %q parsed as %d, want %d", value, got, want)
		}
	}
}

func TestMediaParamsDeriveTimestampStep(t *testing.T) {
	o := &Obfuscation{MediaPayloadType: 102, MediaSSRC: 7, MediaClock: 30}
	params := o.MediaParams()
	if params.TimestampStep != 3000 {
		t.Fatalf("timestamp step = %d, want 3000", params.TimestampStep)
	}
	if params.PayloadType != 102 || params.SSRC != 7 {
		t.Fatalf("unexpected media params %+v", params)
	}
	if (&Obfuscation{}).MediaParams().TimestampStep != 0 {
		t.Fatal("timestamp step must stay zero without a media clock")
	}
}

func TestObfuscationMatchesPeerBySourcePort(t *testing.T) {
	text := `[Interface]
PrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=
Address = 10.8.0.2/32

[Peer]
PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
AllowedIPs = 10.0.0.0/24
Endpoint = 127.0.0.1:51001

[Peer]
PublicKey = TrMvSoP4jYQlY6RIzBgbssQqY3vxI2Pi+y71lOWWXX0=
AllowedIPs = 10.0.1.0/24
Endpoint = 127.0.0.1:51002

[instance]
source-lport = 51002
target = second.example.com:1
key = second-key
masking = STUN

[instance]
source-lport = 51001
target = first.example.com:2
key = first-key
masking = none
`
	config := parseConfig(t, text)
	if config.Peers[0].Obfuscation.Target.Host != "first.example.com" {
		t.Errorf("first peer got %v", config.Peers[0].Obfuscation.Target)
	}
	if config.Peers[1].Obfuscation.Target.Host != "second.example.com" {
		t.Errorf("second peer got %v", config.Peers[1].Obfuscation.Target)
	}
}

func TestObfuscationRejectsBadInput(t *testing.T) {
	cases := map[string]string{
		"unknown key":     strings.Replace(wireGuardModeConfig, "max-dummy = 4", "max-dumy = 4", 1),
		"bad masking":     strings.Replace(wireGuardModeConfig, "masking = MEDIA", "masking = quic", 1),
		"server role":     strings.Replace(socks5ModeConfig, "role = client", "role = server", 1),
		"missing target":  strings.Replace(wireGuardModeConfig, "target = vpn.example.com:51823\n", "", 1),
		"missing key":     strings.Replace(wireGuardModeConfig, "key = Ic0OGtSf1BdMmMDzs7GmYRuPS/HGmNXsSU9EOWEeuQI=\n", "", 1),
		"socks5 key":      strings.Replace(socks5ModeConfig, "login = phobos-user", "user = phobos-user", 1),
		"orphan instance": strings.Replace(wireGuardModeConfig, "masking = MEDIA", "mode = socks5", 1),
	}
	for name, text := range cases {
		if _, err := FromWgQuick(text, "test"); err == nil {
			t.Errorf("%s: expected a parse error", name)
		}
	}
}

func TestObfuscationAcceptsBinaryOnlyOptions(t *testing.T) {
	text := strings.Replace(wireGuardModeConfig, "max-dummy = 4", "max-dummy = 4\nthreads = 2\nidle-timeout = 300\nfwmark = 51820", 1)
	if _, err := FromWgQuick(text, "test"); err != nil {
		t.Fatalf("options meant for the obfuscator binary must be accepted: %v", err)
	}
}

func TestRedactClearsObfuscationSecrets(t *testing.T) {
	config := parseConfig(t, socks5ModeConfig)
	config.Redact()
	o := config.Obfuscation
	if o.Key != "" || o.Login != "" || o.Password != "" {
		t.Fatalf("secrets survived redaction: %+v", *o)
	}
	if o.Target.Host != "vpn.example.com" {
		t.Fatal("redaction must keep the target")
	}
}
