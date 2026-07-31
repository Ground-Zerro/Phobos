/* SPDX-License-Identifier: MIT
 *
 * Copyright (C) 2019-2026 WireGuard LLC. All Rights Reserved.
 */

package conf

import (
	"encoding/base64"
	"net/netip"
	"strconv"
	"strings"

	"golang.org/x/text/encoding/unicode"

	"golang.zx2c4.com/wireguard/windows/l18n"
	"golang.zx2c4.com/wireguard/windows/phobos"
)

type ParseError struct {
	why      string
	offender string
}

func (e *ParseError) Error() string {
	return l18n.Sprintf("%s: %q", e.why, e.offender)
}

func parseIPCidr(s string) (netip.Prefix, error) {
	ipcidr, err := netip.ParsePrefix(s)
	if err == nil {
		return ipcidr, nil
	}
	addr, err := netip.ParseAddr(s)
	if err != nil {
		return netip.Prefix{}, &ParseError{l18n.Sprintf("Invalid IP address: "), s}
	}
	return netip.PrefixFrom(addr, addr.BitLen()), nil
}

func parseEndpoint(s string) (*Endpoint, error) {
	i := strings.LastIndexByte(s, ':')
	if i < 0 {
		return nil, &ParseError{l18n.Sprintf("Missing port from endpoint"), s}
	}
	host, portStr := s[:i], s[i+1:]
	if len(host) < 1 {
		return nil, &ParseError{l18n.Sprintf("Invalid endpoint host"), host}
	}
	port, err := parsePort(portStr)
	if err != nil {
		return nil, err
	}
	hostColon := strings.IndexByte(host, ':')
	if host[0] == '[' || host[len(host)-1] == ']' || hostColon >= 0 {
		err := &ParseError{l18n.Sprintf("Brackets must contain an IPv6 address"), host}
		if len(host) > 3 && host[0] == '[' && host[len(host)-1] == ']' && hostColon > 0 {
			end := len(host) - 1
			if i := strings.LastIndexByte(host, '%'); i > 1 {
				end = i
			}
			maybeV6, err2 := netip.ParseAddr(host[1:end])
			if err2 != nil || !maybeV6.Is6() {
				return nil, err
			}
		} else {
			return nil, err
		}
		host = host[1 : len(host)-1]
	}
	return &Endpoint{host, port}, nil
}

func parseMTU(s string) (uint16, error) {
	m, err := strconv.Atoi(s)
	if err != nil {
		return 0, err
	}
	if m < 576 || m > 65535 {
		return 0, &ParseError{l18n.Sprintf("Invalid MTU"), s}
	}
	return uint16(m), nil
}

func parsePort(s string) (uint16, error) {
	m, err := strconv.Atoi(s)
	if err != nil {
		return 0, err
	}
	if m < 0 || m > 65535 {
		return 0, &ParseError{l18n.Sprintf("Invalid port"), s}
	}
	return uint16(m), nil
}

func parsePersistentKeepalive(s string) (uint16, error) {
	if s == "off" {
		return 0, nil
	}
	m, err := strconv.Atoi(s)
	if err != nil {
		return 0, err
	}
	if m < 0 || m > 65535 {
		return 0, &ParseError{l18n.Sprintf("Invalid persistent keepalive"), s}
	}
	return uint16(m), nil
}

func parseTableOff(s string) (bool, error) {
	if s == "off" {
		return true, nil
	} else if s == "auto" || s == "main" {
		return false, nil
	}
	_, err := strconv.ParseUint(s, 10, 32)
	return false, err
}

func parseKeyBase64(s string) (*Key, error) {
	k, err := base64.StdEncoding.DecodeString(s)
	if err != nil {
		return nil, &ParseError{l18n.Sprintf("Invalid key: %v", err), s}
	}
	if len(k) != KeyLength {
		return nil, &ParseError{l18n.Sprintf("Keys must decode to exactly 32 bytes"), s}
	}
	var key Key
	copy(key[:], k)
	return &key, nil
}

func splitList(s string) ([]string, error) {
	var out []string
	for split := range strings.SplitSeq(s, ",") {
		trim := strings.TrimSpace(split)
		if len(trim) == 0 {
			return nil, &ParseError{l18n.Sprintf("Two commas in a row"), s}
		}
		out = append(out, trim)
	}
	return out, nil
}

func parseUint16(s, what string) (uint16, error) {
	v, err := strconv.ParseUint(s, 10, 16)
	if err != nil {
		return 0, &ParseError{l18n.Sprintf("Invalid %s", what), s}
	}
	return uint16(v), nil
}

func parseObfuscationMode(s string) (ObfuscationMode, error) {
	switch strings.ToLower(s) {
	case "wireguard":
		return ObfuscationModeWireGuard, nil
	case "socks5":
		return ObfuscationModeSocks5, nil
	}
	return 0, &ParseError{l18n.Sprintf("Invalid obfuscator mode"), s}
}

func parseMasking(s string) (phobos.Masking, error) {
	masking, ok := phobos.ParseMasking(s)
	if !ok && !strings.EqualFold(strings.TrimSpace(s), "auto") {
		return 0, &ParseError{l18n.Sprintf("Invalid masking type"), s}
	}
	return masking, nil
}

func parseMediaSSRC(s string) (uint32, error) {
	base, digits := 10, s
	if rest, ok := strings.CutPrefix(strings.ToLower(s), "0x"); ok {
		base, digits = 16, rest
	}
	v, err := strconv.ParseUint(digits, base, 32)
	if err != nil {
		return 0, &ParseError{l18n.Sprintf("Invalid media SSRC"), s}
	}
	return uint32(v), nil
}

type parserState int

const (
	inInterfaceSection parserState = iota
	inPeerSection
	inObfuscationSection
	inSocks5Section
	notInASection
)

func (c *Config) maybeAddPeer(p *Peer) {
	if p != nil {
		c.Peers = append(c.Peers, *p)
	}
}

func (o *Obfuscation) validate() error {
	if o.Target.IsEmpty() {
		return &ParseError{l18n.Sprintf("An obfuscator instance must have a target"), l18n.Sprintf("[none specified]")}
	}
	if len(o.Key) == 0 {
		return &ParseError{l18n.Sprintf("An obfuscator instance must have a key"), l18n.Sprintf("[none specified]")}
	}
	return nil
}

func (conf *Config) attachObfuscations(obfuscations []*Obfuscation) error {
	if len(obfuscations) == 0 {
		return nil
	}
	for _, o := range obfuscations {
		if err := o.validate(); err != nil {
			return err
		}
	}

	if obfuscations[0].Mode == ObfuscationModeSocks5 {
		if len(obfuscations) != 1 {
			return &ParseError{l18n.Sprintf("A SOCKS5 tunnel accepts exactly one [Instance] section"), l18n.Sprintf("%d given", len(obfuscations))}
		}
		if len(conf.Peers) != 0 {
			return &ParseError{l18n.Sprintf("A SOCKS5 tunnel must not declare peers"), l18n.Sprintf("%d given", len(conf.Peers))}
		}
		conf.Obfuscation = obfuscations[0]
		conf.applySocks5InterfaceDefaults()
		return nil
	}

	if len(conf.Peers) == 0 {
		return &ParseError{l18n.Sprintf("An [Instance] section requires a peer to attach to"), l18n.Sprintf("[none specified]")}
	}
	for _, o := range obfuscations {
		peer := conf.matchObfuscationPeer(o, len(obfuscations))
		if peer == nil {
			return &ParseError{l18n.Sprintf("No peer matches the obfuscator source port"), strconv.Itoa(int(o.SourceListenPort))}
		}
		if peer.Obfuscation != nil {
			return &ParseError{l18n.Sprintf("A peer accepts only one [Instance] section"), peer.PublicKey.String()}
		}
		peer.Obfuscation = o
	}
	return nil
}

func (conf *Config) matchObfuscationPeer(o *Obfuscation, total int) *Peer {
	if total == 1 && len(conf.Peers) == 1 {
		return &conf.Peers[0]
	}
	for i := range conf.Peers {
		if conf.Peers[i].Endpoint.Port == o.SourceListenPort && o.SourceListenPort != 0 {
			return &conf.Peers[i]
		}
	}
	return nil
}

func FromWgQuick(s, name string) (*Config, error) {
	if !TunnelNameIsValid(name) {
		return nil, &ParseError{l18n.Sprintf("Tunnel name is not valid"), name}
	}
	lines := strings.Split(s, "\n")
	parserState := notInASection
	conf := Config{Name: name}
	sawPrivateKey := false
	var peer *Peer
	var obfuscation *Obfuscation
	var obfuscations []*Obfuscation
	var pendingComments []string
	for _, line := range lines {
		code, after, hasComment := strings.Cut(line, "#")
		comment := ""
		if hasComment {
			comment = "#" + strings.TrimRight(after, " \t\r")
		}
		stripped := strings.TrimSpace(code)
		if len(stripped) == 0 {
			if len(comment) != 0 {
				pendingComments = append(pendingComments, comment)
			} else {
				pendingComments = append(pendingComments, "")
			}
			continue
		}
		key, val, hasValue := strings.Cut(stripped, "=")
		key = strings.ToLower(strings.TrimSpace(key))
		if key == "[interface]" && !hasValue {
			conf.maybeAddPeer(peer)
			parserState = inInterfaceSection
			h := &conf.Interface.Comments.Header
			h.Before = append(h.Before, pendingComments...)
			if len(comment) != 0 {
				if len(h.Suffix) == 0 {
					h.Suffix = comment
				} else {
					h.Suffix += " " + comment
				}
			}
			pendingComments = nil
			continue
		}
		if key == "[peer]" && !hasValue {
			conf.maybeAddPeer(peer)
			peer = &Peer{}
			peer.Comments.Header = Comments{Before: pendingComments, Suffix: comment}
			pendingComments = nil
			parserState = inPeerSection
			continue
		}
		if key == "[instance]" && !hasValue {
			conf.maybeAddPeer(peer)
			peer = nil
			obfuscation = &Obfuscation{Masking: phobos.MaskingNone, MaxDummy: phobos.DefaultMaxDummy}
			obfuscation.Comments.Header = Comments{Before: pendingComments, Suffix: comment}
			obfuscations = append(obfuscations, obfuscation)
			pendingComments = nil
			parserState = inObfuscationSection
			continue
		}
		if key == "[socks5]" && !hasValue {
			if obfuscation == nil {
				return nil, &ParseError{l18n.Sprintf("A [Socks5] section must follow an [Instance] section"), stripped}
			}
			obfuscation.Socks5Comments.Header = Comments{Before: pendingComments, Suffix: comment}
			pendingComments = nil
			parserState = inSocks5Section
			continue
		}
		if parserState == notInASection {
			return nil, &ParseError{l18n.Sprintf("Line must occur in a section"), stripped}
		}
		if !hasValue {
			return nil, &ParseError{l18n.Sprintf("Config key is missing an equals separator"), stripped}
		}
		switch key {
		case "preup", "postup", "predown", "postdown":
			_, val, _ = strings.Cut(line, "=")
			comment = ""
		}
		val = strings.TrimSpace(val)
		if len(val) == 0 {
			return nil, &ParseError{l18n.Sprintf("Key must have a value"), stripped}
		}
		section := &conf.Interface.Comments
		switch parserState {
		case inPeerSection:
			section = &peer.Comments
		case inObfuscationSection:
			section = &obfuscation.Comments
		case inSocks5Section:
			section = &obfuscation.Socks5Comments
		}
		if len(pendingComments) != 0 || len(comment) != 0 {
			if section.Lines == nil {
				section.Lines = make(map[string]Comments)
			}
			c := section.Lines[key]
			c.Before = append(c.Before, pendingComments...)
			if len(comment) != 0 {
				if len(c.Suffix) == 0 {
					c.Suffix = comment
				} else {
					c.Suffix += " " + comment
				}
			}
			section.Lines[key] = c
		}
		pendingComments = nil
		if parserState == inInterfaceSection {
			switch key {
			case "privatekey":
				k, err := parseKeyBase64(val)
				if err != nil {
					return nil, err
				}
				conf.Interface.PrivateKey = *k
				sawPrivateKey = true
			case "listenport":
				p, err := parsePort(val)
				if err != nil {
					return nil, err
				}
				conf.Interface.ListenPort = p
			case "mtu":
				m, err := parseMTU(val)
				if err != nil {
					return nil, err
				}
				conf.Interface.MTU = m
			case "address":
				addresses, err := splitList(val)
				if err != nil {
					return nil, err
				}
				for _, address := range addresses {
					a, err := parseIPCidr(address)
					if err != nil {
						return nil, err
					}
					conf.Interface.Addresses = append(conf.Interface.Addresses, a)
				}
			case "dns":
				addresses, err := splitList(val)
				if err != nil {
					return nil, err
				}
				for _, address := range addresses {
					a, err := netip.ParseAddr(address)
					if err != nil {
						conf.Interface.DNSSearch = append(conf.Interface.DNSSearch, address)
					} else {
						conf.Interface.DNS = append(conf.Interface.DNS, a)
					}
				}
			case "preup":
				conf.Interface.PreUp = val
			case "postup":
				conf.Interface.PostUp = val
			case "predown":
				conf.Interface.PreDown = val
			case "postdown":
				conf.Interface.PostDown = val
			case "table":
				tableOff, err := parseTableOff(val)
				if err != nil {
					return nil, err
				}
				conf.Interface.TableOff = tableOff
			default:
				return nil, &ParseError{l18n.Sprintf("Invalid key for [Interface] section"), key}
			}
		} else if parserState == inPeerSection {
			switch key {
			case "publickey":
				k, err := parseKeyBase64(val)
				if err != nil {
					return nil, err
				}
				peer.PublicKey = *k
			case "presharedkey":
				k, err := parseKeyBase64(val)
				if err != nil {
					return nil, err
				}
				peer.PresharedKey = *k
			case "allowedips":
				addresses, err := splitList(val)
				if err != nil {
					return nil, err
				}
				for _, address := range addresses {
					a, err := parseIPCidr(address)
					if err != nil {
						return nil, err
					}
					peer.AllowedIPs = append(peer.AllowedIPs, a)
				}
			case "persistentkeepalive":
				p, err := parsePersistentKeepalive(val)
				if err != nil {
					return nil, err
				}
				peer.PersistentKeepalive = p
			case "endpoint":
				e, err := parseEndpoint(val)
				if err != nil {
					return nil, err
				}
				peer.Endpoint = *e
			default:
				return nil, &ParseError{l18n.Sprintf("Invalid key for [Peer] section"), key}
			}
		} else if parserState == inObfuscationSection {
			switch key {
			case "mode":
				m, err := parseObfuscationMode(val)
				if err != nil {
					return nil, err
				}
				obfuscation.Mode = m
			case "role":
				if !strings.EqualFold(val, "client") {
					return nil, &ParseError{l18n.Sprintf("Only the client obfuscator role is supported"), val}
				}
			case "source-lport":
				p, err := parsePort(val)
				if err != nil {
					return nil, err
				}
				obfuscation.SourceListenPort = p
			case "target":
				e, err := parseEndpoint(val)
				if err != nil {
					return nil, err
				}
				obfuscation.Target = *e
			case "key":
				obfuscation.Key = val
			case "masking":
				m, err := parseMasking(val)
				if err != nil {
					return nil, err
				}
				obfuscation.Masking = m
				if m == phobos.MaskingMEDIA && obfuscation.ObfuscateBytes == 0 {
					obfuscation.ObfuscateBytes = phobos.MediaObfuscateBytesDefault
				}
			case "obfuscate-bytes":
				b, err := parseUint16(val, "obfuscate-bytes")
				if err != nil {
					return nil, err
				}
				obfuscation.ObfuscateBytes = b
			case "max-dummy":
				d, err := parseUint16(val, "max-dummy")
				if err != nil {
					return nil, err
				}
				obfuscation.MaxDummy = d
			case "media-pt":
				pt, err := strconv.ParseUint(val, 10, 8)
				if err != nil || pt > 127 {
					return nil, &ParseError{l18n.Sprintf("Invalid RTP payload type"), val}
				}
				obfuscation.MediaPayloadType = uint8(pt)
			case "media-ssrc":
				ssrc, err := parseMediaSSRC(val)
				if err != nil {
					return nil, err
				}
				obfuscation.MediaSSRC = ssrc
			case "media-clock":
				clock, err := parseUint16(val, "media-clock")
				if err != nil || clock > 1000 {
					return nil, &ParseError{l18n.Sprintf("Invalid media clock"), val}
				}
				obfuscation.MediaClock = clock
			case "source-if", "verbose", "idle-timeout", "max-clients", "threads",
				"fwmark", "static-bindings", "socks5-users", "socks5-stats":
			default:
				return nil, &ParseError{l18n.Sprintf("Invalid key for [Instance] section"), key}
			}
		} else if parserState == inSocks5Section {
			switch key {
			case "login":
				obfuscation.Login = val
			case "password":
				obfuscation.Password = val
			default:
				return nil, &ParseError{l18n.Sprintf("Invalid key for [Socks5] section"), key}
			}
		}
	}
	conf.maybeAddPeer(peer)

	if err := conf.attachObfuscations(obfuscations); err != nil {
		return nil, err
	}

	pruneComments := func(run []string, dropLeading, dropTrailing bool) []string {
		var out []string
		for _, line := range run {
			if line == "" && len(out) != 0 && out[len(out)-1] == "" {
				continue
			}
			out = append(out, line)
		}
		if dropLeading && len(out) != 0 && out[0] == "" {
			out = out[1:]
		}
		if dropTrailing && len(out) != 0 && out[len(out)-1] == "" {
			out = out[:len(out)-1]
		}
		if len(out) == 0 || len(out) == 1 && out[0] == "" {
			return nil
		}
		return out
	}
	pruneSectionComments := func(s *SectionComments) {
		s.Header.Before = pruneComments(s.Header.Before, true, false)
		for key, c := range s.Lines {
			c.Before = pruneComments(c.Before, false, false)
			if len(c.Before) == 0 && len(c.Suffix) == 0 {
				delete(s.Lines, key)
			} else {
				s.Lines[key] = c
			}
		}
		if len(s.Lines) == 0 {
			s.Lines = nil
		}
	}

	conf.TrailingComments = pruneComments(pendingComments, false, true)
	pruneSectionComments(&conf.Interface.Comments)
	for i := range conf.Peers {
		pruneSectionComments(&conf.Peers[i].Comments)
		if o := conf.Peers[i].Obfuscation; o != nil {
			pruneSectionComments(&o.Comments)
		}
	}
	if conf.Obfuscation != nil {
		pruneSectionComments(&conf.Obfuscation.Comments)
		pruneSectionComments(&conf.Obfuscation.Socks5Comments)
	}

	if !sawPrivateKey && !conf.IsSocks5() {
		return nil, &ParseError{l18n.Sprintf("An interface must have a private key"), l18n.Sprintf("[none specified]")}
	}
	for _, p := range conf.Peers {
		if p.PublicKey.IsZero() {
			return nil, &ParseError{l18n.Sprintf("All peers must have public keys"), l18n.Sprintf("[none specified]")}
		}
	}

	return &conf, nil
}

func FromWgQuickWithUnknownEncoding(s, name string) (*Config, error) {
	c, firstErr := FromWgQuick(s, name)
	if firstErr == nil {
		return c, nil
	}
	for _, encoding := range unicode.All {
		decoded, err := encoding.NewDecoder().String(s)
		if err == nil {
			c, err := FromWgQuick(decoded, name)
			if err == nil {
				return c, nil
			}
		}
	}
	return nil, firstErr
}
