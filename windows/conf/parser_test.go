/* SPDX-License-Identifier: MIT
 *
 * Copyright (C) 2019-2026 WireGuard LLC. All Rights Reserved.
 */

package conf

import (
	"net/netip"
	"reflect"
	"runtime"
	"strings"
	"testing"
)

const testInput = `
[Interface] 
Address = 10.192.122.1/24 
Address = 10.10.0.1/16 
PrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk= 
ListenPort = 51820  #comments don't matter

[Peer] 
PublicKey   =   xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=    
Endpoint = 192.95.5.67:1234 
AllowedIPs = 10.192.122.3/32, 10.192.124.1/24

[Peer] 
PublicKey = TrMvSoP4jYQlY6RIzBgbssQqY3vxI2Pi+y71lOWWXX0= 
Endpoint = [2607:5300:60:6b0::c05f:543]:2468 
AllowedIPs = 10.192.122.4/32, 192.168.0.0/16
PersistentKeepalive = 100

[Peer] 
PublicKey = gN65BkIKy1eCE9pP1wdc8ROUtkHLF2PfAqYdyYBz6EA= 
PresharedKey = TrMvSoP4jYQlY6RIzBgbssQqY3vxI2Pi+y71lOWWXX0= 
Endpoint = test.wireguard.com:18981 
AllowedIPs = 10.10.10.230/32`

func noError(t *testing.T, err error) bool {
	if err == nil {
		return true
	}
	_, fn, line, _ := runtime.Caller(1)
	t.Errorf("Error at %s:%d: %#v", fn, line, err)
	return false
}

func equal(t *testing.T, expected, actual any) bool {
	if reflect.DeepEqual(expected, actual) {
		return true
	}
	_, fn, line, _ := runtime.Caller(1)
	t.Errorf("Failed equals at %s:%d\nactual   %#v\nexpected %#v", fn, line, actual, expected)
	return false
}

func lenTest(t *testing.T, actualO any, expected int) bool {
	actual := reflect.ValueOf(actualO).Len()
	if reflect.DeepEqual(expected, actual) {
		return true
	}
	_, fn, line, _ := runtime.Caller(1)
	t.Errorf("Wrong length at %s:%d\nactual   %#v\nexpected %#v", fn, line, actual, expected)
	return false
}

func contains(t *testing.T, list, element any) bool {
	listValue := reflect.ValueOf(list)
	for i := 0; i < listValue.Len(); i++ {
		if reflect.DeepEqual(listValue.Index(i).Interface(), element) {
			return true
		}
	}
	_, fn, line, _ := runtime.Caller(1)
	t.Errorf("Error %s:%d\nelement not found: %#v", fn, line, element)
	return false
}

func TestFromWgQuick(t *testing.T) {
	conf, err := FromWgQuick(testInput, "test")
	if noError(t, err) {
		lenTest(t, conf.Interface.Addresses, 2)
		contains(t, conf.Interface.Addresses, netip.PrefixFrom(netip.AddrFrom4([4]byte{10, 10, 0, 1}), 16))
		contains(t, conf.Interface.Addresses, netip.PrefixFrom(netip.AddrFrom4([4]byte{10, 192, 122, 1}), 24))
		equal(t, "yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=", conf.Interface.PrivateKey.String())
		equal(t, uint16(51820), conf.Interface.ListenPort)

		lenTest(t, conf.Peers, 3)
		lenTest(t, conf.Peers[0].AllowedIPs, 2)
		equal(t, Endpoint{Host: "192.95.5.67", Port: 1234}, conf.Peers[0].Endpoint)
		equal(t, "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=", conf.Peers[0].PublicKey.String())

		lenTest(t, conf.Peers[1].AllowedIPs, 2)
		equal(t, Endpoint{Host: "2607:5300:60:6b0::c05f:543", Port: 2468}, conf.Peers[1].Endpoint)
		equal(t, "TrMvSoP4jYQlY6RIzBgbssQqY3vxI2Pi+y71lOWWXX0=", conf.Peers[1].PublicKey.String())
		equal(t, uint16(100), conf.Peers[1].PersistentKeepalive)

		lenTest(t, conf.Peers[2].AllowedIPs, 1)
		equal(t, Endpoint{Host: "test.wireguard.com", Port: 18981}, conf.Peers[2].Endpoint)
		equal(t, "gN65BkIKy1eCE9pP1wdc8ROUtkHLF2PfAqYdyYBz6EA=", conf.Peers[2].PublicKey.String())
		equal(t, "TrMvSoP4jYQlY6RIzBgbssQqY3vxI2Pi+y71lOWWXX0=", conf.Peers[2].PresharedKey.String())
	}
}

func TestComments(t *testing.T) {
	const input = `# top of file
# second line

[Interface] # the interface
PrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=
# which port
ListenPort = 51820 # inline port
Address = 10.0.0.1/24

# the only peer
[Peer]
PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
AllowedIPs = 0.0.0.0/0 # everything
# trailing note
`
	c, err := FromWgQuick(input, "test")
	if !noError(t, err) {
		return
	}

	equal(t, []string{"# top of file", "# second line", ""}, c.Interface.Comments.Header.Before)
	equal(t, "# the interface", c.Interface.Comments.Header.Suffix)
	equal(t, []string{"# which port"}, c.Interface.Comments.Lines["listenport"].Before)
	equal(t, "# inline port", c.Interface.Comments.Lines["listenport"].Suffix)
	equal(t, []string{"# the only peer"}, c.Peers[0].Comments.Header.Before)
	equal(t, "# everything", c.Peers[0].Comments.Lines["allowedips"].Suffix)
	equal(t, []string{"# trailing note"}, c.TrailingComments)

	c2, err := FromWgQuick("[Interface]\nPrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=\nPostUp = echo '#1 done'\n", "test")
	if noError(t, err) {
		equal(t, "echo '#1 done'", c2.Interface.PostUp)
		equal(t, "", c2.Interface.Comments.Lines["postup"].Suffix)
	}

	serialized := c.ToWgQuick()
	for _, want := range []string{
		"# top of file\n# second line\n\n[Interface] # the interface\n",
		"# which port\nListenPort = 51820 # inline port\n",
		"# the only peer\n[Peer]\n",
		"AllowedIPs = 0.0.0.0/0 # everything\n",
		"# trailing note\n",
	} {
		if !strings.Contains(serialized, want) {
			t.Errorf("serialized config missing %q in:\n%s", want, serialized)
		}
	}

	reparsed, err := FromWgQuick(serialized, "test")
	if noError(t, err) {
		equal(t, serialized, reparsed.ToWgQuick())
		equal(t, c, reparsed)
	}
}

func TestCommentBlankLines(t *testing.T) {
	const input = `# Header line one

# Header line two
[Interface]
PrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=

# blank line precedes this comment
ListenPort = 51820
Address = 10.0.0.1/24


# multiple blank lines above collapse to one
[Peer]
PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
AllowedIPs = 0.0.0.0/0
`
	c, err := FromWgQuick(input, "test")
	if !noError(t, err) {
		return
	}

	equal(t, []string{"# Header line one", "", "# Header line two"}, c.Interface.Comments.Header.Before)
	equal(t, []string{"", "# blank line precedes this comment"}, c.Interface.Comments.Lines["listenport"].Before)
	equal(t, []string{"# multiple blank lines above collapse to one"}, c.Peers[0].Comments.Header.Before)

	serialized := c.ToWgQuick()
	for _, want := range []string{
		"# Header line one\n\n# Header line two\n[Interface]\n",
		"\n# blank line precedes this comment\nListenPort = 51820\n",
		"\n# multiple blank lines above collapse to one\n[Peer]\n",
	} {
		if !strings.Contains(serialized, want) {
			t.Errorf("serialized config missing %q in:\n%s", want, serialized)
		}
	}
	if strings.Contains(serialized, "\n\n\n") {
		t.Errorf("serialized config has a run of blank lines:\n%s", serialized)
	}

	reparsed, err := FromWgQuick(serialized, "test")
	if noError(t, err) {
		equal(t, serialized, reparsed.ToWgQuick())
		equal(t, c, reparsed)
	}
}

func TestCommentRepeatedKey(t *testing.T) {
	const input = `[Interface]
PrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=
# a

Address = 10.0.0.1/24 # home

# b
Address = 10.0.0.2/24 # work
`
	c, err := FromWgQuick(input, "test")
	if !noError(t, err) {
		return
	}
	lenTest(t, c.Interface.Addresses, 2)
	addr := c.Interface.Comments.Lines["address"]
	equal(t, []string{"# a", "", "# b"}, addr.Before)
	equal(t, "# home # work", addr.Suffix)
	serialized := c.ToWgQuick()
	if !strings.Contains(serialized, "# a\n\n# b\nAddress = 10.0.0.1/24, 10.0.0.2/24 # home # work\n") {
		t.Errorf("merged repeated-key comments wrong in:\n%s", serialized)
	}

	c2, err := FromWgQuick("# one\n[Interface] # h1\nPrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=\n# two\n[Interface] # h2\nListenPort = 51820\n", "test")
	if noError(t, err) {
		equal(t, []string{"# one", "# two"}, c2.Interface.Comments.Header.Before)
		equal(t, "# h1 # h2", c2.Interface.Comments.Header.Suffix)
	}
}

func TestCommentDefaultValuedKeys(t *testing.T) {
	for _, input := range []string{
		"[Interface]\nPrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=\n# note\nListenPort = 0 # inline\n",
		"[Interface]\nPrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=\n# note\nTable = auto # inline\n",
		"[Interface]\nPrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=\n[Peer]\nPublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=\nAllowedIPs = 0.0.0.0/0\n# note\nPersistentKeepalive = off # inline\n",
		"[Interface]\nPrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=\n[Peer]\nPublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=\nAllowedIPs = 0.0.0.0/0\n# note\nPresharedKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n",
	} {
		c, err := FromWgQuick(input, "test")
		if !noError(t, err) {
			continue
		}
		serialized := c.ToWgQuick()
		if !strings.Contains(serialized, "# note") {
			t.Errorf("comment on a default-valued key was dropped:\n--input--\n%s--output--\n%s", input, serialized)
		}
		reparsed, err := FromWgQuick(serialized, "test")
		if noError(t, err) {
			equal(t, c, reparsed)
		}
	}
}

func TestRedactClearsComments(t *testing.T) {
	input := "[Interface]\nPrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk= # backup SECRET\n" +
		"# note SECRET\n[Peer]\nPublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=\nAllowedIPs = 0.0.0.0/0\n# trailing SECRET\n"
	c, err := FromWgQuick(input, "test")
	if !noError(t, err) {
		return
	}
	c.Redact()
	if out := c.ToWgQuick(); strings.Contains(out, "SECRET") {
		t.Errorf("Redact left comment text in output:\n%s", out)
	}
}

func FuzzRoundTrip(f *testing.F) {
	f.Add(testInput)
	f.Add("# top of file\n# second line\n\n[Interface] # the interface\n" +
		"PrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=\n# which port\n" +
		"ListenPort = 51820 # inline port\nAddress = 10.0.0.1/24\n\n# the only peer\n[Peer]\n" +
		"PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=\nAllowedIPs = 0.0.0.0/0 # everything\n# trailing note\n")
	f.Add("[Interface]\nPrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=\n# a\n\n" +
		"Address = 10.0.0.1/24 # home\n\n# b\nAddress = 10.0.0.2/24 # work\n")
	f.Add("[Interface]\nPrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=\n# p\nListenPort = 0 # x\n" +
		"# t\nTable = auto # y\n[Peer]\nPublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=\n" +
		"AllowedIPs = 0.0.0.0/0\n# k\nPersistentKeepalive = off # z\n")
	f.Add("[Interface]\nPrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=\nDNS = 1.1.1.1, home.arpa\nMTU = 1280\n" +
		"# pre\nPreUp = echo a=b #1\nPostUp = ip route add # x\nPreDown = echo down\nPostDown = echo # done\n")

	f.Fuzz(func(t *testing.T, s string) {
		c, err := FromWgQuick(s, "test")
		if err != nil {
			return
		}
		serialized := c.ToWgQuick()
		reparsed, err := FromWgQuick(serialized, "test")
		if err != nil {
			t.Fatalf("reserialized config no longer parses: %v\n%s", err, serialized)
		}
		if got := reparsed.ToWgQuick(); got != serialized {
			t.Errorf("serialization is not idempotent\n--first--\n%s--second--\n%s", serialized, got)
		}
		if !reflect.DeepEqual(c, reparsed) {
			t.Errorf("round-trip changed the parsed config\n--input--\n%s--serialized--\n%s", s, serialized)
		}
		if strings.Contains(serialized, "\n\n\n") {
			t.Errorf("output has consecutive blank lines:\n%s", serialized)
		}
		if strings.HasPrefix(serialized, "\n") {
			t.Errorf("output begins with a blank line:\n%s", serialized)
		}
	})
}

func TestParseEndpoint(t *testing.T) {
	_, err := parseEndpoint("[192.168.42.0:]:51880")
	if err == nil {
		t.Error("Error was expected")
	}
	e, err := parseEndpoint("192.168.42.0:51880")
	if noError(t, err) {
		equal(t, "192.168.42.0", e.Host)
		equal(t, uint16(51880), e.Port)
	}
	e, err = parseEndpoint("test.wireguard.com:18981")
	if noError(t, err) {
		equal(t, "test.wireguard.com", e.Host)
		equal(t, uint16(18981), e.Port)
	}
	e, err = parseEndpoint("[2607:5300:60:6b0::c05f:543]:2468")
	if noError(t, err) {
		equal(t, "2607:5300:60:6b0::c05f:543", e.Host)
		equal(t, uint16(2468), e.Port)
	}
	_, err = parseEndpoint("[::::::invalid:18981")
	if err == nil {
		t.Error("Error was expected")
	}
	_, err = parseEndpoint("::0")
	if err == nil {
		t.Error("Error was expected")
	}
}
