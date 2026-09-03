# TapeTree catalog pipeline. Run from this directory.
# Full rebuild: make all   (crawl is resume-safe; re-runs only fetch new items)

PY := python3
PIPE := pipeline
FIXTURE_DATES := 1977-05-08,1972-05-04,1969-02-27,1970-02-13,1989-07-07,1995-07-09,1966-01-08,1978-04-24,1985-06-24,1990-03-29,1974-06-28,1982-04-06
APP_CATALOG := ../../ShakedownAI/Resources/catalog/catalog.sqlite
FIXTURE_OUT := ../../ShakedownAITests/Fixtures/catalog-fixture.sqlite

.PHONY: crawl setlists metadata build images digests fixture install all test

crawl:
	cd $(PIPE) && $(PY) stage1_search.py

setlists:
	cd $(PIPE) && $(PY) stage3_setlists.py

metadata:
	cd $(PIPE) && $(PY) stage2_metadata.py

build:
	cd $(PIPE) && $(PY) stage4_build.py

images:
	cd $(PIPE) && $(PY) stage4_build.py --no-gates  # stage_images needs the date list
	cd $(PIPE) && $(PY) stage_images.py --offline   # re-parses cached jerrygarcia.com pages
	cd $(PIPE) && $(PY) stage4_build.py             # re-embed with gallery.json, gated

digests: build
	cd $(PIPE) && $(PY) stage5_digests.py
	cd $(PIPE) && $(PY) stage4_build.py   # re-embed with digests

fixture:
	cd $(PIPE) && $(PY) stage4_build.py --fixture $(FIXTURE_DATES) --out $(abspath $(FIXTURE_OUT))

install: build
	mkdir -p $(dir $(APP_CATALOG))
	cp $(PIPE)/../out/catalog.sqlite $(APP_CATALOG)
	cd $(PIPE) && $(PY) stage6_backfill.py

test:
	$(PY) -m pytest tests -q

all: crawl setlists metadata build images fixture install
