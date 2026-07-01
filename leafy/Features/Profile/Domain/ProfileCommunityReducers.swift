import Foundation

enum ProfileCommunityPostListReducer {
    static func applyingPostChange(
        _ updatedPost: CommunityPost,
        to posts: [CommunityPost],
        kind: ProfileCommunityPostListKind
    ) -> [CommunityPost] {
        if kind == .liked, !updatedPost.viewerHasLiked {
            return posts.filter { $0.id != updatedPost.id }
        }

        if kind == .favorited, !updatedPost.viewerHasFavorited {
            return posts.filter { $0.id != updatedPost.id }
        }

        return posts.map { $0.id == updatedPost.id ? updatedPost : $0 }
    }
}
