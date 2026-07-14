package hme

import "testing"

func TestBuildCookieHeaderPreservesQuotedAndUnquotedValues(t *testing.T) {
	cookies := map[string]string{
		"x-apple-group":         "false",
		"X-APPLE-WEBAUTH-USER": `"v=1:s=0:d=123"`,
		"session":               "abc==",
	}

	got := buildCookieHeader(cookies)
	want := `X-APPLE-WEBAUTH-USER="v=1:s=0:d=123"; session=abc==; x-apple-group=false`
	if got != want {
		t.Errorf("buildCookieHeader() = %q, want %q", got, want)
	}
}
