// Benchmark the exact native libraries packaged in an APK, without Flutter UI.
// Input: mono 16 kHz float32 PCM. Use a public sample, never private recordings.
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define LOAD(name, result, args) \
  result (*name) args = (result (*) args)dlsym(lib, #name); \
  if (!name) { fprintf(stderr, "Missing %s\n", #name); return 2; }

int main(int argc, char **argv) {
  if (argc != 5 && argc != 6) {
    fprintf(stderr, "usage: native_asr_benchmark model.bin audio.f32 language threads [beam_size]\n");
    return 2;
  }
  void *lib = dlopen("libwhisper_flutter.so", RTLD_NOW);
  if (!lib) { fprintf(stderr, "%s\n", dlerror()); return 2; }
  LOAD(wf_context_create, void *, (const char *, int, int, int, int, int));
  LOAD(wf_context_free, void, (void *));
  LOAD(wf_job_create, void *, (int));
  LOAD(wf_job_free, void, (void *));
  LOAD(wf_job_set_int, void, (void *, const char *, int64_t));
  LOAD(wf_job_set_string, void, (void *, const char *, const char *));
  LOAD(wf_run, char *, (void *, void *, const float *, int));
  LOAD(wf_string_free, void, (char *));
  LOAD(wf_last_error, const char *, (void));
  FILE *input = fopen(argv[2], "rb");
  if (!input) return 2;
  fseek(input, 0, SEEK_END);
  long bytes = ftell(input);
  rewind(input);
  if (bytes <= 0 || bytes % sizeof(float)) return 2;
  float *pcm = malloc(bytes);
  if (!pcm || fread(pcm, 1, bytes, input) != (size_t)bytes) return 2;
  fclose(input);
  void *ctx = wf_context_create(argv[1], 2, 0, 0, 0, 1);
  if (!ctx) { fprintf(stderr, "%s\n", wf_last_error()); return 1; }
  int beams = argc == 6 ? atoi(argv[5]) : 1;
  void *job = wf_job_create(beams > 1 ? 1 : 0);
  wf_job_set_int(job, "beam_size", beams);
  wf_job_set_int(job, "threads", atoi(argv[4]));
  wf_job_set_int(job, "greedy_best_of", 1);
  wf_job_set_int(job, "no_context", 1);
  wf_job_set_int(job, "no_timestamps", 1);
  wf_job_set_int(job, "token_timestamps", 0);
  wf_job_set_string(job, "language", argv[3]);
  char *json = wf_run(ctx, job, pcm, bytes / sizeof(float));
  if (json) { puts(json); wf_string_free(json); }
  else fprintf(stderr, "%s\n", wf_last_error());
  wf_job_free(job);
  wf_context_free(ctx);
  free(pcm);
  return json ? 0 : 1;
}
