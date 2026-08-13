package health

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthzGet(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, Path, nil)
	rec := httptest.NewRecorder()

	Handler().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if rec.Body.String() != Body {
		t.Fatalf("body = %q, want %q", rec.Body.String(), Body)
	}
}

func TestHealthzRejectsUnsupportedMethod(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, Path, nil)
	rec := httptest.NewRecorder()

	Handler().ServeHTTP(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusMethodNotAllowed)
	}
}

func TestUnknownRoute(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/missing", nil)
	rec := httptest.NewRecorder()

	Handler().ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusNotFound)
	}
}
