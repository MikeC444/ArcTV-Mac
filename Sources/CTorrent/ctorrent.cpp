#include "ctorrent.h"

#include <algorithm>
#include <cstring>
#include <memory>
#include <string>

#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/file_storage.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/torrent_flags.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_status.hpp>

struct ct_engine {
    lt::session session;
    lt::torrent_handle handle;
    std::string save_path;

    static lt::settings_pack makePack() {
        lt::settings_pack pack;
        pack.set_int(lt::settings_pack::alert_mask, 0);
        pack.set_str(lt::settings_pack::user_agent, "ArcTV/1.0 libtorrent");
        return pack;
    }

    ct_engine() : session(makePack()) {}
};

static std::shared_ptr<const lt::torrent_info> info_of(ct_engine *e) {
    if (!e->handle.is_valid()) return nullptr;
    return e->handle.torrent_file();
}

extern "C" {

ct_engine *ct_create(void) {
    try { return new ct_engine(); } catch (...) { return nullptr; }
}

void ct_destroy(ct_engine *engine) {
    delete engine;
}

int ct_start(ct_engine *engine, const char *magnet, const char *save_path) {
    if (!engine || !magnet || !save_path) return -1;
    try {
        if (engine->handle.is_valid()) {
            engine->session.remove_torrent(engine->handle, lt::session::delete_files);
            engine->handle = lt::torrent_handle();
        }
        lt::error_code ec;
        lt::add_torrent_params params = lt::parse_magnet_uri(magnet, ec);
        if (ec) return -2;
        params.save_path = save_path;
        params.flags |= lt::torrent_flags::sequential_download;
        engine->save_path = save_path;
        engine->handle = engine->session.add_torrent(params);
        return 0;
    } catch (...) {
        return -3;
    }
}

void ct_stop(ct_engine *engine, int delete_files) {
    if (!engine) return;
    try {
        if (engine->handle.is_valid()) {
            engine->session.remove_torrent(engine->handle, delete_files ? lt::session::delete_files : lt::remove_flags_t{});
        }
        engine->handle = lt::torrent_handle();
    } catch (...) {
    }
}

void ct_get_status(ct_engine *engine, ct_status *out) {
    if (!out) return;
    std::memset(out, 0, sizeof(*out));
    if (!engine) return;
    try {
        if (!engine->handle.is_valid()) return;
        lt::torrent_status status = engine->handle.status();
        out->has_metadata = status.has_metadata ? 1 : 0;
        switch (status.state) {
            case lt::torrent_status::checking_files:
            case lt::torrent_status::checking_resume_data: out->state = 0; break;
            case lt::torrent_status::downloading_metadata: out->state = 1; break;
            case lt::torrent_status::downloading: out->state = 2; break;
            default: out->state = 3; break;
        }
        out->num_peers = status.num_peers;
        out->num_seeds = status.num_seeds;
        out->progress = status.progress;
        out->download_rate = status.download_payload_rate;
        auto info = info_of(engine);
        out->file_count = info ? info->files().num_files() : 0;
    } catch (...) {
    }
}

int ct_file_info(ct_engine *engine, int index, char *name, int name_len, long long *size) {
    try {
        auto info = info_of(engine);
        if (!info || index < 0 || index >= info->files().num_files()) return -1;
        lt::file_index_t file{index};
        std::string path = info->files().file_path(file);
        if (name && name_len > 0) {
            std::strncpy(name, path.c_str(), static_cast<size_t>(name_len) - 1);
            name[name_len - 1] = 0;
        }
        if (size) *size = info->files().file_size(file);
        return 0;
    } catch (...) {
        return -2;
    }
}

int ct_file_path(ct_engine *engine, int index, char *path, int path_len) {
    try {
        auto info = info_of(engine);
        if (!info || index < 0 || index >= info->files().num_files() || !path || path_len <= 0) return -1;
        std::string full = engine->save_path + "/" + info->files().file_path(lt::file_index_t{index});
        std::strncpy(path, full.c_str(), static_cast<size_t>(path_len) - 1);
        path[path_len - 1] = 0;
        return 0;
    } catch (...) {
        return -2;
    }
}

int ct_select_file(ct_engine *engine, int index) {
    try {
        auto info = info_of(engine);
        if (!info || index < 0 || index >= info->files().num_files()) return -1;
        for (int i = 0; i < info->files().num_files(); i++) {
            engine->handle.file_priority(lt::file_index_t{i}, i == index ? lt::default_priority : lt::dont_download);
        }
        return 0;
    } catch (...) {
        return -2;
    }
}

int ct_have_range(ct_engine *engine, int index, long long offset, long long length) {
    try {
        auto info = info_of(engine);
        if (!info || index < 0 || index >= info->files().num_files() || length <= 0) return 0;
        lt::file_index_t file{index};
        long long size = info->files().file_size(file);
        if (offset < 0 || offset >= size) return 0;
        long long last = std::min(offset + length, size) - 1;
        int first_piece = static_cast<int>(info->map_file(file, offset, 1).piece);
        int last_piece = static_cast<int>(info->map_file(file, last, 1).piece);
        for (int piece = first_piece; piece <= last_piece; piece++) {
            if (!engine->handle.have_piece(lt::piece_index_t{piece})) return 0;
        }
        return 1;
    } catch (...) {
        return 0;
    }
}

void ct_stream_from(ct_engine *engine, int index, long long offset, int pieces) {
    try {
        auto info = info_of(engine);
        if (!info || index < 0 || index >= info->files().num_files()) return;
        lt::file_index_t file{index};
        long long size = info->files().file_size(file);
        if (offset < 0 || offset >= size) return;
        int first_piece = static_cast<int>(info->map_file(file, offset, 1).piece);
        int last_piece = static_cast<int>(info->map_file(file, size - 1, 1).piece);
        engine->handle.clear_piece_deadlines();
        if (pieces < 4) pieces = 4;
        for (int k = 0; k < pieces && first_piece + k <= last_piece; k++) {
            engine->handle.set_piece_deadline(lt::piece_index_t{first_piece + k}, 150 + k * 100);
        }
    } catch (...) {
    }
}

}
