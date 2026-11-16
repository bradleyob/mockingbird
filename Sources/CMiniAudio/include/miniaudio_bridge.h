#ifndef MINIAUDIO_BRIDGE_H
#define MINIAUDIO_BRIDGE_H

/*
 * mb_ bridge over the vendored miniaudio (Vendor/miniaudio, 0.11.26).
 *
 * Every function returns an mb_result: 0 (MB_SUCCESS) or a negative miniaudio ma_result
 * code. Callers must check it; mb_result_description() turns it into text.
 *
 * Capture is mono float32. The miniaudio data callback only copies into a lock-free ring
 * buffer allocated by mb_capture_create; mb_capture_read drains it from any other thread.
 */

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int mb_result;

#define MB_SUCCESS 0
/* Returned when a capture device name does not match any device (miniaudio's MA_NO_DEVICE). */
#define MB_DEVICE_NOT_FOUND (-204)
/* Bytes reserved per device name by mb_list_capture_devices, including the terminator. */
#define MB_DEVICE_NAME_CAPACITY 256

typedef enum mb_backend {
  MB_BACKEND_DEFAULT = 0, /* platform default order (CoreAudio, PulseAudio, ALSA, ...) */
  MB_BACKEND_NULL = 1     /* miniaudio's null device: silence in real time, no hardware */
} mb_backend;

typedef struct mb_capture mb_capture;
typedef struct mb_decoder mb_decoder;

/* Human-readable description of an mb_result. Never NULL. */
const char *mb_result_description(mb_result result);

/*
 * Writes up to `capacity` capture-device names into `names`, each slot
 * MB_DEVICE_NAME_CAPACITY bytes and NUL-terminated, and the number written to `count`.
 */
mb_result mb_list_capture_devices(mb_backend backend, char *names, unsigned int capacity,
                                  unsigned int *count);

/*
 * Opens a mono float32 capture device at `sample_rate`. `device_name` NULL or "default"
 * selects the backend's default input; otherwise it must equal a listed name exactly
 * (MB_DEVICE_NOT_FOUND if not). `ring_frames` sizes the ring buffer. On success `*out`
 * owns the context, device and ring buffer; release it with mb_capture_destroy.
 */
mb_result mb_capture_create(mb_backend backend, const char *device_name, unsigned int sample_rate,
                            unsigned int ring_frames, mb_capture **out);
mb_result mb_capture_start(mb_capture *capture);
mb_result mb_capture_stop(mb_capture *capture);
/* Moves up to `max_frames` captured frames into `out`; `*frames_read` may be 0. */
mb_result mb_capture_read(mb_capture *capture, float *out, unsigned int max_frames,
                          unsigned int *frames_read);
/* Frames the callback could not store because the ring buffer was full. */
unsigned long long mb_capture_dropped_frames(mb_capture *capture);
/* Stops if needed and frees everything. Accepts NULL. */
void mb_capture_destroy(mb_capture *capture);

/*
 * Opens an audio file (WAV, FLAC, MP3) for decoding to mono float32 at `sample_rate`,
 * downmixing and resampling as needed.
 */
mb_result mb_decoder_open(const char *path, unsigned int sample_rate, mb_decoder **out);
/* Decodes up to `max_frames` frames; `*frames_read` is 0 only at end of file. */
mb_result mb_decoder_read(mb_decoder *decoder, float *out, unsigned int max_frames,
                          unsigned int *frames_read);
/* Accepts NULL. */
void mb_decoder_close(mb_decoder *decoder);

#ifdef __cplusplus
}
#endif

#endif /* MINIAUDIO_BRIDGE_H */
