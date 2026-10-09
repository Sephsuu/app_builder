#include <jni.h>
#include <memory>
#include <string>
#include <vector>
#include "sentencepiece_processor.h"

using sentencepiece::SentencePieceProcessor;
static void fail(JNIEnv *env, const std::string &message) {
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), message.c_str());
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_example_offline_1speech_1translator_NllbTokenizer_load(
        JNIEnv *env, jobject, jstring path) {
    const char *chars = env->GetStringUTFChars(path, nullptr);
    if (!chars) return 0;
    auto model = std::make_unique<SentencePieceProcessor>();
    auto status = model->Load(chars);
    env->ReleaseStringUTFChars(path, chars);
    if (!status.ok() || model->GetPieceSize() != 256000) {
        fail(env, "Invalid NLLB SentencePiece model");
        return 0;
    }
    return reinterpret_cast<jlong>(model.release());
}

extern "C" JNIEXPORT jintArray JNICALL
Java_com_example_offline_1speech_1translator_NllbTokenizer_encodeNative(
        JNIEnv *env, jobject, jlong handle, jbyteArray input) {
    const auto size = env->GetArrayLength(input);
    std::string text(size, '\0');
    env->GetByteArrayRegion(input, 0, size, reinterpret_cast<jbyte *>(text.data()));
    std::vector<int> ids;
    auto status = reinterpret_cast<SentencePieceProcessor *>(handle)->Encode(text, &ids);
    if (!status.ok()) { fail(env, status.ToString()); return nullptr; }
    auto output = env->NewIntArray(static_cast<jsize>(ids.size()));
    if (output) env->SetIntArrayRegion(output, 0, static_cast<jsize>(ids.size()), ids.data());
    return output;
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_example_offline_1speech_1translator_NllbTokenizer_decodeNative(
        JNIEnv *env, jobject, jlong handle, jintArray input) {
    const auto size = env->GetArrayLength(input);
    std::vector<int> ids(size);
    env->GetIntArrayRegion(input, 0, size, ids.data());
    std::string text;
    auto status = reinterpret_cast<SentencePieceProcessor *>(handle)->Decode(ids, &text);
    if (!status.ok()) { fail(env, status.ToString()); return nullptr; }
    auto output = env->NewByteArray(static_cast<jsize>(text.size()));
    if (output) env->SetByteArrayRegion(output, 0, static_cast<jsize>(text.size()),
                                       reinterpret_cast<const jbyte *>(text.data()));
    return output;
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_offline_1speech_1translator_NllbTokenizer_release(
        JNIEnv *, jobject, jlong handle) {
    delete reinterpret_cast<SentencePieceProcessor *>(handle);
}
