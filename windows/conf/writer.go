/* SPDX-License-Identifier: MIT
 *
 * Copyright (C) 2019-2026 WireGuard LLC. All Rights Reserved.
 */

package conf

import (
	"fmt"
	"strings"
)

func writeLine(output *strings.Builder, c Comments, line string) {
	for _, before := range c.Before {
		output.WriteString(before)
		output.WriteByte('\n')
	}
	output.WriteString(line)
	if len(c.Suffix) != 0 {
		output.WriteByte(' ')
		output.WriteString(c.Suffix)
	}
	output.WriteByte('\n')
}

func writeField(output *strings.Builder, comments SectionComments, key string, present bool, value any) {
	c := comments.Lines[strings.ToLower(key)]
	if !present && len(c.Before) == 0 && len(c.Suffix) == 0 {
		return
	}
	writeLine(output, c, key+" = "+fmt.Sprint(value))
}

func writeObfuscation(output *strings.Builder, o *Obfuscation) {
	writeLine(output, o.Comments.Header, "[Instance]")
	writeField(output, o.Comments, "mode", o.Mode == ObfuscationModeSocks5, "socks5")
	writeField(output, o.Comments, "source-lport", o.SourceListenPort > 0, o.SourceListenPort)
	writeField(output, o.Comments, "target", true, o.Target.String())
	writeField(output, o.Comments, "key", true, o.Key)
	writeField(output, o.Comments, "masking", true, o.Masking)
	if o.Mode == ObfuscationModeWireGuard {
		writeField(output, o.Comments, "obfuscate-bytes", true, o.ObfuscateBytes)
		writeField(output, o.Comments, "max-dummy", true, o.MaxDummy)
	}
	writeField(output, o.Comments, "media-pt", o.MediaPayloadType > 0, o.MediaPayloadType)
	writeField(output, o.Comments, "media-ssrc", o.MediaSSRC > 0, o.MediaSSRC)
	writeField(output, o.Comments, "media-clock", o.MediaClock > 0, o.MediaClock)

	if len(o.Login) == 0 && len(o.Password) == 0 {
		return
	}
	output.WriteByte('\n')
	writeLine(output, o.Socks5Comments.Header, "[Socks5]")
	writeField(output, o.Socks5Comments, "login", true, o.Login)
	writeField(output, o.Socks5Comments, "password", true, o.Password)
}

func (conf *Config) ToWgQuick() string {
	var output strings.Builder

	if !conf.IsSocks5() {
		writeLine(&output, conf.Interface.Comments.Header, "[Interface]")
		writeField(&output, conf.Interface.Comments, "PrivateKey", true, conf.Interface.PrivateKey.String())
		writeField(&output, conf.Interface.Comments, "ListenPort", conf.Interface.ListenPort > 0, conf.Interface.ListenPort)

		if len(conf.Interface.Addresses) > 0 {
			addrStrings := make([]string, len(conf.Interface.Addresses))
			for i, address := range conf.Interface.Addresses {
				addrStrings[i] = address.String()
			}
			writeField(&output, conf.Interface.Comments, "Address", true, strings.Join(addrStrings, ", "))
		}

		if len(conf.Interface.DNS)+len(conf.Interface.DNSSearch) > 0 {
			addrStrings := make([]string, 0, len(conf.Interface.DNS)+len(conf.Interface.DNSSearch))
			for _, address := range conf.Interface.DNS {
				addrStrings = append(addrStrings, address.String())
			}
			addrStrings = append(addrStrings, conf.Interface.DNSSearch...)
			writeField(&output, conf.Interface.Comments, "DNS", true, strings.Join(addrStrings, ", "))
		}

		writeField(&output, conf.Interface.Comments, "MTU", conf.Interface.MTU > 0, conf.Interface.MTU)
		writeField(&output, conf.Interface.Comments, "PreUp", len(conf.Interface.PreUp) > 0, conf.Interface.PreUp)
		writeField(&output, conf.Interface.Comments, "PostUp", len(conf.Interface.PostUp) > 0, conf.Interface.PostUp)
		writeField(&output, conf.Interface.Comments, "PreDown", len(conf.Interface.PreDown) > 0, conf.Interface.PreDown)
		writeField(&output, conf.Interface.Comments, "PostDown", len(conf.Interface.PostDown) > 0, conf.Interface.PostDown)

		table := "auto"
		if conf.Interface.TableOff {
			table = "off"
		}
		writeField(&output, conf.Interface.Comments, "Table", conf.Interface.TableOff, table)

		for _, peer := range conf.Peers {
			output.WriteByte('\n')
			writeLine(&output, peer.Comments.Header, "[Peer]")
			writeField(&output, peer.Comments, "PublicKey", true, peer.PublicKey.String())
			writeField(&output, peer.Comments, "PresharedKey", !peer.PresharedKey.IsZero(), peer.PresharedKey.String())

			if len(peer.AllowedIPs) > 0 {
				addrStrings := make([]string, len(peer.AllowedIPs))
				for i, address := range peer.AllowedIPs {
					addrStrings[i] = address.String()
				}
				writeField(&output, peer.Comments, "AllowedIPs", true, strings.Join(addrStrings, ", "))
			}

			writeField(&output, peer.Comments, "Endpoint", !peer.Endpoint.IsEmpty(), peer.Endpoint.String())
			writeField(&output, peer.Comments, "PersistentKeepalive", peer.PersistentKeepalive > 0, peer.PersistentKeepalive)
		}

		for _, peer := range conf.Peers {
			if peer.Obfuscation != nil {
				output.WriteByte('\n')
				writeObfuscation(&output, peer.Obfuscation)
			}
		}
	} else {
		writeObfuscation(&output, conf.Obfuscation)
	}

	for _, comment := range conf.TrailingComments {
		output.WriteString(comment)
		output.WriteByte('\n')
	}
	return output.String()
}
