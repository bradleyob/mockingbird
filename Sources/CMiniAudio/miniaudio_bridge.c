/*
 * The one translation unit that compiles miniaudio's implementation, plus the mb_ bridge.
 * Package.swift is frozen, so build-time miniaudio options are set here.
 */
#define MA_NO_ENGINE
#define MA_NO_NODE_GRAPH
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_GENERATION
#define MA_NO_ENCODING
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include "miniaudio_bridge.h"

#include <stdlib.h>
#include <string.h>

_Static_assert(MB_DEVICE_NOT_FOUND == MA_NO_DEVICE, "MB_DEVICE_NOT_FOUND must mirror MA_NO_DEVICE");
_Static_assert(MB_DEVICE_NAME_CAPACITY >= MA_MAX_DEVICE_NAME_LENGTH + 1, "device name slot too small");

struct mb_capture {
  ma_context context;
  ma_device device;
  ma_pcm_rb ring;
  /* Written only by the audio callback; read approximately by mb_capture_dropped_frames. */
  volatile unsigned long long dropped_frames;
  int context_ready;
  int ring_ready;
  int device_ready;
};

struct mb_decoder {
  ma_decoder decoder;
};

const char *mb_result_description(mb_result result) {
  return ma_result_description((ma_result)result);
}

static mb_result mb_context_init(mb_backend backend, ma_context *context) {
  if (backend == MB_BACKEND_NULL) {
    ma_backend backends[] = {ma_backend_null};
    return ma_context_init(backends, 1, NULL, context);
  }
  return ma_context_init(NULL, 0, NULL, context);
}

mb_result mb_list_capture_devices(mb_backend backend, char *names, unsigned int capacity,
                                  unsigned int *count) {
  if (names == NULL || count == NULL) {
    return MA_INVALID_ARGS;
  }
  *count = 0;
  ma_context context;
  mb_result result = mb_context_init(backend, &context);
  if (result != MA_SUCCESS) {
    return result;
  }
  ma_device_info *capture_infos = NULL;
  ma_uint32 capture_count = 0;
  result = ma_context_get_devices(&context, NULL, NULL, &capture_infos, &capture_count);
  if (result == MA_SUCCESS) {
    unsigned int written = 0;
    for (ma_uint32 index = 0; index < capture_count && written < capacity; index += 1) {
      char *slot = names + (size_t)written * MB_DEVICE_NAME_CAPACITY;
      strncpy(slot, capture_infos[index].name, MB_DEVICE_NAME_CAPACITY - 1);
      slot[MB_DEVICE_NAME_CAPACITY - 1] = '\0';
      written += 1;
    }
    *count = written;
  }
  mb_result uninit = ma_context_uninit(&context);
  return result != MA_SUCCESS ? result : uninit;
}

/* Real-time thread: no allocation, no locks, no Swift. Copies into the ring buffer only. */
static void mb_capture_callback(ma_device *device, void *output, const void *input,
                                ma_uint32 frame_count) {
  (void)output;
  mb_capture *capture = (mb_capture *)device->pUserData;
  const float *source = (const float *)input;
  ma_uint32 remaining = frame_count;
  while (remaining > 0) {
    ma_uint32 writable = remaining;
    void *destination = NULL;
    if (ma_pcm_rb_acquire_write(&capture->ring, &writable, &destination) != MA_SUCCESS ||
        writable == 0) {
      break;
    }
    memcpy(destination, source, (size_t)writable * sizeof(float));
    if (ma_pcm_rb_commit_write(&capture->ring, writable) != MA_SUCCESS) {
      break;
    }
    source += writable;
    remaining -= writable;
  }
  capture->dropped_frames += remaining;
}

static mb_result mb_find_capture_device(ma_context *context, const char *name, ma_device_id *id) {
  ma_device_info *capture_infos = NULL;
  ma_uint32 capture_count = 0;
  mb_result result = ma_context_get_devices(context, NULL, NULL, &capture_infos, &capture_count);
  if (result != MA_SUCCESS) {
    return result;
  }
  for (ma_uint32 index = 0; index < capture_count; index += 1) {
    if (strcmp(capture_infos[index].name, name) == 0) {
      *id = capture_infos[index].id;
      return MA_SUCCESS;
    }
  }
  return MB_DEVICE_NOT_FOUND;
}

mb_result mb_capture_create(mb_backend backend, const char *device_name, unsigned int sample_rate,
                            unsigned int ring_frames, mb_capture **out) {
  if (out == NULL || sample_rate == 0 || ring_frames == 0) {
    return MA_INVALID_ARGS;
  }
  *out = NULL;
  mb_capture *capture = (mb_capture *)calloc(1, sizeof(mb_capture));
  if (capture == NULL) {
    return MA_OUT_OF_MEMORY;
  }

  mb_result result = mb_context_init(backend, &capture->context);
  if (result != MA_SUCCESS) {
    mb_capture_destroy(capture);
    return result;
  }
  capture->context_ready = 1;

  ma_device_id device_id;
  int use_named_device = device_name != NULL && strcmp(device_name, "default") != 0;
  if (use_named_device) {
    result = mb_find_capture_device(&capture->context, device_name, &device_id);
    if (result != MA_SUCCESS) {
      mb_capture_destroy(capture);
      return result;
    }
  }

  result = ma_pcm_rb_init(ma_format_f32, 1, ring_frames, NULL, NULL, &capture->ring);
  if (result != MA_SUCCESS) {
    mb_capture_destroy(capture);
    return result;
  }
  capture->ring_ready = 1;

  ma_device_config config = ma_device_config_init(ma_device_type_capture);
  config.capture.pDeviceID = use_named_device ? &device_id : NULL;
  config.capture.format = ma_format_f32;
  config.capture.channels = 1;
  config.sampleRate = sample_rate;
  config.dataCallback = mb_capture_callback;
  config.pUserData = capture;
  result = ma_device_init(&capture->context, &config, &capture->device);
  if (result != MA_SUCCESS) {
    mb_capture_destroy(capture);
    return result;
  }
  capture->device_ready = 1;

  *out = capture;
  return MA_SUCCESS;
}

mb_result mb_capture_start(mb_capture *capture) {
  if (capture == NULL || !capture->device_ready) {
    return MA_INVALID_ARGS;
  }
  return ma_device_start(&capture->device);
}

mb_result mb_capture_stop(mb_capture *capture) {
  if (capture == NULL || !capture->device_ready) {
    return MA_INVALID_ARGS;
  }
  if (ma_device_get_state(&capture->device) != ma_device_state_started) {
    return MA_SUCCESS;
  }
  return ma_device_stop(&capture->device);
}

mb_result mb_capture_read(mb_capture *capture, float *out, unsigned int max_frames,
                          unsigned int *frames_read) {
  if (capture == NULL || out == NULL || frames_read == NULL || !capture->ring_ready) {
    return MA_INVALID_ARGS;
  }
  *frames_read = 0;
  while (*frames_read < max_frames) {
    ma_uint32 readable = max_frames - *frames_read;
    void *source = NULL;
    mb_result result = ma_pcm_rb_acquire_read(&capture->ring, &readable, &source);
    if (result != MA_SUCCESS) {
      return result;
    }
    if (readable == 0) {
      break;
    }
    memcpy(out + *frames_read, source, (size_t)readable * sizeof(float));
    result = ma_pcm_rb_commit_read(&capture->ring, readable);
    if (result != MA_SUCCESS) {
      return result;
    }
    *frames_read += readable;
  }
  return MA_SUCCESS;
}

unsigned long long mb_capture_dropped_frames(mb_capture *capture) {
  return capture == NULL ? 0 : capture->dropped_frames;
}

void mb_capture_destroy(mb_capture *capture) {
  if (capture == NULL) {
    return;
  }
  if (capture->device_ready) {
    /* ma_device_uninit stops the device and joins its thread; it returns nothing. */
    ma_device_uninit(&capture->device);
  }
  if (capture->ring_ready) {
    ma_pcm_rb_uninit(&capture->ring);
  }
  if (capture->context_ready) {
    /* Nothing useful can be done with a teardown failure; the memory is freed either way. */
    (void)ma_context_uninit(&capture->context);
  }
  free(capture);
}

mb_result mb_decoder_open(const char *path, unsigned int sample_rate, mb_decoder **out) {
  if (path == NULL || out == NULL || sample_rate == 0) {
    return MA_INVALID_ARGS;
  }
  *out = NULL;
  mb_decoder *decoder = (mb_decoder *)calloc(1, sizeof(mb_decoder));
  if (decoder == NULL) {
    return MA_OUT_OF_MEMORY;
  }
  ma_decoder_config config = ma_decoder_config_init(ma_format_f32, 1, sample_rate);
  mb_result result = ma_decoder_init_file(path, &config, &decoder->decoder);
  if (result != MA_SUCCESS) {
    free(decoder);
    return result;
  }
  *out = decoder;
  return MA_SUCCESS;
}

mb_result mb_decoder_read(mb_decoder *decoder, float *out, unsigned int max_frames,
                          unsigned int *frames_read) {
  if (decoder == NULL || out == NULL || frames_read == NULL) {
    return MA_INVALID_ARGS;
  }
  ma_uint64 read = 0;
  mb_result result = ma_decoder_read_pcm_frames(&decoder->decoder, out, max_frames, &read);
  *frames_read = (unsigned int)read;
  if (result == MA_AT_END) {
    return MA_SUCCESS;
  }
  return result;
}

void mb_decoder_close(mb_decoder *decoder) {
  if (decoder == NULL) {
    return;
  }
  /* ma_decoder_uninit only fails on invalid arguments, which cannot happen here. */
  (void)ma_decoder_uninit(&decoder->decoder);
  free(decoder);
}
