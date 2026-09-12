BINARY_NAME=ravpkg

.PHONY: all build test clean fmt vet build-darwin build-freebsd

all: build

build:
	go build -o $(BINARY_NAME) ./cmd/ravpkg

test:
	go test -v ./...

fmt:
	go fmt ./...

vet:
	go vet ./...

clean:
	rm -f $(BINARY_NAME) $(BINARY_NAME).exe *.db *.sqlite coverage.out

# Cross-compilation targets for ravynOS targets (Darwin and FreeBSD userland)
build-darwin:
	GOOS=darwin GOARCH=amd64 go build -o bin/$(BINARY_NAME)-darwin-amd64 ./cmd/ravpkg
	GOOS=darwin GOARCH=arm64 go build -o bin/$(BINARY_NAME)-darwin-arm64 ./cmd/ravpkg

build-freebsd:
	GOOS=freebsd GOARCH=amd64 go build -o bin/$(BINARY_NAME)-freebsd-amd64 ./cmd/ravpkg
