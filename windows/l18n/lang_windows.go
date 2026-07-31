/* SPDX-License-Identifier: MIT
 *
 * Copyright (C) 2019-2026 WireGuard LLC. All Rights Reserved.
 */

package l18n

import (
	"golang.org/x/sys/windows"
	"golang.org/x/text/language"
	"golang.org/x/text/message"
)

// lang returns the user preferred UI language we have most confident translation in the default catalog available.
func lang() (tag language.Tag) {
	tag = language.English
	confidence := language.No
	languages, err := windows.GetUserPreferredUILanguages(windows.MUI_LANGUAGE_NAME)
	if err != nil {
		return
	}
	for i := range languages {
		t, _, c := message.DefaultCatalog.Matcher().Match(message.MatchLanguage(languages[i]))
		if c > confidence {
			tag = t
			confidence = c
		}
	}
	return
}
