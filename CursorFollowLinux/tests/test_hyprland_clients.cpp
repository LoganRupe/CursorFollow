#include "hyprland_clients.h"

#include "check.h"

using namespace cf;

static const char* kClients = R"json([
  {
    "address": "0x55f0330b8760",
    "mapped": true,
    "hidden": false,
    "at": [1427, 38],
    "size": [2001, 1390],
    "workspace": {"id": 1, "name": "1"},
    "floating": false,
    "monitor": 0,
    "class": "chromium",
    "title": "ExpLAN - Chromium",
    "initialClass": "chromium",
    "initialTitle": "Chromium",
    "pid": 1547,
    "pinned": false,
    "fullscreen": 0,
    "focusHistoryID": 1
  },
  {
    "address": "0x55f032c2af20",
    "mapped": true,
    "hidden": false,
    "at": [1727, 38],
    "size": [1701, 1390],
    "workspace": {"id": 2, "name": "2"},
    "floating": true,
    "monitor": 0,
    "class": "slack",
    "title": "Slack",
    "pid": 1553,
    "pinned": true,
    "fullscreen": 1,
    "focusHistoryID": 0
  },
  {
    "address": "0x0",
    "class": "ghost",
    "title": "address zero is dropped"
  }
])json";

int main() {
    std::vector<TrackedWindow> windows;
    std::string err;
    CHECK(hyprland_clients::parse_clients(kClients, windows, &err));
    CHECK_EQ(err, "");
    CHECK_EQ(windows.size(), 2u);

    const TrackedWindow& c = windows[0];
    CHECK_EQ(c.address, 0x55f0330b8760ull);
    CHECK_EQ(c.export_handle(), 0x330b8760u);
    CHECK_EQ(c.address_hex(), "0x55f0330b8760");
    CHECK_EQ(c.app_id, "chromium");
    CHECK_EQ(c.title, "ExpLAN - Chromium");
    CHECK_EQ(c.initial_title, "Chromium");
    CHECK_EQ(c.x, 1427);
    CHECK_EQ(c.y, 38);
    CHECK_EQ(c.width, 2001);
    CHECK_EQ(c.height, 1390);
    CHECK_EQ(c.workspace_id, 1);
    CHECK_EQ(c.workspace_name, "1");
    CHECK_EQ(c.pid, 1547);
    CHECK(c.mapped && !c.hidden && !c.floating && !c.pinned);
    CHECK_EQ(c.fullscreen, 0);
    CHECK_EQ(c.focus_history_id, 1);
    CHECK_EQ(c.size_label(), "2001×1390");

    const TrackedWindow& s = windows[1];
    CHECK(s.floating && s.pinned);
    CHECK_EQ(s.fullscreen, 1);
    CHECK_EQ(s.focus_history_id, 0);
    CHECK_EQ(s.initial_title, "");  // missing member reads as empty, not a crash

    // Single object (activewindow) and the event-stream address form.
    TrackedWindow active;
    CHECK(hyprland_clients::parse_client(R"({"address":"0x55f0330e3f90","class":"teams-for-linux","title":"Teams","size":[1701,1390]})", active));
    CHECK_EQ(active.address, 0x55f0330e3f90ull);
    CHECK_EQ(hyprland_clients::parse_address("55f0330e3f90"), 0x55f0330e3f90ull);
    CHECK_EQ(hyprland_clients::parse_address("0x55f0330e3f90"), 0x55f0330e3f90ull);
    CHECK_EQ(hyprland_clients::parse_address(""), 0ull);

    // Malformed input reports rather than throws.
    std::vector<TrackedWindow> none;
    CHECK(!hyprland_clients::parse_clients("not json", none, &err));
    CHECK(!err.empty());
    CHECK(!hyprland_clients::parse_clients("{}", none, &err));
    TrackedWindow empty;
    CHECK(!hyprland_clients::parse_client("{}", empty, &err));  // no address

    return check_summary("test_hyprland_clients");
}
