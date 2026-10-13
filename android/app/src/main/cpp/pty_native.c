#include <jni.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

static char **to_cstr_array(JNIEnv *env, jobjectArray arr) {
    int n = arr ? (*env)->GetArrayLength(env, arr) : 0;
    char **out = calloc(n + 1, sizeof(char *));
    for (int i = 0; i < n; i++) {
        jstring s = (jstring)(*env)->GetObjectArrayElement(env, arr, i);
        const char *cs = (*env)->GetStringUTFChars(env, s, NULL);
        out[i] = strdup(cs);
        (*env)->ReleaseStringUTFChars(env, s, cs);
        (*env)->DeleteLocalRef(env, s);
    }
    return out;
}

static void free_cstr_array(char **arr) {
    if (!arr) return;
    for (char **p = arr; *p; p++) free(*p);
    free(arr);
}

static void throw_io(JNIEnv *env, const char *what) {
    char msg[256];
    snprintf(msg, sizeof(msg), "%s: %s", what, strerror(errno));
    jclass cls = (*env)->FindClass(env, "java/io/IOException");
    (*env)->ThrowNew(env, cls, msg);
}

/* Returns [masterFd, pid]. Everything that allocates happens before fork():
 * the parent is a multithreaded JVM, so the child may only make
 * async-signal-safe calls until execve(). */
JNIEXPORT jintArray JNICALL
Java_com_aiterm_aiterm_NativePty_createSubprocess(
        JNIEnv *env, jclass clazz, jstring j_cwd, jobjectArray j_argv,
        jobjectArray j_envp, jint rows, jint cols) {
    const char *cwd_tmp = (*env)->GetStringUTFChars(env, j_cwd, NULL);
    char *cwd = strdup(cwd_tmp);
    (*env)->ReleaseStringUTFChars(env, j_cwd, cwd_tmp);
    char **argv = to_cstr_array(env, j_argv);
    char **envp = to_cstr_array(env, j_envp);

    int master = open("/dev/ptmx", O_RDWR | O_CLOEXEC);
    if (master < 0) {
        throw_io(env, "open /dev/ptmx");
        goto fail;
    }
    char slave_name[64];
    if (grantpt(master) || unlockpt(master) ||
        ptsname_r(master, slave_name, sizeof(slave_name))) {
        throw_io(env, "pty setup");
        close(master);
        goto fail;
    }

    struct winsize ws = {.ws_row = rows, .ws_col = cols};
    pid_t pid = fork();
    if (pid < 0) {
        throw_io(env, "fork");
        close(master);
        goto fail;
    }
    if (pid == 0) {
        sigset_t all;
        sigfillset(&all);
        sigprocmask(SIG_UNBLOCK, &all, NULL);
        setsid();
        int slave = open(slave_name, O_RDWR);
        if (slave < 0) _exit(126);
        ioctl(slave, TIOCSCTTY, 0);
        ioctl(slave, TIOCSWINSZ, &ws);
        dup2(slave, 0);
        dup2(slave, 1);
        dup2(slave, 2);
        if (slave > 2) close(slave);
        chdir(cwd);
        execve(argv[0], argv, envp);
        _exit(127);
    }

    free(cwd);
    free_cstr_array(argv);
    free_cstr_array(envp);
    jintArray result = (*env)->NewIntArray(env, 2);
    jint vals[2] = {master, (jint)pid};
    (*env)->SetIntArrayRegion(env, result, 0, 2, vals);
    return result;

fail:
    free(cwd);
    free_cstr_array(argv);
    free_cstr_array(envp);
    return NULL;
}

JNIEXPORT void JNICALL
Java_com_aiterm_aiterm_NativePty_setWindowSize(
        JNIEnv *env, jclass clazz, jint fd, jint rows, jint cols) {
    struct winsize ws = {.ws_row = rows, .ws_col = cols};
    ioctl(fd, TIOCSWINSZ, &ws);
}

JNIEXPORT jint JNICALL
Java_com_aiterm_aiterm_NativePty_waitFor(JNIEnv *env, jclass clazz, jint pid) {
    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return -1;
}
