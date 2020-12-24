#ifdef __cplusplus
extern "C" __attribute__((visibility("default"))) __attribute__((used))
#endif
int
stockfish_init();

#ifdef __cplusplus
extern "C" __attribute__((visibility("default"))) __attribute__((used))
#endif
int
stockfish_main();

#ifdef __cplusplus
extern "C" __attribute__((visibility("default"))) __attribute__((used))
#endif
ssize_t
stockfish_stdin_write(char *data);

#ifdef __cplusplus
extern "C" __attribute__((visibility("default"))) __attribute__((used))
#endif
char *
stockfish_stdout_read();
