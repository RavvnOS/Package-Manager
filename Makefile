PREFIX ?= /usr/local

.PHONY: all test install clean

all: test

test:
	@bash tests/run_tests.sh

install:
	@PREFIX=$(PREFIX) bash install.sh

clean:
	rm -f *.db *.sqlite cli_test.db
