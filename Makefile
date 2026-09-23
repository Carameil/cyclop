APP := build/Cyclop.app
DEST := /Applications/Cyclop.app

.PHONY: update pull build install test

update:
	$(MAKE) pull
	$(MAKE) install

pull:
	git pull --ff-only

build:
	./Scripts/bundle.sh

install: build
	-pkill -x Cyclop
	@while pgrep -x Cyclop >/dev/null; do sleep 0.2; done
	rm -rf "$(DEST)"
	cp -R "$(APP)" "$(DEST)"
	open "$(DEST)"

test:
	./Scripts/test.sh
