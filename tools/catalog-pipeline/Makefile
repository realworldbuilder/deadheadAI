# Nethead catalog pipeline. Run from this directory.
# Full rebuild: make all   (crawl is resume-safe; re-runs only fetch new items)

PY := python3
PIPE := pipeline
FIXTURE_DATES := 1977-05-08,1972-05-04,1969-02-27,1970-02-13,1989-07-07,1995-07-09,1966-01-08,1978-04-24,1985-06-24,1990-03-29,1974-06-28,1982-04-06
APP_CATALOG := ../../ShakedownAI/Resources/catalog/catalog.sqlite
FIXTURE_OUT := ../../ShakedownAITests/Fixtures/catalog-fixture.sqlite
WEB := ../../web
D1_OUT := out/d1
D1_FIXTURE_DIR := $(WEB)/test/fixtures

.PHONY: crawl setlists metadata build tracks images digests fixture install all test d1-sql d1 d1-local d1-fixture

crawl:
	cd $(PIPE) && $(PY) stage1_search.py

setlists:
	cd $(PIPE) && $(PY) stage3_setlists.py

metadata:
	cd $(PIPE) && $(PY) stage2_metadata.py

build:
	cd $(PIPE) && $(PY) stage4_build.py

tracks:
	cd $(PIPE) && $(PY) stage2b_tracks.py   # needs out/catalog.sqlite for the per-show ranking
	cd $(PIPE) && $(PY) stage4_build.py     # re-embed with recording_tracks

images:
	cd $(PIPE) && $(PY) stage4_build.py --no-gates  # stage_images needs the date list
	cd $(PIPE) && $(PY) stage_images.py --offline   # re-parses cached jerrygarcia.com pages
	cd $(PIPE) && $(PY) stage4_build.py             # re-embed with gallery.json, gated

digests: build
	cd $(PIPE) && $(PY) stage5_digests.py
	cd $(PIPE) && $(PY) stage4_build.py   # re-embed with digests

fixture:
	cd $(PIPE) && $(PY) stage4_build.py --fixture $(FIXTURE_DATES) --out $(abspath $(FIXTURE_OUT))
	$(MAKE) d1-fixture

# --- The web notesfile's copy of the catalog (Cloudflare D1) ---------------
# d1-sql dumps the app's catalog into D1-friendly SQL parts; d1 pushes them to
# the remote database (needs `npx wrangler login` once, from web/) and d1-local
# into wrangler's local state for `npm run dev`. A full push writes ~65k rows —
# most of a free-tier day's write quota — so it's a once-per-catalog job.
d1-sql:
	cd $(PIPE) && $(PY) stage7_d1.py --in $(abspath $(APP_CATALOG)) --out-dir $(abspath $(D1_OUT))

d1: d1-sql
	cd $(WEB) && for f in $(abspath $(D1_OUT))/catalog.tables.*.sql $(abspath $(D1_OUT))/catalog.fts.*.sql; do \
	  echo "== $$f"; npx wrangler d1 execute nethead-catalog --remote --yes --file "$$f" || exit 1; done

d1-local: d1-sql
	cd $(WEB) && for f in $(abspath $(D1_OUT))/catalog.tables.*.sql $(abspath $(D1_OUT))/catalog.fts.*.sql; do \
	  echo "== $$f"; npx wrangler d1 execute nethead-catalog --local --yes --file "$$f" || exit 1; done

d1-fixture:
	cd $(PIPE) && $(PY) stage7_d1.py --in $(abspath $(FIXTURE_OUT)) --out-dir $(abspath $(D1_FIXTURE_DIR)) --single

install: build
	mkdir -p $(dir $(APP_CATALOG))
	cp $(PIPE)/../out/catalog.sqlite $(APP_CATALOG)
	cd $(PIPE) && $(PY) stage6_backfill.py

test:
	$(PY) -m pytest tests -q

all: crawl setlists metadata build tracks images fixture install
