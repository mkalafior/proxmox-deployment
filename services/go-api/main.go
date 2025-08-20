// golang service: go-api
package main

import (
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "os"
    "time"
)

type Response struct {
    Message   string `json:"message"`
    Service   string `json:"service"`
    Type      string `json:"type"`
    Runtime   string `json:"runtime"`
    Timestamp string `json:"timestamp,omitempty"`
}

func main() {
    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }

    http.HandleFunc("/", rootHandler)
    http.HandleFunc("/health", healthHandler)

    fmt.Printf("🚀 go-api (golang) running on http://0.0.0.0:%s\n", port)
    log.Fatal(http.ListenAndServe(":"+port, nil))
}

func rootHandler(w http.ResponseWriter, r *http.Request) {
    response := Response{
        Message: "Hello from go-api!",
        Service: "go-api",
        Type:    "golang",
        Runtime: "go",
    }
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(response)
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
    response := Response{
        Message:   "healthy",
        Service:   "go-api",
        Type:      "golang",
        Timestamp: time.Now().Format(time.RFC3339),
    }
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(response)
}
