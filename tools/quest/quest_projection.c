#include <jni.h>
#include <stdint.h>
#include <openxr/openxr.h>

JNIEXPORT jlong JNICALL Java_com_godot_game_QuestProjection_readEyeSize(
        JNIEnv *env, jclass cls, jlong projection_layer) {
    (void)env;
    (void)cls;
    const XrCompositionLayerProjection *layer = (const void *)(uintptr_t)projection_layer;
    if (!layer || layer->type != XR_TYPE_COMPOSITION_LAYER_PROJECTION || layer->viewCount != 2 || !layer->views) {
        return 0;
    }
    const XrExtent2Di left = layer->views[0].subImage.imageRect.extent;
    const XrExtent2Di right = layer->views[1].subImage.imageRect.extent;
    if (left.width <= 0 || left.height <= 0 || left.width != right.width || left.height != right.height) {
        return 0;
    }
    return ((jlong)left.width << 32) | (uint32_t)left.height;
}
