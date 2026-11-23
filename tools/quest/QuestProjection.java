package com.godot.game;

/** Reads the two submitted eye extents while Godot owns the projection layer on its render thread. */
public final class QuestProjection {
    static { System.loadLibrary("quest_projection"); }
    public static native long readEyeSize(long projectionLayer);
    private QuestProjection() {}
}
