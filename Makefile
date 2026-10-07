# DevisChat — commandes principales (à lancer depuis la racine du projet)
#   make install     installe l'environnement Python du serveur (.venv)
#   make test        lance tous les tests du serveur (mode mock, aucun appel à l'IA)
#   make render      rend les devis d'exemple en .docx et .pdf dans server/out/
#   make server      lance le serveur (lit server/.env)
#   make demo        lance le serveur en mode démo (MOCK_LLM=1, jeton « demo »)
#   make ios-build   génère le projet Xcode (XcodeGen) puis compile pour le simulateur
#   make ios-test    lance les tests unitaires iOS dans le simulateur
#   make ios-linux-check  compile + teste la logique iOS sans Mac (Docker, Swift Linux)

SHELL := /bin/bash
PY ?= python3
VENV := .venv
BIN := $(CURDIR)/$(VENV)/bin
# Simulateur : iPhone 16 si disponible, sinon le premier iPhone trouvé (surchargable : make ios-build SIM="iPhone 15")
SIM ?= $(shell ios/scripts/pick_simulator.sh 2>/dev/null)
XCODE_FLAGS = -project ios/DevisChat.xcodeproj -scheme DevisChat \
	-destination 'platform=iOS Simulator,name=$(SIM)' -derivedDataPath build/DerivedData

.PHONY: install test render server demo ios-gen ios-build ios-test ios-linux-check clean

install: $(VENV)/.installed

$(VENV)/.installed: server/requirements.txt
	$(PY) -m venv $(VENV)
	$(BIN)/pip install -q -r server/requirements.txt
	touch $@

test: install
	cd server && $(BIN)/python -m pytest -q

render: install
	cd server && $(BIN)/python -m scripts.render_fixtures

server: install
	./server/run_server.sh

demo: install
	MOCK_LLM=1 APP_TOKEN=demo ./server/run_server.sh

ios-gen:
	cd ios && xcodegen generate

ios-build: ios-gen
	xcodebuild $(XCODE_FLAGS) build

ios-test: ios-gen
	xcodebuild $(XCODE_FLAGS) test

ios-linux-check:
	ios/scripts/linux_check.sh

clean:
	rm -rf server/out build
