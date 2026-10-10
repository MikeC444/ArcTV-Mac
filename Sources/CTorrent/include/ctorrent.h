#ifndef CTORRENT_H
#define CTORRENT_H

#ifdef __cplusplus
extern "C" {
#endif

/// A small C face on libtorrent: one session that holds one torrent at a time (the one being watched).
typedef struct ct_engine ct_engine;

typedef struct {
    int has_metadata;       /* 1 once the torrent's file list is known */
    int state;              /* 0 checking, 1 getting file list, 2 downloading, 3 finished or seeding */
    int num_peers;
    int num_seeds;
    double progress;        /* 0...1 of the files being downloaded */
    long long download_rate; /* bytes per second */
    int file_count;
} ct_status;

ct_engine *ct_create(void);
void ct_destroy(ct_engine *engine);

/// Replaces any torrent in the session with this magnet link, saving under save_path. 0 on success.
int ct_start(ct_engine *engine, const char *magnet, const char *save_path);
/// Stops the torrent and, with delete_files, removes what it downloaded.
void ct_stop(ct_engine *engine, int delete_files);

void ct_get_status(ct_engine *engine, ct_status *out);
/// Name (path inside the torrent) and size of a file. 0 on success.
int ct_file_info(ct_engine *engine, int index, char *name, int name_len, long long *size);
/// Where the file is (or will be) on disk. 0 on success.
int ct_file_path(ct_engine *engine, int index, char *path, int path_len);
/// Downloads only this file, in order. 0 on success.
int ct_select_file(ct_engine *engine, int index);
/// 1 if every piece covering bytes [offset, offset + length) of the file has arrived.
int ct_have_range(ct_engine *engine, int index, long long offset, long long length);
/// Asks for the next `pieces` pieces from this byte on first (the player jumped there).
void ct_stream_from(ct_engine *engine, int index, long long offset, int pieces);

#ifdef __cplusplus
}
#endif

#endif
