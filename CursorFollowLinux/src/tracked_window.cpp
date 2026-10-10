#include "tracked_window.h"

#include <cstdio>

namespace cf {

std::string TrackedWindow::address_hex() const {
    char buf[32];
    std::snprintf(buf, sizeof buf, "0x%llx", static_cast<unsigned long long>(address));
    return buf;
}

std::string TrackedWindow::size_label() const {
    return std::to_string(width) + "×" + std::to_string(height);
}

const char* filter_mode_name(FilterMode mode) {
    switch (mode) {
        case FilterMode::All: return "All";
        case FilterMode::Exclude: return "Exclude";
        case FilterMode::Include: return "Include";
    }
    return "All";
}

bool filter_mode_from_name(const std::string& name, FilterMode& out) {
    if (name == "All") { out = FilterMode::All; return true; }
    if (name == "Exclude") { out = FilterMode::Exclude; return true; }
    if (name == "Include") { out = FilterMode::Include; return true; }
    return false;
}

}  // namespace cf
