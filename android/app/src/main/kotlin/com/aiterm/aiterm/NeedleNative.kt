package com.aiterm.aiterm

object NeedleNative {
    init {
        System.loadLibrary("aiterm-needle")
    }

    @JvmStatic external fun load(path: String)

    @JvmStatic external fun init(systemPrompt: String, toolsJson: String, toolIndexPath: String)

    @JvmStatic external fun complete(input: String, maxTokens: Int): String
}
