#include <jni.h>
#include <stdint.h>
#include <string.h>

#define MAX_DUMMY_LENGTH_TOTAL          1024
#define MAX_DUMMY_LENGTH_HANDSHAKE      512

#include "obfuscation.h"

JNIEXPORT jint JNICALL
Java_com_wireguard_android_backend_obfuscator_NativeObfuscator_nativeEncode(
        JNIEnv *env, jclass clazz, jbyteArray buffer, jint length, jbyteArray key, jint maxDummy, jint obfuscateBytes) {
    if (buffer == NULL || key == NULL || length < 0)
        return -1;

    const jsize capacity = (*env)->GetArrayLength(env, buffer);
    const jsize key_length = (*env)->GetArrayLength(env, key);
    if (length > capacity || key_length <= 0)
        return -1;

    jbyte *buf = (*env)->GetByteArrayElements(env, buffer, NULL);
    jbyte *k = (*env)->GetByteArrayElements(env, key, NULL);
    if (buf == NULL || k == NULL) {
        if (buf != NULL) (*env)->ReleaseByteArrayElements(env, buffer, buf, JNI_ABORT);
        if (k != NULL) (*env)->ReleaseByteArrayElements(env, key, k, JNI_ABORT);
        return -1;
    }

    int new_length = encode((uint8_t *) buf, length, (char *) k, key_length,
                            OBFUSCATION_VERSION, maxDummy < 0 ? 0 : maxDummy,
                            obfuscateBytes < 0 ? 0 : obfuscateBytes);

    (*env)->ReleaseByteArrayElements(env, buffer, buf, 0);
    (*env)->ReleaseByteArrayElements(env, key, k, JNI_ABORT);
    return new_length;
}

JNIEXPORT jint JNICALL
Java_com_wireguard_android_backend_obfuscator_NativeObfuscator_nativeDecode(
        JNIEnv *env, jclass clazz, jbyteArray buffer, jint length, jbyteArray key, jint obfuscateBytes) {
    if (buffer == NULL || key == NULL || length < 0)
        return -1;

    const jsize capacity = (*env)->GetArrayLength(env, buffer);
    const jsize key_length = (*env)->GetArrayLength(env, key);
    if (length > capacity || key_length <= 0)
        return -1;

    jbyte *buf = (*env)->GetByteArrayElements(env, buffer, NULL);
    jbyte *k = (*env)->GetByteArrayElements(env, key, NULL);
    if (buf == NULL || k == NULL) {
        if (buf != NULL) (*env)->ReleaseByteArrayElements(env, buffer, buf, JNI_ABORT);
        if (k != NULL) (*env)->ReleaseByteArrayElements(env, key, k, JNI_ABORT);
        return -1;
    }

    uint8_t version = 0;
    int new_length = decode((uint8_t *) buf, length, (char *) k, key_length, &version,
                            obfuscateBytes < 0 ? 0 : obfuscateBytes);

    (*env)->ReleaseByteArrayElements(env, buffer, buf, 0);
    (*env)->ReleaseByteArrayElements(env, key, k, JNI_ABORT);
    return new_length;
}
