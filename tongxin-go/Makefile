.PHONY: build run tidy clean

build:
	go build -o bin/api ./cmd/api

run:
	go run ./cmd/api

tidy:
	go mod tidy

clean:
	rm -rf bin/
