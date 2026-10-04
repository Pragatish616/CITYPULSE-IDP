.PHONY: help setup city-fetch city-pack region-pack packs router-cli test fmt study1 study1-rescore study2 verifier-eval app-web clean

# F-19 (2026-10-02): the old targets named scripts that do not exist (build_graph.py,
# study1_replay.py, study3_faithfulness.py) and a bin/ path the harness does not read. These
# targets call the scripts and paths that exist. The graph itself is a pinned snapshot under
# data/graph/2026-09-14 (built once by scripts/t1_3_build_graph_and_prior.py).

ROUTER_BIN ?= data/bin/2026-10-02/pulse_router.exe

help:
	@grep -E '^[a-z0-9-]+:.*?##' $(MAKEFILE_LIST) | sed 's/:.*##/	/'

setup:            ## install python + dart deps
	pip install -r server/requirements.txt
	pip install -r scripts/requirements.txt
	cd packages/pulse_belief && dart pub get
	cd packages/pulse_router && dart pub get
	cd packages/pulse_explain && dart pub get
	cd services/router_api && dart pub get

city-fetch:       ## fetch a city's roads from Overpass (CITY=<id>; network)
	python scripts/city_pipeline.py fetch --city $(CITY)

city-pack:        ## build a routing-only pack for a city (CITY=<id> DATE=<yyyy-mm-dd>)
	python scripts/city_pipeline.py pack --city $(CITY) --date $(DATE)

region-pack:      ## build a region pack from a Geofabrik extract (CITY=<id> LEVELS=backbone DATE=<yyyy-mm-dd>; needs pyosmium)
	python scripts/region_pack.py --city $(CITY) --levels $(LEVELS) --date $(DATE)

packs:            ## build the binary map pack the app and router_api load
	python scripts/build_packs.py

router-cli:       ## AOT-compile the router CLI the harness calls (dated build, never overwrites)
	mkdir -p $(dir $(ROUTER_BIN))
	cd packages/pulse_router && dart compile exe bin/pulse_router.dart -o ../../$(ROUTER_BIN)

test:             ## run all tests
	cd packages/pulse_belief && dart test
	cd packages/pulse_router && dart test
	cd packages/pulse_explain && dart test
	cd services/router_api && dart test
	pytest scripts/tests server

fmt:              ## format everything
	dart format packages services app
	ruff check --fix server scripts && black server scripts

study1:           ## route quality replay (needs router-cli)
	PULSE_ROUTER_BIN=$(ROUTER_BIN) python scripts/study1_route_quality.py
study1-rescore:   ## re-score study1 routes under one reference belief (needs study1)
	PULSE_ROUTER_BIN=$(ROUTER_BIN) python scripts/study1_rescore.py
study2:           ## confidence calibration
	python scripts/study2_calibration.py
verifier-eval:    ## explanation-gate error rates on the authored case set
	cd packages/pulse_explain && dart test test/verifier_eval_test.dart

app-web:          ## build the Flutter web app (map pack must be synced first)
	cd app && bash scripts/sync_data_assets.sh && flutter pub get && flutter build web --release --no-web-resources-cdn

clean:
	rm -rf build .dart_tool __pycache__
