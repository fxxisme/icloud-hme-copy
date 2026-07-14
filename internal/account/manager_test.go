package account

import (
	"path/filepath"
	"testing"
)

func TestParseCookieInputHeaderStripsPairedQuotes(t *testing.T) {
	input := `plain=value; double="v=1:t=abc=="; single='token-value'`

	cookies, err := ParseCookieInput(input)
	if err != nil {
		t.Fatalf("ParseCookieInput() error = %v", err)
	}

	want := map[string]string{
		"plain":  "value",
		"double": "v=1:t=abc==",
		"single": "token-value",
	}
	for name, value := range want {
		if cookies[name] != value {
			t.Errorf("cookie %q = %q, want %q", name, cookies[name], value)
		}
	}
}

func TestFinalizeCookieImportNormalizesNameAndRemovesDuplicates(t *testing.T) {
	manager := &Manager{
		accounts: map[string]*Account{
			"acc_old_b": {ID: "acc_old_b", Name: "旧账号 B", RealEmail: "User.Name@Example.com"},
			"acc_keep":  {ID: "acc_keep", Name: "临时名称", RealEmail: "user.name@example.com"},
			"acc_other": {ID: "acc_other", Name: "其他账号", RealEmail: "other@example.com"},
			"acc_old_a": {ID: "acc_old_a", Name: "旧账号 A", RealEmail: " user.name@example.com "},
		},
		dataFile: filepath.Join(t.TempDir(), "accounts.json"),
	}

	account, removed, err := manager.FinalizeCookieImport("acc_keep")
	if err != nil {
		t.Fatalf("FinalizeCookieImport() error = %v", err)
	}
	if account.Name != "user.name" {
		t.Errorf("account.Name = %q, want %q", account.Name, "user.name")
	}
	if len(removed) != 2 || removed[0] != "acc_old_a" || removed[1] != "acc_old_b" {
		t.Errorf("removed = %v, want [acc_old_a acc_old_b]", removed)
	}
	if _, exists := manager.accounts["acc_old_a"]; exists {
		t.Error("acc_old_a was not removed")
	}
	if _, exists := manager.accounts["acc_old_b"]; exists {
		t.Error("acc_old_b was not removed")
	}
	if _, exists := manager.accounts["acc_other"]; !exists {
		t.Error("unrelated account was removed")
	}
}
