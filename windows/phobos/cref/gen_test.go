//go:build phoboscref

/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package cref_test

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"math/rand"
	"net/netip"
	"os"
	"testing"

	"golang.zx2c4.com/wireguard/windows/phobos/cref"
)

const goldenHeader = `/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package phobos

type maskVector struct {
	key    string
	length int
	digest string
}

type streamVector struct {
	key    string
	length int
	split  int
	digest string
}

type decodeVector struct {
	key            string
	obfuscateBytes int
	encoded        string
	decoded        string
}

type bindingSuccessVector struct {
	txid string
	addr string
	out  string
}

`

func digest(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func TestGenerateGoldenVectors(t *testing.T) {
	path := os.Getenv("PHOBOS_GOLDEN_OUT")
	if path == "" {
		t.Skip("set PHOBOS_GOLDEN_OUT to regenerate golden vectors")
	}

	keys := []string{"k", "phobos", "Ic0OGtSf1BdMmMDzs7GmYRuPS/HGmNXsSU9EOWEeuQI="}
	var out bytes.Buffer
	out.WriteString(goldenHeader)

	out.WriteString("var maskVectors = []maskVector{\n")
	for _, key := range keys {
		for _, length := range []int{1, 16, 64, 148, 1499, 1500, 1501, 4096, 9000} {
			mask := cref.XOR(make([]byte, length), []byte(key))
			fmt.Fprintf(&out, "\t{%q, %d, %q},\n", key, length, digest(mask))
		}
	}
	out.WriteString("}\n\n")

	out.WriteString("var streamVectors = []streamVector{\n")
	for _, key := range keys {
		for _, length := range []int{64, 65, 300, 20000} {
			for _, split := range []int{0, 1, length / 2} {
				stream := cref.Stream(make([]byte, length), []byte(key), split)
				fmt.Fprintf(&out, "\t{%q, %d, %d, %q},\n", key, length, split, digest(stream))
			}
		}
	}
	out.WriteString("}\n\n")

	rng := rand.New(rand.NewSource(42))
	out.WriteString("var decodeVectors = []decodeVector{\n")
	for _, key := range keys {
		for _, obfuscateBytes := range []int{0, 16} {
			for _, length := range []int{32, 92, 148} {
				payload := make([]byte, length)
				rng.Read(payload)
				payload[0] = byte(1 + rng.Intn(4))
				payload[1], payload[2], payload[3] = 0, 0, 0
				encoded := cref.Encode(payload, []byte(key), 4, obfuscateBytes, 65535)
				fmt.Fprintf(&out, "\t{%q, %d,\n\t\t%q,\n\t\t%q},\n", key, obfuscateBytes,
					hex.EncodeToString(encoded), hex.EncodeToString(payload))
			}
		}
	}
	out.WriteString("}\n\n")

	out.WriteString("var bindingSuccessVectors = []bindingSuccessVector{\n")
	for _, addr := range []string{"127.0.0.1:51820", "10.0.0.7:1", "203.0.113.42:65535"} {
		txid := make([]byte, 12)
		rng.Read(txid)
		frame := cref.StunBindingSuccess(txid, netip.MustParseAddrPort(addr))
		fmt.Fprintf(&out, "\t{%q, %q,\n\t\t%q},\n", hex.EncodeToString(txid), addr, hex.EncodeToString(frame))
	}
	out.WriteString("}\n")

	if err := os.WriteFile(path, out.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
}
