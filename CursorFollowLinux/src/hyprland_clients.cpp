#include "hyprland_clients.h"

#include <json-glib/json-glib.h>

#include <cstdlib>

namespace cf::hyprland_clients {

uint64_t parse_address(const std::string& text) {
    return std::strtoull(text.c_str(), nullptr, 16);
}

namespace {

std::string member_string(JsonObject* obj, const char* key) {
    if (!json_object_has_member(obj, key)) return {};
    JsonNode* node = json_object_get_member(obj, key);
    if (!node || json_node_get_node_type(node) != JSON_NODE_VALUE) return {};
    if (json_node_get_value_type(node) != G_TYPE_STRING) return {};
    const gchar* s = json_node_get_string(node);
    return s ? s : "";
}

int member_int(JsonObject* obj, const char* key, int fallback) {
    if (!json_object_has_member(obj, key)) return fallback;
    JsonNode* node = json_object_get_member(obj, key);
    if (!node || json_node_get_node_type(node) != JSON_NODE_VALUE) return fallback;
    GType t = json_node_get_value_type(node);
    if (t == G_TYPE_INT64) return static_cast<int>(json_node_get_int(node));
    if (t == G_TYPE_DOUBLE) return static_cast<int>(json_node_get_double(node));
    if (t == G_TYPE_BOOLEAN) return json_node_get_boolean(node) ? 1 : 0;
    return fallback;
}

bool member_bool(JsonObject* obj, const char* key, bool fallback) {
    if (!json_object_has_member(obj, key)) return fallback;
    JsonNode* node = json_object_get_member(obj, key);
    if (!node || json_node_get_node_type(node) != JSON_NODE_VALUE) return fallback;
    if (json_node_get_value_type(node) != G_TYPE_BOOLEAN) return fallback;
    return json_node_get_boolean(node) != FALSE;
}

bool read_client(JsonObject* obj, TrackedWindow& w) {
    w.address = parse_address(member_string(obj, "address"));
    w.title = member_string(obj, "title");
    w.app_id = member_string(obj, "class");
    w.initial_title = member_string(obj, "initialTitle");
    w.pid = member_int(obj, "pid", 0);
    w.mapped = member_bool(obj, "mapped", true);
    w.hidden = member_bool(obj, "hidden", false);
    w.floating = member_bool(obj, "floating", false);
    w.pinned = member_bool(obj, "pinned", false);
    w.fullscreen = member_int(obj, "fullscreen", 0);
    w.monitor = member_int(obj, "monitor", -1);
    w.focus_history_id = member_int(obj, "focusHistoryID", -1);

    if (json_object_has_member(obj, "at")) {
        JsonArray* at = json_object_get_array_member(obj, "at");
        if (at && json_array_get_length(at) >= 2) {
            w.x = static_cast<int>(json_array_get_int_element(at, 0));
            w.y = static_cast<int>(json_array_get_int_element(at, 1));
        }
    }
    if (json_object_has_member(obj, "size")) {
        JsonArray* size = json_object_get_array_member(obj, "size");
        if (size && json_array_get_length(size) >= 2) {
            w.width = static_cast<int>(json_array_get_int_element(size, 0));
            w.height = static_cast<int>(json_array_get_int_element(size, 1));
        }
    }
    if (json_object_has_member(obj, "workspace")) {
        JsonObject* ws = json_object_get_object_member(obj, "workspace");
        if (ws) {
            w.workspace_id = member_int(ws, "id", 0);
            w.workspace_name = member_string(ws, "name");
        }
    }
    return w.address != 0;
}

}  // namespace

bool parse_clients(const std::string& json, std::vector<TrackedWindow>& out, std::string* error) {
    JsonParser* parser = json_parser_new();
    GError* err = nullptr;
    if (!json_parser_load_from_data(parser, json.c_str(), static_cast<gssize>(json.size()), &err)) {
        if (error) *error = err ? err->message : "invalid JSON";
        g_clear_error(&err);
        g_object_unref(parser);
        return false;
    }
    JsonNode* root = json_parser_get_root(parser);
    if (!root || !JSON_NODE_HOLDS_ARRAY(root)) {
        if (error) *error = "expected a JSON array of clients";
        g_object_unref(parser);
        return false;
    }
    JsonArray* arr = json_node_get_array(root);
    guint n = json_array_get_length(arr);
    out.clear();
    out.reserve(n);
    for (guint i = 0; i < n; ++i) {
        JsonNode* node = json_array_get_element(arr, i);
        if (!node || !JSON_NODE_HOLDS_OBJECT(node)) continue;
        TrackedWindow w;
        if (read_client(json_node_get_object(node), w)) out.push_back(std::move(w));
    }
    g_object_unref(parser);
    return true;
}

bool parse_client(const std::string& json, TrackedWindow& out, std::string* error) {
    JsonParser* parser = json_parser_new();
    GError* err = nullptr;
    if (!json_parser_load_from_data(parser, json.c_str(), static_cast<gssize>(json.size()), &err)) {
        if (error) *error = err ? err->message : "invalid JSON";
        g_clear_error(&err);
        g_object_unref(parser);
        return false;
    }
    JsonNode* root = json_parser_get_root(parser);
    bool ok = root && JSON_NODE_HOLDS_OBJECT(root) && read_client(json_node_get_object(root), out);
    if (!ok && error) *error = "no active window";
    g_object_unref(parser);
    return ok;
}

}  // namespace cf::hyprland_clients
