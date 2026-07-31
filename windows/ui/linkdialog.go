//go:build windows

/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package ui

import (
	"strings"

	"github.com/lxn/walk"

	"golang.zx2c4.com/wireguard/windows/conf"
	"golang.zx2c4.com/wireguard/windows/l18n"
)

type LinkDialog struct {
	*walk.Dialog
	linkEdit *walk.TextEdit
	acceptPB *walk.PushButton
	link     string
}

func runLinkDialog(owner walk.Form) (string, bool) {
	dlg, err := newLinkDialog(owner)
	if err != nil {
		return "", false
	}
	if dlg.Run() != walk.DlgCmdOK {
		return "", false
	}
	return dlg.link, true
}

func clipboardPhobosLink() string {
	text, err := walk.Clipboard().Text()
	if err != nil || !conf.IsPhobosLink(text) {
		return ""
	}
	return strings.TrimSpace(text)
}

func newLinkDialog(owner walk.Form) (*LinkDialog, error) {
	var disposables walk.Disposables
	defer disposables.Treat()

	dlg := new(LinkDialog)
	var err error

	layout := walk.NewGridLayout()
	layout.SetSpacing(6)
	layout.SetMargins(walk.Margins{10, 10, 10, 10})
	layout.SetColumnStretchFactor(0, 1)

	if dlg.Dialog, err = walk.NewDialog(owner); err != nil {
		return nil, err
	}
	disposables.Add(dlg)
	dlg.SetTitle(l18n.Sprintf("Import tunnel from link"))
	dlg.SetLayout(layout)
	dlg.SetMinMaxSize(walk.Size{500, 220}, walk.Size{0, 0})
	if icon, err := loadSystemIcon("imageres", -3, 32); err == nil {
		dlg.SetIcon(icon)
	}

	hintLabel, err := walk.NewTextLabel(dlg)
	if err != nil {
		return nil, err
	}
	layout.SetRange(hintLabel, walk.Rectangle{0, 0, 2, 1})
	hintLabel.SetText(l18n.Sprintf("Paste a phobos:// link. The tunnel name is taken from the link."))

	if dlg.linkEdit, err = walk.NewTextEdit(dlg); err != nil {
		return nil, err
	}
	layout.SetRange(dlg.linkEdit, walk.Rectangle{0, 1, 2, 1})
	dlg.linkEdit.SetText(clipboardPhobosLink())
	dlg.linkEdit.TextChanged().Attach(dlg.updateAcceptButton)

	buttonsContainer, err := walk.NewComposite(dlg)
	if err != nil {
		return nil, err
	}
	layout.SetRange(buttonsContainer, walk.Rectangle{0, 2, 2, 1})
	buttonsLayout := walk.NewHBoxLayout()
	buttonsLayout.SetMargins(walk.Margins{})
	buttonsContainer.SetLayout(buttonsLayout)
	walk.NewHSpacer(buttonsContainer)

	if dlg.acceptPB, err = walk.NewPushButton(buttonsContainer); err != nil {
		return nil, err
	}
	dlg.acceptPB.SetText(l18n.Sprintf("&Import"))
	dlg.acceptPB.Clicked().Attach(dlg.onImport)

	cancelPB, err := walk.NewPushButton(buttonsContainer)
	if err != nil {
		return nil, err
	}
	cancelPB.SetText(l18n.Sprintf("Cancel"))
	cancelPB.Clicked().Attach(dlg.Cancel)

	dlg.SetCancelButton(cancelPB)
	dlg.SetDefaultButton(dlg.acceptPB)
	dlg.updateAcceptButton()

	disposables.Spare()

	return dlg, nil
}

func (dlg *LinkDialog) updateAcceptButton() {
	dlg.acceptPB.SetEnabled(conf.IsPhobosLink(dlg.linkEdit.Text()))
}

func (dlg *LinkDialog) onImport() {
	link := strings.TrimSpace(dlg.linkEdit.Text())
	if _, _, err := conf.DecodePhobosLink(link); err != nil {
		showErrorCustom(dlg, l18n.Sprintf("Invalid link"), err.Error())
		return
	}
	dlg.link = link
	dlg.Accept()
}
