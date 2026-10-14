package com.aiterm.aiterm

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

/**
 * "aiterm/phone": phone files through Android's own picker (the Storage
 * Access Framework), so aiterm can work with just the folders and files the
 * user chose instead of all storage.
 *
 * A document is named by `tree` (a folder grant) plus `doc` (a document id
 * inside it; null for the folder itself), or by `doc` alone (a full
 * document uri: a single picked file, or one shared from another app).
 *
 * Also receives files shared to aiterm (Share → aiterm) for import.
 */
class PhoneFilesPlugin(private val activity: Activity, private val channel: MethodChannel) :
    MethodChannel.MethodCallHandler {
    companion object {
        const val PICK_TREE = 61
        const val PICK_FILES = 62
        private const val RW = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
    }

    private val main = Handler(Looper.getMainLooper())
    private val resolver get() = activity.contentResolver
    private var pending: MethodChannel.Result? = null
    private var persist = true

    /** Files shared to aiterm, waiting for the user to pick where they go. */
    private var shared: List<Map<String, Any?>> = emptyList()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFolder" -> pick(call, result, PICK_TREE) {
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(RW or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            }
            "pickFiles" -> pick(call, result, PICK_FILES) {
                Intent(Intent.ACTION_OPEN_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType("*/*")
                    .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                    .addFlags(RW or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            }
            "grants" -> io(result) { grants() }
            "release" -> io(result) {
                val uri = Uri.parse(call.argument<String>("uri"))
                try {
                    resolver.releasePersistableUriPermission(uri, RW)
                } catch (_: SecurityException) {
                    resolver.releasePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                null
            }
            "list" -> io(result) { list(call.argument("tree")!!, call.argument("doc")) }
            "create" -> io(result) {
                val parent = docUri(call.argument("tree"), call.argument("doc"))
                val name = call.argument<String>("name")!!
                val mime = if (call.argument<Boolean>("dir") == true) Document.MIME_TYPE_DIR else mimeOf(name)
                val created = DocumentsContract.createDocument(resolver, parent, mime, name)
                    ?: throw IllegalStateException("Couldn't create $name")
                DocumentsContract.getDocumentId(created)
            }
            "delete" -> io(result) {
                DocumentsContract.deleteDocument(resolver, docUri(call.argument("tree"), call.argument("doc")))
                null
            }
            "rename" -> io(result) {
                val renamed = DocumentsContract.renameDocument(
                    resolver, docUri(call.argument("tree"), call.argument("doc")), call.argument<String>("name")!!,
                )
                renamed?.let { DocumentsContract.getDocumentId(it) }
            }
            "readText" -> io(result) {
                resolver.openInputStream(docUri(call.argument("tree"), call.argument("doc")))!!
                    .use { it.readBytes().toString(Charsets.UTF_8) }
            }
            "writeText" -> io(result) {
                resolver.openOutputStream(docUri(call.argument("tree"), call.argument("doc")), "wt")!!
                    .use { it.write(call.argument<String>("text")!!.toByteArray()) }
                null
            }
            "importTo" -> io(result) {
                val dest = File(call.argument<String>("dest")!!)
                val items = call.argument<List<Map<String, String?>>>("items")!!
                items.map { importOne(it["tree"], it["doc"], dest).absolutePath }
            }
            "exportTo" -> io(result) {
                val parent = docUri(call.argument("tree"), call.argument("doc"))
                call.argument<List<String>>("paths")!!.map { exportOne(File(it), parent) }
            }
            "takeShared" -> {
                result.success(shared)
                shared = emptyList()
            }
            else -> result.notImplemented()
        }
    }

    // ---- Picking -----------------------------------------------------------

    private fun pick(call: MethodCall, result: MethodChannel.Result, request: Int, intent: () -> Intent) {
        pending?.success(null)
        pending = result
        persist = call.argument<Boolean>("persist") ?: true
        activity.startActivityForResult(intent(), request)
    }

    /** From MainActivity.onActivityResult. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_TREE && requestCode != PICK_FILES) return false
        val result = pending ?: return true
        pending = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(null)
            return true
        }
        val uris = buildList {
            data.data?.let { add(it) }
            data.clipData?.let { clip -> for (i in 0 until clip.itemCount) add(clip.getItemAt(i).uri) }
        }.distinct()
        if (persist) {
            for (uri in uris) {
                try {
                    resolver.takePersistableUriPermission(uri, RW)
                } catch (_: SecurityException) {
                    try {
                        resolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    } catch (_: SecurityException) {
                    }
                }
            }
        }
        thread(name = "phone-pick") {
            val picked = uris.map { describe(it, tree = requestCode == PICK_TREE) }
            main.post { result.success(picked) }
        }
        return true
    }

    // ---- Shared to aiterm ----------------------------------------------------

    /** An ACTION_SEND / ACTION_SEND_MULTIPLE intent: keep its files and tell Dart. */
    fun onShareIntent(intent: Intent?): Boolean {
        val action = intent?.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return false
        val uris = buildList {
            if (action == Intent.ACTION_SEND) {
                @Suppress("DEPRECATION")
                (intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))?.let { add(it) }
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { addAll(it) }
            }
            intent.clipData?.let { clip -> for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { add(it) } }
        }.distinct()
        intent.action = null // handled once
        if (uris.isEmpty()) return true
        thread(name = "phone-share") {
            val items = uris.map { describe(it, tree = false) }
            main.post {
                shared = items
                channel.invokeMethod("shared", null)
            }
        }
        return true
    }

    // ---- Reading -------------------------------------------------------------

    private fun docUri(tree: String?, doc: String?): Uri {
        if (tree == null) return Uri.parse(doc!!)
        val treeUri = Uri.parse(tree)
        return DocumentsContract.buildDocumentUriUsingTree(treeUri, doc ?: DocumentsContract.getTreeDocumentId(treeUri))
    }

    private fun describe(uri: Uri, tree: Boolean): Map<String, Any?> {
        val doc = if (tree) DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri)) else uri
        var name = uri.lastPathSegment?.substringAfterLast('/') ?: "file"
        var size = 0L
        try {
            resolver.query(doc, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    c.getStringOrNull(0)?.let { name = it }
                    if (!c.isNull(1)) size = c.getLong(1)
                }
            }
        } catch (_: Exception) {
        }
        return mapOf("uri" to uri.toString(), "name" to name, "tree" to tree, "size" to size)
    }

    private fun grants(): List<Map<String, Any?>> = resolver.persistedUriPermissions
        .filter { it.isReadPermission }
        .map { describe(it.uri, tree = DocumentsContract.isTreeUri(it.uri)) + ("writable" to it.isWritePermission) }

    private fun list(tree: String, doc: String?): List<Map<String, Any?>> {
        val treeUri = Uri.parse(tree)
        val parent = doc ?: DocumentsContract.getTreeDocumentId(treeUri)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parent)
        val cols = arrayOf(
            Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE,
            Document.COLUMN_SIZE, Document.COLUMN_LAST_MODIFIED,
        )
        val out = mutableListOf<Map<String, Any?>>()
        resolver.query(children, cols, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "doc" to c.getString(0),
                        "name" to (c.getStringOrNull(1) ?: c.getString(0)),
                        "dir" to (c.getStringOrNull(2) == Document.MIME_TYPE_DIR),
                        "size" to (if (c.isNull(3)) 0L else c.getLong(3)),
                        "modified" to (if (c.isNull(4)) 0L else c.getLong(4)),
                    ),
                )
            }
        }
        return out
    }

    // ---- Copying ---------------------------------------------------------------

    /** Copies a document (a folder recursively) into [destDir], never overwriting. */
    private fun importOne(tree: String?, doc: String?, destDir: File): File {
        val uri = docUri(tree, doc)
        val (name, mime) = nameAndMime(uri)
        val target = freeName(destDir, name)
        if (mime == Document.MIME_TYPE_DIR && tree != null) {
            target.mkdirs()
            val treeUri = Uri.parse(tree)
            val id = doc ?: DocumentsContract.getTreeDocumentId(treeUri)
            for (child in list(tree, id)) importOne(tree, child["doc"] as String, target)
        } else {
            destDir.mkdirs()
            resolver.openInputStream(uri)!!.use { input -> target.outputStream().use { input.copyTo(it) } }
        }
        return target
    }

    /** Copies a Linux file or folder into the phone folder [parent]; returns the new document's name. */
    private fun exportOne(file: File, parent: Uri): String {
        val name = freeDocName(parent, file.name)
        if (file.isDirectory) {
            // Children go under the new folder's own (tree-based) uri.
            val dir = DocumentsContract.createDocument(resolver, parent, Document.MIME_TYPE_DIR, name)
                ?: throw IllegalStateException("Couldn't create $name")
            file.listFiles()?.forEach { exportOne(it, dir) }
            return name
        }
        val created = DocumentsContract.createDocument(resolver, parent, mimeOf(name), name)
            ?: throw IllegalStateException("Couldn't create $name")
        file.inputStream().use { input -> resolver.openOutputStream(created, "wt")!!.use { input.copyTo(it) } }
        return name
    }

    private fun nameAndMime(uri: Uri): Pair<String, String?> {
        var name = uri.lastPathSegment?.substringAfterLast('/') ?: "file"
        var mime: String? = null
        try {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, Document.COLUMN_MIME_TYPE), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    c.getStringOrNull(0)?.let { name = it }
                    mime = c.getStringOrNull(1)
                }
            }
        } catch (_: Exception) {
            // Some providers (shares) only answer DISPLAY_NAME.
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getStringOrNull(0)?.let { name = it }
            }
        }
        return name.replace('/', '_') to mime
    }

    private fun freeName(dir: File, name: String): File {
        var f = File(dir, name)
        if (!f.exists()) return f
        val dot = name.lastIndexOf('.')
        val (stem, ext) = if (dot > 0) name.substring(0, dot) to name.substring(dot) else name to ""
        var n = 2
        while (true) {
            f = File(dir, "$stem ($n)$ext")
            if (!f.exists()) return f
            n++
        }
    }

    /** A name not used yet in the phone folder [parent] ("notes (2).txt"). */
    private fun freeDocName(parent: Uri, name: String): String {
        val existing = mutableSetOf<String>()
        try {
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(parent, DocumentsContract.getDocumentId(parent))
            resolver.query(children, arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { c ->
                while (c.moveToNext()) c.getStringOrNull(0)?.let { existing.add(it) }
            }
        } catch (_: Exception) {
        }
        if (name !in existing) return name
        val dot = name.lastIndexOf('.')
        val (stem, ext) = if (dot > 0) name.substring(0, dot) to name.substring(dot) else name to ""
        var n = 2
        while ("$stem ($n)$ext" in existing) n++
        return "$stem ($n)$ext"
    }

    private fun mimeOf(name: String): String =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase())
            ?: "application/octet-stream"

    private fun io(result: MethodChannel.Result, work: () -> Any?) {
        thread(name = "phone-files") {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("phone", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }
}

private fun Cursor.getStringOrNull(i: Int): String? = if (isNull(i)) null else getString(i)
