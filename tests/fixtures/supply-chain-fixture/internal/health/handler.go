package health

import "net/http"

const (
	Path = "/healthz"
	Body = "ok\n"
)

func Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc(Path, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, "method not allowed\n", http.StatusMethodNotAllowed)
			return
		}

		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(Body))
	})
	return mux
}
