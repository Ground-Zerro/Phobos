/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package conf

import (
	"encoding/base64"
	"net/url"
	"strings"
	"unicode/utf8"

	"golang.zx2c4.com/wireguard/windows/l18n"
)

const (
	PhobosLinkScheme   = "phobos://"
	phobosLinkNoValue  = "none"
	phobosFallbackName = "phobos"
)

func IsPhobosLink(link string) bool {
	return strings.HasPrefix(strings.ToLower(strings.TrimSpace(link)), PhobosLinkScheme)
}

func DecodePhobosLink(link string) (config, name string, err error) {
	link = strings.TrimSpace(link)
	if !IsPhobosLink(link) {
		return "", "", &ParseError{l18n.Sprintf("Not a phobos:// link"), link}
	}

	body := link[len(PhobosLinkScheme):]
	payload, fragment, _ := strings.Cut(body, "#")
	payload = strings.TrimSuffix(payload, "/")
	if len(payload) == 0 {
		return "", "", &ParseError{l18n.Sprintf("The link carries no configuration"), link}
	}

	decoded, err := base64.RawURLEncoding.DecodeString(payload)
	if err != nil {
		return "", "", &ParseError{l18n.Sprintf("The link payload is not valid base64url: %v", err), payload}
	}
	if !utf8.Valid(decoded) {
		return "", "", &ParseError{l18n.Sprintf("The link payload is not valid UTF-8 text"), payload}
	}

	return stripUnsetFields(string(decoded)), phobosLinkName(fragment), nil
}

func phobosLinkName(fragment string) string {
	name, err := url.QueryUnescape(fragment)
	if err != nil {
		name = fragment
	}
	name = sanitizeTunnelName(name)
	if !TunnelNameIsValid(name) {
		return phobosFallbackName
	}
	return name
}

func sanitizeTunnelName(name string) string {
	if strings.EqualFold(strings.TrimSpace(name), phobosLinkNoValue) {
		return ""
	}
	var sanitized strings.Builder
	for _, r := range name {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9',
			r == '_', r == '=', r == '+', r == '.', r == '-':
			sanitized.WriteRune(r)
		default:
			sanitized.WriteByte('-')
		}
	}
	collapsed := sanitized.String()
	for strings.Contains(collapsed, "--") {
		collapsed = strings.ReplaceAll(collapsed, "--", "-")
	}
	collapsed = strings.Trim(collapsed, "-.")
	if len(collapsed) > 32 {
		collapsed = strings.Trim(collapsed[:32], "-.")
	}
	return collapsed
}

func stripUnsetFields(config string) string {
	lines := strings.Split(config, "\n")
	kept := lines[:0]
	for _, line := range lines {
		if key, value, found := strings.Cut(line, "="); found &&
			strings.EqualFold(strings.TrimSpace(value), phobosLinkNoValue) &&
			len(strings.TrimSpace(key)) > 0 {
			continue
		}
		kept = append(kept, line)
	}
	return strings.Join(kept, "\n")
}
