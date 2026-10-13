#include <jni.h>
#include <fcntl.h>
#include <string>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

#include "needle.h"

// Needle keeps one process-global model and is not thread-safe; NeedlePlugin
// serializes every call onto a single thread, so no locking here.
namespace {

void throwIllegalState(JNIEnv *env, const std::string &msg) {
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), msg.c_str());
}

std::string lastError(const char *what) {
    const char *e = needle_last_error();
    return std::string(what) + ": " + (e ? e : "unknown error");
}

std::string utf(JNIEnv *env, jstring s) {
    if (!s) return {};
    const char *c = env->GetStringUTFChars(s, nullptr);
    std::string out(c);
    env->ReleaseStringUTFChars(s, c);
    return out;
}

}  // namespace

extern "C" JNIEXPORT void JNICALL
Java_com_aiterm_aiterm_NeedleNative_load(JNIEnv *env, jclass, jstring j_path) {
    std::string path = utf(env, j_path);
    int fd = open(path.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) return throwIllegalState(env, "cannot open " + path);
    struct stat st{};
    fstat(fd, &st);
    // The mapping is never unmapped: the engine reads weights in place for
    // the life of the process.
    void *data = mmap(nullptr, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (data == MAP_FAILED) return throwIllegalState(env, "mmap failed for " + path);
    if (needle_load(static_cast<const unsigned char *>(data), st.st_size) < 0) {
        munmap(data, st.st_size);
        throwIllegalState(env, lastError("needle_load"));
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_aiterm_aiterm_NeedleNative_init(JNIEnv *env, jclass, jstring j_system,
                                         jstring j_tools, jstring j_index) {
    std::string system = utf(env, j_system);
    std::string tools = utf(env, j_tools);
    std::string index = utf(env, j_index);
    if (needle_init(system.c_str(), tools.c_str(), index.empty() ? nullptr : index.c_str()) < 0) {
        throwIllegalState(env, lastError("needle_init"));
    }
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_aiterm_aiterm_NeedleNative_complete(JNIEnv *env, jclass, jstring j_input,
                                             jint max_tokens) {
    std::string input = utf(env, j_input);
    needle_reset();  // every request stands alone; no chat history
    std::vector<char> out(32 * 1024);
    int n = needle_complete(input.c_str(), nullptr, 0, max_tokens, out.data(),
                            static_cast<int>(out.size()));
    if (n < 0) {
        throwIllegalState(env, lastError("needle_complete"));
        return nullptr;
    }
    out.back() = '\0';
    return env->NewStringUTF(out.data());
}
