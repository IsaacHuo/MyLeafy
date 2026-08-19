package com.myleafy.android.shared.model

import org.junit.Assert.assertEquals
import org.junit.Test

class CommentThreadGroupingTest {

    private fun comment(id: String, parent: String? = null, body: String = "c-$id") = CommentThreadDto(
        thread_root_id = parent ?: id,
        id = id,
        post_id = "post-1",
        author_id = "author-1",
        body = body,
        parent_comment_id = parent,
        reply_to_comment_id = parent,
    )

    @Test
    fun groupsRootAndReplies() {
        val threads = groupCommentThreads(
            listOf(
                comment("root1"),
                comment("reply1", parent = "root1"),
                comment("reply2", parent = "root1"),
                comment("root2"),
            ),
        )
        assertEquals(2, threads.size)
        assertEquals("root1", threads[0].root.id)
        assertEquals(listOf("reply1", "reply2"), threads[0].replies.map { it.id })
        assertEquals("root2", threads[1].root.id)
        assertEquals(0, threads[1].replies.size)
    }

    @Test
    fun emptyInputProducesEmptyThreads() {
        assertEquals(emptyList<CommentThread>(), groupCommentThreads(emptyList()))
    }

    @Test
    fun singleRootProducesSingleThread() {
        val threads = groupCommentThreads(listOf(comment("only")))
        assertEquals(1, threads.size)
        assertEquals("only", threads[0].root.id)
    }
}
