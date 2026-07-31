/* SPDX-License-Identifier: MIT
 *
 * Copyright (C) 2019-2026 WireGuard LLC. All Rights Reserved.
 */

package ui

import (
	"runtime"
	"strings"

	"github.com/lxn/walk"
	"golang.zx2c4.com/wireguard/windows/driver"

	"golang.zx2c4.com/wireguard/windows/l18n"
	"golang.zx2c4.com/wireguard/windows/version"
)

var (
	easterEggIndex     = -1
	showingAboutDialog *walk.Dialog
)

func onAbout(owner walk.Form) {
	showError(runAboutDialog(owner), owner)
}

func runAboutDialog(owner walk.Form) error {
	if showingAboutDialog != nil {
		showingAboutDialog.Show()
		raise(showingAboutDialog.Handle())
		return nil
	}

	vbl := walk.NewVBoxLayout()
	vbl.SetMargins(walk.Margins{80, 20, 80, 20})
	vbl.SetSpacing(10)

	var disposables walk.Disposables
	defer disposables.Treat()

	var err error
	showingAboutDialog, err = walk.NewDialogWithFixedSize(owner)
	if err != nil {
		return err
	}
	defer func() {
		showingAboutDialog = nil
	}()
	disposables.Add(showingAboutDialog)
	showingAboutDialog.SetTitle(l18n.Sprintf("About Phobos"))
	showingAboutDialog.SetLayout(vbl)
	if icon, err := loadLogoIcon(32); err == nil {
		showingAboutDialog.SetIcon(icon)
	}

	font, _ := walk.NewFont("Segoe UI", 9, 0)
	showingAboutDialog.SetFont(font)

	iv, err := walk.NewImageView(showingAboutDialog)
	if err != nil {
		return err
	}
	iv.MouseUp().Attach(func(x, y int, button walk.MouseButton) {
		if easterEggIndex >= 0 && button == walk.RightButton {
			if icon, err := loadSystemIcon("moricons", int32(easterEggIndex), 128); err == nil {
				iv.SetImage(icon)
				easterEggIndex++
			} else {
				easterEggIndex = -1
				if logo, err := loadLogoIcon(128); err == nil {
					iv.SetImage(logo)
				}
			}
		}
	})
	if logo, err := loadLogoIcon(128); err == nil {
		iv.SetImage(logo)
	}
	iv.Accessibility().SetName(l18n.Sprintf("Phobos logo image"))

	wgLbl, err := walk.NewTextLabel(showingAboutDialog)
	if err != nil {
		return err
	}
	wgFont, _ := walk.NewFont("Segoe UI", 16, walk.FontBold)
	wgLbl.SetFont(wgFont)
	wgLbl.SetTextAlignment(walk.AlignHCenterVNear)
	wgLbl.SetText("Phobos")

	detailsLbl, err := walk.NewTextLabel(showingAboutDialog)
	if err != nil {
		return err
	}
	detailsLbl.SetTextAlignment(walk.AlignHCenterVNear)
	detailsLbl.SetText(l18n.Sprintf("App version: %s\nDriver version: %s\nGo version: %s\nOperating system: %s\nArchitecture: %s", version.Number, driver.Version(), strings.TrimPrefix(runtime.Version(), "go"), version.OsName(), version.Arch()))

	copyrightLbl, err := walk.NewTextLabel(showingAboutDialog)
	if err != nil {
		return err
	}
	copyrightFont, _ := walk.NewFont("Segoe UI", 7, 0)
	copyrightLbl.SetFont(copyrightFont)
	copyrightLbl.SetTextAlignment(walk.AlignHCenterVNear)
	copyrightLbl.SetText("Phobos")

	buttonCP, err := walk.NewComposite(showingAboutDialog)
	if err != nil {
		return err
	}
	hbl := walk.NewHBoxLayout()
	hbl.SetMargins(walk.Margins{VNear: 10})
	buttonCP.SetLayout(hbl)
	walk.NewHSpacer(buttonCP)
	closePB, err := walk.NewPushButton(buttonCP)
	if err != nil {
		return err
	}
	closePB.SetAlignment(walk.AlignHCenterVNear)
	closePB.SetText(l18n.Sprintf("Close"))
	closePB.Clicked().Attach(showingAboutDialog.Accept)
	walk.NewHSpacer(buttonCP)

	showingAboutDialog.SetDefaultButton(closePB)
	showingAboutDialog.SetCancelButton(closePB)

	disposables.Spare()

	showingAboutDialog.Run()

	return nil
}
