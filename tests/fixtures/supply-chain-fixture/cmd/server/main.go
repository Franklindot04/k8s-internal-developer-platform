package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"fixture/supply-chain-fixture/internal/health"
)

func main() {
	server := &http.Server{
		Addr:              ":8080",
		Handler:           health.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	rootContext, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	serverErrors := make(chan error, 1)
	go func() {
		log.Printf("supply-chain-fixture listening on %s", server.Addr)
		err := server.ListenAndServe()
		if errors.Is(err, http.ErrServerClosed) {
			serverErrors <- nil
			return
		}
		serverErrors <- err
	}()

	select {
	case <-rootContext.Done():
		shutdownContext, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		if err := server.Shutdown(shutdownContext); err != nil {
			log.Printf("graceful shutdown failed: %v", err)
			os.Exit(1)
		}
		if err := <-serverErrors; err != nil {
			log.Printf("server failed during shutdown: %v", err)
			os.Exit(1)
		}
	case err := <-serverErrors:
		if err != nil {
			log.Printf("server failed: %v", err)
			os.Exit(1)
		}
	}
}
