package com.aiterm.aiterm

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder

/** Records 16 kHz mono float PCM, the format Whistle expects, up to 30 s. */
class VoiceRecorder {
    companion object {
        const val RATE = 16000
        private const val MAX_SAMPLES = RATE * 30
    }

    private var record: AudioRecord? = null
    private var thread: Thread? = null
    @Volatile private var running = false
    private var samples = FloatArray(RATE * 5)
    private var count = 0

    // Caller has already obtained RECORD_AUDIO (MainActivity "requestMic").
    @SuppressLint("MissingPermission")
    fun start() {
        stop()
        val min = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT)
        val rec = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_FLOAT,
            maxOf(min, RATE / 2 * 4),
        )
        check(rec.state == AudioRecord.STATE_INITIALIZED) { "Microphone unavailable" }
        record = rec
        count = 0
        running = true
        rec.startRecording()
        thread = Thread {
            val buf = FloatArray(RATE / 10)
            while (running && count < MAX_SAMPLES) {
                val n = rec.read(buf, 0, buf.size, AudioRecord.READ_BLOCKING)
                if (n <= 0) continue
                if (count + n > samples.size) samples = samples.copyOf(minOf(MAX_SAMPLES, samples.size * 2))
                val take = minOf(n, samples.size - count)
                System.arraycopy(buf, 0, samples, count, take)
                count += take
            }
        }.apply { start() }
    }

    /** Stops and returns what was recorded (empty if nothing). */
    fun stop(): FloatArray {
        running = false
        thread?.join(1000)
        thread = null
        record?.let {
            try {
                it.stop()
            } catch (_: IllegalStateException) {
            }
            it.release()
        }
        record = null
        return samples.copyOf(count).also { count = 0 }
    }
}
