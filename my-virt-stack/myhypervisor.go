package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	log.Printf("MyHypervisor v0.1 starting...")

	if err := os.MkdirAll("/var/lib/myhypervisor", 0755); err != nil && !os.IsExist(err) {
		log.Fatalf("Failed to create state directory: %v", err)
	}

	go func() {
		http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
			fmt.Fprintf(w, "OK\n")
		})
		log.Println("Health endpoint listening on :8080")
		if err := http.ListenAndServe(":8080", nil); err != nil {
			log.Printf("HTTP server error: %v", err)
		}
	}()

	go func() {
		for {
			log.Printf("Hypervisor running, managing VMs...")
			time.Sleep(30 * time.Second)
		}
	}()

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig
	log.Printf("Shutting down MyHypervisor...")
}
