# CursorFollowLinux build. Plain GNU make on purpose: the only build-time tools
# are g++, pkg-config and wayland-scanner, all of which ship with a Wayland desktop.

VERSION ?= 1.0
PREFIX  ?= $(HOME)/.local
BUILD   ?= build

PKGS     := gtk4 wayland-client json-glib-1.0
CXX      ?= g++
CC       ?= gcc
SCANNER  ?= wayland-scanner

PKG_CFLAGS := $(shell pkg-config --cflags $(PKGS))
PKG_LIBS   := $(shell pkg-config --libs $(PKGS))

CXXFLAGS ?= -O2 -g
CXXFLAGS += -std=c++20 -Wall -Wextra -Wno-unused-parameter -Wno-missing-field-initializers \
            -DCF_VERSION=\"$(VERSION)\" -DG_LOG_DOMAIN=\"CursorFollow\" \
            -Isrc -I$(BUILD)/protocols $(PKG_CFLAGS)
CFLAGS   ?= -O2 -g
CFLAGS   += -Wall $(PKG_CFLAGS)

PROTOCOLS := hyprland-toplevel-export-v1 wlr-foreign-toplevel-management-unstable-v1
PROTO_HDR := $(patsubst %,$(BUILD)/protocols/%-client.h,$(PROTOCOLS))
PROTO_OBJ := $(patsubst %,$(BUILD)/protocols/%.o,$(PROTOCOLS))

APP_SRC := $(wildcard src/*.cpp)
APP_OBJ := $(patsubst src/%.cpp,$(BUILD)/obj/%.o,$(APP_SRC))
LIB_OBJ := $(filter-out $(BUILD)/obj/main.o,$(APP_OBJ))

TEST_SRC := $(wildcard tests/*.cpp)
TEST_BIN := $(patsubst tests/%.cpp,$(BUILD)/tests/%,$(TEST_SRC))

BIN := $(BUILD)/cursorfollow

.PHONY: all test install uninstall clean run

all: $(BIN)

$(BIN): $(APP_OBJ) $(PROTO_OBJ)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(PKG_LIBS)

$(BUILD)/obj/%.o: src/%.cpp $(PROTO_HDR)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -MMD -MP -c -o $@ $<

$(BUILD)/protocols/%-client.h: protocols/%.xml
	@mkdir -p $(dir $@)
	$(SCANNER) client-header $< $@

$(BUILD)/protocols/%.c: protocols/%.xml
	@mkdir -p $(dir $@)
	$(SCANNER) private-code $< $@

$(BUILD)/protocols/%.o: $(BUILD)/protocols/%.c $(PROTO_HDR)
	$(CC) $(CFLAGS) -c -o $@ $<

# Tests link the app objects minus main so they can exercise the real code.
$(BUILD)/tests/%: tests/%.cpp $(LIB_OBJ) $(PROTO_OBJ)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -Itests -o $@ $< $(LIB_OBJ) $(PROTO_OBJ) $(PKG_LIBS)

test: $(TEST_BIN)
	@set -e; for t in $(TEST_BIN); do echo "== $$t"; $$t; done

run: $(BIN)
	$(BIN)

install: $(BIN)
	install -Dm755 $(BIN) $(DESTDIR)$(PREFIX)/bin/cursorfollow
	install -Dm644 data/io.github.loganrupe.CursorFollowLinux.desktop $(DESTDIR)$(PREFIX)/share/applications/io.github.loganrupe.CursorFollowLinux.desktop
	install -Dm644 data/io.github.loganrupe.CursorFollowLinux.png $(DESTDIR)$(PREFIX)/share/icons/hicolor/512x512/apps/io.github.loganrupe.CursorFollowLinux.png
	-update-desktop-database $(DESTDIR)$(PREFIX)/share/applications 2>/dev/null
	-gtk-update-icon-cache -q -t $(DESTDIR)$(PREFIX)/share/icons/hicolor 2>/dev/null

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/cursorfollow \
	      $(DESTDIR)$(PREFIX)/share/applications/io.github.loganrupe.CursorFollowLinux.desktop \
	      $(DESTDIR)$(PREFIX)/share/icons/hicolor/512x512/apps/io.github.loganrupe.CursorFollowLinux.png

clean:
	rm -rf $(BUILD)

-include $(APP_OBJ:.o=.d)
