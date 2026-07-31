//go:build !windows

/* SPDX-License-Identifier: MIT
 *
 * Copyright (C) 2019-2026 WireGuard LLC. All Rights Reserved.
 */

package l18n

import "golang.org/x/text/language"

func lang() language.Tag {
	return language.English
}
