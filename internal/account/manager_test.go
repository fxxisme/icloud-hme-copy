package account

import "testing"

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
